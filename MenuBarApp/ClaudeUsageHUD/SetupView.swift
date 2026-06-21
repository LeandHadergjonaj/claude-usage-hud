import SwiftUI

/// Drives the one-time setup window. `AppDelegate` owns the instance, validates
/// the pasted key, and updates `status`; the view just renders and submits.
final class SetupCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case validating
        case failed(String)
    }

    @Published var sessionKey = ""
    @Published var status: Status = .idle

    /// Called with the trimmed key when the user submits.
    var onSubmit: (String) -> Void = { _ in }

    func submit() {
        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .failed("Paste your session key first.")
            return
        }
        status = .validating
        onSubmit(trimmed)
    }
}

/// One-time setup: paste the `sessionKey` cookie from claude.ai.
struct SetupView: View {
    @ObservedObject var coordinator: SetupCoordinator

    private var isValidating: Bool {
        if case .validating = coordinator.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            instructions
            keyField
            statusLine
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: 420, height: 400)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connect to Claude")
                .font(.title3.bold())
            Text("Paste your claude.ai session key once. It's stored in your macOS Keychain and never leaves your Mac.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let steps: [LocalizedStringKey] = [
        "Open **claude.ai** in your browser.",
        "Open DevTools (**⌥⌘I**).",
        "Go to **Application → Cookies → claude.ai**.",
        "Find the cookie named **sessionKey** and copy its value.",
        "Paste it below.",
    ]

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, text in
                step(index + 1, text)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session key")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            TextField("sk-ant-sid01-…", text: $coordinator.sessionKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .font(.system(.body, design: .monospaced))
                .disabled(isValidating)
                .onSubmit { coordinator.submit() }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch coordinator.status {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking your key…").font(.caption).foregroundColor(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Save & Connect") { coordinator.submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(isValidating)
        }
    }
}

#Preview {
    SetupView(coordinator: SetupCoordinator())
}
