import Foundation
import Network

/// A tiny loopback-only HTTP/1.1 server built on Network.framework. It accepts
/// `POST /usage` with a JSON body of `{ "percentage": 23, "timestamp": "..." }`
/// and answers CORS preflight (`OPTIONS`) requests so the browser extension can
/// reach it from an https://claude.ai page.
final class UsageServer {
    private let port: NWEndpoint.Port
    private let onUsage: (Int) -> Void
    private let queue = DispatchQueue(label: "com.claudeusagehud.server")
    private var listener: NWListener?

    init(port: UInt16, onUsage: @escaping (Int) -> Void) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.onUsage = onUsage
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: port)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    NSLog("[ClaudeUsageHUD] listening on 127.0.0.1:\(self?.port.rawValue ?? 0)")
                case .failed(let error):
                    NSLog("[ClaudeUsageHUD] listener failed: \(error)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            NSLog("[ClaudeUsageHUD] could not start listener: \(error)")
        }
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        // Only accept connections from the local machine.
        if !UsageServer.isLoopback(conn.endpoint) {
            conn.cancel()
            return
        }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            var buffer = buffer
            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            // Respond as soon as we have a complete request.
            if let request = HTTPRequest(data: buffer), request.isComplete {
                self.respond(to: request, on: conn)
                return
            }

            if isComplete || error != nil {
                if let request = HTTPRequest(data: buffer) {
                    self.respond(to: request, on: conn)
                } else {
                    conn.cancel()
                }
                return
            }

            self.receive(conn, buffer: buffer)
        }
    }

    private func respond(to request: HTTPRequest, on conn: NWConnection) {
        switch request.method {
        case "OPTIONS":
            // CORS / Private Network Access preflight.
            send(status: "204 No Content", body: Data(), on: conn)

        case "POST":
            if let pct = request.percentageFromJSONBody() {
                onUsage(pct)
                send(status: "200 OK", body: Data("{\"ok\":true}".utf8), on: conn)
            } else {
                send(status: "400 Bad Request",
                     body: Data("{\"ok\":false,\"error\":\"missing percentage\"}".utf8),
                     on: conn)
            }

        default:
            send(status: "200 OK", body: Data("{\"ok\":true}".utf8), on: conn)
        }
    }

    private func send(status: String, body: Data, on conn: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
        header += "Access-Control-Allow-Headers: Content-Type\r\n"
        header += "Access-Control-Allow-Private-Network: true\r\n"
        header += "Connection: close\r\n\r\n"

        var out = Data(header.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let addr): return addr.isLoopback
        case .ipv6(let addr): return addr.isLoopback
        @unknown default: return false
        }
    }
}

// MARK: - Minimal HTTP request parser

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let isComplete: Bool

    init?(data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }

        let headerData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        method = parts[0].uppercased()
        path = parts[1]

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            parsedHeaders[key] = value
        }
        headers = parsedHeaders

        let available = data.subdata(in: range.upperBound..<data.endIndex)
        body = available
        let contentLength = Int(parsedHeaders["content-length"] ?? "0") ?? 0
        isComplete = available.count >= contentLength
    }

    /// Extracts an integer `percentage` from a JSON body (number or string).
    func percentageFromJSONBody() -> Int? {
        guard !body.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }

        if let p = obj["percentage"] as? Int { return p }
        if let d = obj["percentage"] as? Double { return Int(d.rounded()) }
        if let s = obj["percentage"] as? String, let p = Int(s) { return p }
        return nil
    }
}
