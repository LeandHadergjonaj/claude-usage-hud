import AppKit
import Combine
import SwiftUI

/// Owns the menu bar status item, the click-through popover, and the local
/// HTTP server that the browser extension POSTs usage updates to.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var server: UsageServer!
    private var cancellables = Set<AnyCancellable>()
    private let state = UsageState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeState()
        startServer()
        updateStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.toolTip = "Claude Usage HUD"
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(state)
        )
    }

    private func observeState() {
        // Redraw the menu bar title whenever the percentage changes.
        state.$percentage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func startServer() {
        server = UsageServer(port: 27420) { [weak self] percentage in
            self?.state.update(percentage: percentage)
        }
        server.start()
    }

    // MARK: - Menu bar rendering

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let title: String
        let color: NSColor
        if let pct = state.percentage {
            title = "\(pct)%"
            color = AppDelegate.menuBarColor(for: pct)
        } else {
            title = "—"
            color = .secondaryLabelColor
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
}
