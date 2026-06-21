import SwiftUI

/// Notification posted when the user asks to (re)enter their session key. The
/// AppDelegate listens for it and opens the setup window.
extension Notification.Name {
    static let showSetup = Notification.Name("com.claudeusagehud.showSetup")
}

/// Shown when the user clicks the menu bar item: every usage bucket Claude
/// exposes (current session + weekly limits) — or a prompt to set up / fix the
/// connection.
struct PopoverView: View {
    @EnvironmentObject var state: UsageState
    @ObservedObject private var loginItem = LoginItem.shared

    /// How a bucket's reset time is phrased.
    private enum ResetStyle { case countdown, weekday }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)
                .frame(maxWidth: .infinity)

            content

            footer
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private var content: some View {
        if let session = state.session {
            VStack(alignment: .leading, spacing: 14) {
                usageSection("Current Session", session, reset: .countdown)
                if let weekly = state.weeklyAllModels {
                    usageSection("Weekly — All Models", weekly, reset: .weekday)
                }
                if let sonnet = state.weeklySonnet {
                    usageSection("Weekly — Sonnet Only", sonnet, reset: .weekday)
                }
            }

            if case .error(let message) = state.status {
                Text("Couldn't refresh: \(message)")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updated = state.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            message(for: state.status)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Usage section

    private func usageSection(_ title: String, _ bucket: UsageState.Bucket, reset: ResetStyle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
            HStack(spacing: 10) {
                bar(pct: bucket.percentage)
                Text("\(bucket.percentage)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 38, alignment: .trailing)
            }
            if let resetsAt = bucket.resetsAt {
                Text(resetText(resetsAt, style: reset))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func bar(pct: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                Capsule()
                    .fill(color(for: pct))
                    .frame(width: max(0, geo.size.width * CGFloat(pct) / 100))
                    .animation(.easeInOut(duration: 0.4), value: pct)
            }
        }
        .frame(height: 9)
    }

    // MARK: - Placeholder (not connected / error states)

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

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            )) {
                Text("Launch at login").font(.caption)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                if state.session != nil {
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

    // MARK: - Formatting

    private func color(for pct: Int) -> Color {
        switch pct {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    private func resetText(_ date: Date, style: ResetStyle) -> String {
        switch style {
        case .countdown:
            let remaining = Int(date.timeIntervalSinceNow)
            guard remaining > 0 else { return "Resets now" }
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            return hours > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(minutes)m"
        case .weekday:
            return "Resets \(Self.weekdayFormatter.string(from: date))"
        }
    }

    /// e.g. "Wed 4:00 AM".
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}

#Preview {
    let state = UsageState.shared
    state.update(Usage(
        session: UsageBucket(percentage: 62, resetsAt: Date().addingTimeInterval(5_280)),
        weeklyAllModels: UsageBucket(percentage: 6, resetsAt: Date().addingTimeInterval(180_000)),
        weeklySonnet: UsageBucket(percentage: 2, resetsAt: Date().addingTimeInterval(180_000))
    ))
    return PopoverView().environmentObject(state)
}
