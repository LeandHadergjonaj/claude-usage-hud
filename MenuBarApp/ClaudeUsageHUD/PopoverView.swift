import SwiftUI

/// Notification posted when the user asks to (re)enter their session key. The
/// AppDelegate listens for it and opens the setup window.
extension Notification.Name {
    static let showSetup = Notification.Name("com.claudeusagehud.showSetup")
}

/// Shown when the user clicks the menu bar item: a progress arc, the session
/// percentage, and when it resets — or a prompt to set up / fix the connection.
struct PopoverView: View {
    @EnvironmentObject var state: UsageState

    var body: some View {
        VStack(spacing: 14) {
            Text("Claude Usage")
                .font(.headline)

            content

            footer
        }
        .padding(20)
        .frame(width: 250)
    }

    @ViewBuilder
    private var content: some View {
        if let pct = state.percentage {
            arc(pct: pct)
            Text("\(pct)% of session used")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let resetsAt = state.resetsAt {
                Text(resetText(resetsAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if case .error(let message) = state.status {
                Text("Couldn't refresh: \(message)")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            if let updated = state.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
            message(for: state.status)
        }
    }

    @ViewBuilder
    private func message(for status: UsageState.Status) -> some View {
        switch status {
        case .needsSetup:
            placeholder(
                icon: "key.horizontal",
                title: "Not connected",
                detail: "Paste your Claude session key to start tracking usage.",
                action: ("Set up…", "key.horizontal")
            )
        case .unauthorized:
            placeholder(
                icon: "exclamationmark.lock",
                title: "Session key expired",
                detail: "Your key was rejected. Paste a fresh one from claude.ai.",
                action: ("Update key…", "arrow.clockwise")
            )
        case .error(let detail):
            placeholder(
                icon: "wifi.exclamationmark",
                title: "Can't reach Claude",
                detail: detail,
                action: nil
            )
        case .loading, .ok:
            placeholder(
                icon: "antenna.radiowaves.left.and.right",
                title: "Loading…",
                detail: "Fetching your current session usage.",
                action: nil
            )
        }
    }

    private func placeholder(
        icon: String,
        title: String,
        detail: String,
        action: (label: String, symbol: String)?
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline.bold())
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button {
                    NotificationCenter.default.post(name: .showSetup, object: nil)
                } label: {
                    Label(action.label, systemImage: action.symbol)
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .frame(minHeight: 120)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        // Quit is always reachable; "Update key" appears once connected (the
        // setup / expired states already surface their own action button).
        VStack(spacing: 0) {
            Divider()
            HStack {
                if state.percentage != nil {
                    Button("Update key") {
                        NotificationCenter.default.post(name: .showSetup, object: nil)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func arc(pct: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(pct) / 100)
                .stroke(color(for: pct), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: pct)
            Text("\(pct)%")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 96, height: 96)
        .padding(.top, 4)
    }

    private func color(for pct: Int) -> Color {
        switch pct {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    /// "Resets in 2h 14m" / "Resets in 9m" / "Resetting now".
    private func resetText(_ date: Date) -> String {
        let remaining = Int(date.timeIntervalSinceNow)
        guard remaining > 0 else { return "Resetting now" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(minutes)m"
    }
}

#Preview {
    let state = UsageState.shared
    state.update(percentage: 62, resetsAt: Date().addingTimeInterval(8_040))
    return PopoverView().environmentObject(state)
}
