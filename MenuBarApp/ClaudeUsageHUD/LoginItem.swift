import Foundation
import ServiceManagement

/// Manages "launch at login" via `SMAppService` (macOS 13+). No LaunchAgent
/// plist needed — the app registers itself. The user's preference is mirrored in
/// UserDefaults so we can opt in once, automatically, after first-time setup.
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    private static let defaultsKey = "com.claudeusagehud.launchAtLogin"

    /// Reflects the actual registration status; the popover toggle binds to this.
    @Published private(set) var isEnabled: Bool

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Opt in to launch-at-login once, the first time setup completes. Respects a
    /// later manual choice (the preference key is only absent before the first run).
    func enableByDefaultIfFirstRun() {
        guard UserDefaults.standard.object(forKey: Self.defaultsKey) == nil else { return }
        setEnabled(true)
    }

    /// Registers or unregisters the app as a login item and persists the choice.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
            isEnabled = enabled
        } catch {
            NSLog("[ClaudeUsageHUD] launch-at-login \(enabled ? "register" : "unregister") failed: \(error)")
            // Fall back to whatever the system actually reports.
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
