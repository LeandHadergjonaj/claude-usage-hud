import Foundation

/// One rate-limit bucket: how much is used and when it resets.
struct UsageBucket {
    let percentage: Int
    let resetsAt: Date?
}

/// A full usage reading across the buckets Claude exposes.
struct Usage {
    let session: UsageBucket            // current 5-hour session
    let weeklyAllModels: UsageBucket?   // rolling 7-day, all models
    let weeklySonnet: UsageBucket?      // rolling 7-day, Sonnet only
}

/// Errors surfaced to the UI so it can react (re-prompt for the key, show a
/// transient network error, etc.).
enum ClaudeAPIError: LocalizedError {
    /// The cookie was rejected (401/403) — expired or wrong value.
    case unauthorized
    /// Couldn't determine the organization id from `/api/account`.
    case noOrganization
    /// The usage response didn't contain a recognizable session percentage.
    case unrecognizedUsage
    /// Any non-2xx HTTP status that isn't an auth failure.
    case http(Int)
    /// Transport-level failure (offline, DNS, TLS, …).
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session key was rejected. It may have expired — paste a fresh one."
        case .noOrganization:
            return "Couldn't read your account. Try again or re-paste the key."
        case .unrecognizedUsage:
            return "Claude returned usage data in an unexpected format."
        case .http(let code):
            return "Claude returned HTTP \(code)."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Talks to Claude.ai's internal web API using the user's `sessionKey` cookie.
///
/// Flow: resolve the organization id once via `GET /api/account`, then poll
/// `GET /api/organizations/{orgId}/usage`. The org id is cached (in memory and
/// UserDefaults) so steady-state polling is a single request.
final class ClaudeAPIClient {
    static let shared = ClaudeAPIClient()

    private static let base = "https://claude.ai"
    private static let orgDefaultsKey = "com.claudeusagehud.orgId"

    /// A realistic browser User-Agent. Claude's web API sits behind protections
    /// that may reject obviously non-browser clients.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let session: URLSession
    private var orgId: String?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        // We pass the cookie by hand; don't let URLSession manage cookies.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        orgId = UserDefaults.standard.string(forKey: Self.orgDefaultsKey)
    }

    /// Forget the cached organization id — call when the session key changes,
    /// since a new key may belong to a different account.
    func clearOrganizationCache() {
        orgId = nil
        UserDefaults.standard.removeObject(forKey: Self.orgDefaultsKey)
    }

    // MARK: - Public

    /// Fetches the current session usage, resolving the org id first if needed.
    func fetchUsage(sessionKey: String) async throws -> Usage {
        let org = try await ensureOrganizationId(sessionKey: sessionKey)
        do {
            return try await fetchUsage(org: org, sessionKey: sessionKey)
        } catch ClaudeAPIError.http(404) {
            // Cached org id may be stale (different account / renamed). Re-derive
            // it once and retry.
            clearOrganizationCache()
            let fresh = try await ensureOrganizationId(sessionKey: sessionKey)
            return try await fetchUsage(org: fresh, sessionKey: sessionKey)
        }
    }

    // MARK: - Requests

    private func fetchUsage(org: String, sessionKey: String) async throws -> Usage {
        let url = URL(string: "\(Self.base)/api/organizations/\(org)/usage")!
        let data = try await get(url, sessionKey: sessionKey)
        UsageParsing.debugLog(data, label: "usage")
        guard let usage = UsageParsing.parseUsage(data) else {
            throw ClaudeAPIError.unrecognizedUsage
        }
        return usage
    }

    private func ensureOrganizationId(sessionKey: String) async throws -> String {
        if let orgId, !orgId.isEmpty { return orgId }

        let url = URL(string: "\(Self.base)/api/account")!
        let data = try await get(url, sessionKey: sessionKey)
        UsageParsing.debugLog(data, label: "account")
        guard let id = UsageParsing.parseOrganizationId(data) else {
            throw ClaudeAPIError.noOrganization
        }
        orgId = id
        UserDefaults.standard.set(id, forKey: Self.orgDefaultsKey)
        return id
    }

    /// Performs an authenticated GET and returns the body, mapping auth failures
    /// and non-2xx statuses to `ClaudeAPIError`.
    private func get(_ url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.base, forHTTPHeaderField: "Referer")
        request.setValue(Self.base, forHTTPHeaderField: "Origin")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.http(0)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw ClaudeAPIError.unauthorized
        default:
            throw ClaudeAPIError.http(http.statusCode)
        }
    }
}

// MARK: - JSON parsing

/// Defensive parsers for the two responses. The exact JSON shape of Claude's
/// internal API isn't part of any contract, so these search the response for the
/// fields we need rather than decoding a fixed schema. Set `DEBUG_DUMP` to log
/// raw responses if the format ever shifts.
enum UsageParsing {
    private static let DEBUG_DUMP = false

    static func debugLog(_ data: Data, label: String) {
        guard DEBUG_DUMP else { return }
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        NSLog("[ClaudeUsageHUD] \(label) response: \(text.prefix(4000))")
    }

    // MARK: Organization id

    /// Finds the organization UUID anywhere in `/api/account`. The expected
    /// shape is `memberships[].organization.uuid`, but we search recursively so
    /// minor shape changes don't break it.
    static func parseOrganizationId(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findOrganizationUUID(root)
    }

    private static func findOrganizationUUID(_ node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let org = dict["organization"] as? [String: Any],
               let id = (org["uuid"] ?? org["id"]) as? String, !id.isEmpty {
                return id
            }
            for value in dict.values {
                if let found = findOrganizationUUID(value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findOrganizationUUID(value) { return found }
            }
        }
        return nil
    }

    // MARK: Usage

    /// Keys that have, at various times, held the 5-hour "current session" bucket.
    private static let sessionKeys = [
        "five_hour", "fiveHour", "5_hour", "five_hour_limit",
        "current_session", "session", "session_usage",
    ]
    /// Keys for the rolling 7-day "all models" bucket.
    private static let weeklyAllKeys = [
        "seven_day", "sevenDay", "7_day", "seven_day_limit",
        "weekly", "weekly_all_models", "seven_day_all_models", "seven_day_all",
    ]
    /// Keys for the rolling 7-day "Sonnet only" bucket.
    private static let weeklySonnetKeys = [
        "seven_day_sonnet", "sevenDaySonnet", "weekly_sonnet",
        "seven_day_sonnet_limit", "7_day_sonnet", "sonnet",
    ]
    private static let percentKeys = [
        "utilization", "percentage", "percent", "pct",
        "used_percent", "usage_percent", "used_percentage",
    ]
    private static let resetKeys = [
        "resets_at", "reset_at", "resetsAt", "resetAt",
        "resets", "next_reset_at", "next_reset", "reset",
    ]

    static func parseUsage(_ data: Data) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // The session bucket is required; weekly buckets are optional (they may
        // not exist on every plan or in every response shape).
        let session = findBucket(root, keys: sessionKeys).flatMap(makeBucket)
            ?? (root as? [String: Any]).flatMap(makeBucket)
        guard let session else { return nil }

        return Usage(
            session: session,
            weeklyAllModels: findBucket(root, keys: weeklyAllKeys).flatMap(makeBucket),
            weeklySonnet: findBucket(root, keys: weeklySonnetKeys).flatMap(makeBucket)
        )
    }

    /// Recursively finds the first dictionary stored under any of `keys`.
    private static func findBucket(_ node: Any, keys: [String]) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            for key in keys {
                if let bucket = dict[key] as? [String: Any] { return bucket }
            }
            for value in dict.values {
                if let found = findBucket(value, keys: keys) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findBucket(value, keys: keys) { return found }
            }
        }
        return nil
    }

    /// Turns a bucket dictionary into a `UsageBucket`, or `nil` if it has no
    /// recognizable percentage.
    private static func makeBucket(_ dict: [String: Any]) -> UsageBucket? {
        guard let pct = percentage(in: dict) else { return nil }
        return UsageBucket(percentage: pct, resetsAt: resetDate(in: dict))
    }

    /// Extracts an integer 0–100 from a bucket. Handles three shapes:
    /// a `used`/`limit` pair, a 0–1 fraction, or an already-percentage number.
    private static func percentage(in dict: [String: Any]) -> Int? {
        if let used = number(dict, ["used", "used_tokens", "consumed", "current"]),
           let limit = number(dict, ["limit", "total", "max", "cap"]), limit > 0 {
            return clampPercent(used / limit * 100)
        }

        if let value = number(dict, percentKeys) {
            // Values in 0...1 are fractions; anything larger is already a percent.
            return value <= 1.0 ? clampPercent(value * 100) : clampPercent(value)
        }

        return nil
    }

    private static func resetDate(in dict: [String: Any]) -> Date? {
        for key in resetKeys {
            guard let raw = dict[key] else { continue }
            if let string = raw as? String, let date = parseDate(string) { return date }
            if let num = raw as? NSNumber { return epochDate(num.doubleValue) }
        }
        return nil
    }

    // MARK: Helpers

    private static func number(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let s = dict[key] as? String, let d = Double(s) { return d }
        }
        return nil
    }

    private static func clampPercent(_ value: Double) -> Int {
        Int(max(0, min(100, value)).rounded())
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        if let d = isoFull.date(from: string) { return d }
        if let d = isoPlain.date(from: string) { return d }
        if let epoch = Double(string) { return epochDate(epoch) }
        return nil
    }

    private static func epochDate(_ value: Double) -> Date {
        // Heuristic: values past ~year 33658 in seconds are really milliseconds.
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
