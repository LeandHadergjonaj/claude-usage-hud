import SwiftUI

/// Shown when the user clicks the menu bar item: a progress arc and a short
/// description of how much of the current Claude session has been used.
struct PopoverView: View {
    @EnvironmentObject var state: UsageState

    var body: some View {
        VStack(spacing: 14) {
            Text("Claude Usage")
                .font(.headline)

            if let pct = state.percentage {
                arc(pct: pct)
                Text("\(pct)% of session used")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text("Waiting for data…")
                        .font(.subheadline)
                    Text("Open claude.ai in Chrome with the extension installed.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(height: 96)
            }

            if let updated = state.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 240)
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
}

#Preview {
    let state = UsageState.shared
    state.update(percentage: 23)
    return PopoverView().environmentObject(state)
}
