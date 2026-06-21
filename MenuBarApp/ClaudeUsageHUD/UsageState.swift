import Combine
import Foundation

/// Single source of truth for the current usage reading and connection status.
/// Written by the polling task in `AppDelegate`, read by the menu bar and popover.
final class UsageState: ObservableObject {
    static let shared = UsageState()

    /// What the app is currently able to show.
    enum Status: Equatable {
        case needsSetup          // no session key stored yet
        case loading             // fetching, nothing to show yet
        case ok                  // showing a fresh reading
        case unauthorized        // key rejected / expired
        case error(String)       // transient failure (network, etc.)
    }

    @Published private(set) var percentage: Int?
    @Published private(set) var resetsAt: Date?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var status: Status = .needsSetup

    private init() {}

    /// A successful reading.
    func update(percentage: Int, resetsAt: Date?) {
        let clamped = max(0, min(100, percentage))
        onMain {
            self.percentage = clamped
            self.resetsAt = resetsAt
            self.lastUpdated = Date()
            self.status = .ok
        }
    }

    /// A status change. `unauthorized`/`needsSetup` clear the stale percentage so
    /// the menu bar shows the attention glyph; transient errors keep the last
    /// value visible (with "Updated …" revealing its age).
    func setStatus(_ status: Status) {
        onMain {
            switch status {
            case .needsSetup, .unauthorized:
                self.percentage = nil
                self.resetsAt = nil
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
