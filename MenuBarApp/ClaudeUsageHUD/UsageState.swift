import Combine
import Foundation

/// Single source of truth for the current usage reading and connection status.
/// Written by the polling task in `AppDelegate`, read by the menu bar and popover.
final class UsageState: ObservableObject {
    static let shared = UsageState()

    /// One usage bucket as displayed in the UI.
    struct Bucket: Equatable {
        let percentage: Int
        let resetsAt: Date?
    }

    /// What the app is currently able to show.
    enum Status: Equatable {
        case needsSetup          // no session key stored yet
        case loading             // fetching, nothing to show yet
        case ok                  // showing a fresh reading
        case unauthorized        // key rejected / expired
        case error(String)       // transient failure (network, etc.)
    }

    @Published private(set) var session: Bucket?
    @Published private(set) var weeklyAllModels: Bucket?
    @Published private(set) var weeklySonnet: Bucket?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var status: Status = .needsSetup

    private init() {}

    /// A successful reading across all buckets.
    func update(_ usage: Usage) {
        onMain {
            self.session = Bucket(usage.session)
            self.weeklyAllModels = usage.weeklyAllModels.map(Bucket.init)
            self.weeklySonnet = usage.weeklySonnet.map(Bucket.init)
            self.lastUpdated = Date()
            self.status = .ok
        }
    }

    /// A status change. `unauthorized`/`needsSetup` clear the stale values so the
    /// menu bar shows the attention glyph; transient errors keep the last reading
    /// visible (with "Updated …" revealing its age).
    func setStatus(_ status: Status) {
        onMain {
            switch status {
            case .needsSetup, .unauthorized:
                self.session = nil
                self.weeklyAllModels = nil
                self.weeklySonnet = nil
            case .loading, .ok, .error:
                break
            }
            self.status = status
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

private extension UsageState.Bucket {
    init(_ bucket: UsageBucket) {
        self.init(percentage: max(0, min(100, bucket.percentage)), resetsAt: bucket.resetsAt)
    }
}
