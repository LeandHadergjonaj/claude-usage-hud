import AppKit
import Combine
import SwiftUI

/// Owns the menu bar status item, the click-through popover, the one-time setup
/// window, and the 30-second polling loop that reads usage from Claude's API.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var setupWindow: NSWindow?
    private var setupCoordinator: SetupCoordinator?
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let state = UsageState.shared
    private let client = ClaudeAPIClient.shared

    private static let pollInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(showSetup),
            name: .showSetup, object: nil
        )

        if KeychainStore.hasSessionKey {
            startPolling()
        } else {
            state.setStatus(.needsSetup)
            showSetup()
        }
        updateStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.toolTip = "Claude Usage HUD"

            // The gauge glyph sits to the left of the percentage. Marking it a
            // template lets macOS tint it automatically for light/dark menu bars.
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
                button.imagePosition = .imageLeft
                button.imageHugsTitle = true
            }
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 250, height: 220)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(state)
        )
    }

    private func observeState() {
        // Redraw the menu bar title whenever the session value or status changes.
        Publishers.Merge(
            state.$session.map { _ in () },
            state.$status.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateStatusItem() }
        .store(in: &cancellables)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in self?.refresh()
        }
        pollTimer = timer
        refresh()
    }

    /// One poll cycle. No-ops (into `needsSetup`) when there's no key.
    private func refresh() {
        guard let key = KeychainStore.load(), !key.isEmpty else {
            state.setStatus(.needsSetup)
            return
        }
        if state.session == nil { state.setStatus(.loading) }

        Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await self.client.fetchUsage(sessionKey: key)
                self.state.update(usage)
            } catch ClaudeAPIError.unauthorized {
                self.state.setStatus(.unauthorized)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.state.setStatus(.error(message))
            }
        }
    }

    // MARK: - Menu bar rendering

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let title: String
        let color: NSColor

        if let pct = state.session?.percentage {
            title = "\(pct)%"
            color = AppDelegate.menuBarColor(for: pct)
        } else {
            switch state.status {
            case .unauthorized:
                title = "!"
                color = .systemRed
            case .error:
                title = "!"
                color = .systemOrange
            case .loading:
                title = "…"
                color = .secondaryLabelColor
            case .needsSetup, .ok:
                title = "—"
                color = .secondaryLabelColor
            }
        }

        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.menuBarFont(ofSize: 0),
            ]
        )
    }

    /// green < 50, orange 50–79, red >= 80 — mirrors the popover arc colour.
    static func menuBarColor(for pct: Int) -> NSColor {
        switch pct {
        case ..<50: return .systemGreen
        case 50..<80: return .systemOrange
        default: return .systemRed
        }
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Setup window

    @objc private func showSetup() {
        popover.performClose(nil)

        let coordinator = setupCoordinator ?? makeSetupCoordinator()
        coordinator.status = .idle

        if setupWindow == nil {
            let hosting = NSHostingController(rootView: SetupView(coordinator: coordinator))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Claude Usage HUD"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            setupWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeSetupCoordinator() -> SetupCoordinator {
        let coordinator = SetupCoordinator()
        coordinator.onSubmit = { [weak self] key in self?.validateAndSave(key) }
        setupCoordinator = coordinator
        return coordinator
    }

    /// Validates a pasted key by fetching once before persisting it.
    private func validateAndSave(_ key: String) {
        // A new key may belong to a different account; drop the cached org id.
        client.clearOrganizationCache()

        Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await self.client.fetchUsage(sessionKey: key)
                KeychainStore.save(key)
                self.state.update(usage)
                await MainActor.run {
                    self.setupCoordinator?.status = .idle
                    self.closeSetup()
                    self.startPolling()
                    // Opt in to launch-at-login the first time setup succeeds.
                    LoginItem.shared.enableByDefaultIfFirstRun()
                }
            } catch ClaudeAPIError.unauthorized {
                await MainActor.run {
                    self.setupCoordinator?.status =
                        .failed("That key was rejected. Copy the full value of the sessionKey cookie and try again.")
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                await MainActor.run {
                    self.setupCoordinator?.status = .failed("Couldn't connect: \(message)")
                }
            }
        }
    }

    private func closeSetup() {
        setupWindow?.close()
    }
}
