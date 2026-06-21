import Combine
import Foundation

/// Single source of truth for the current usage percentage. Shared between the
/// HTTP server (writer) and the SwiftUI popover / menu bar (readers).
final class UsageState: ObservableObject {
    static let shared = UsageState()

    @Published private(set) var percentage: Int?
    @Published private(set) var lastUpdated: Date?

    private init() {}

    /// Called from the server's background queue; hops to main for publishing.
    func update(percentage: Int) {
        let clamped = max(0, min(100, percentage))
        DispatchQueue.main.async {
            self.percentage = clamped
            self.lastUpdated = Date()
        }
    }
}
