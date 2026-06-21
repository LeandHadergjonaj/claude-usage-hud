import SwiftUI

@main
struct ClaudeUsageHUDApp: App {
    // The AppDelegate owns the status bar item, popover, and local HTTP server.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No real window. LSUIElement keeps us out of the Dock; this empty
        // Settings scene satisfies the App protocol without showing UI.
        Settings {
            EmptyView()
        }
    }
}
