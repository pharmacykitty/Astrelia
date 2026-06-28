import SwiftUI

/// A circular, glass-backed icon button used across the app's chrome (sky view,
/// Galaxy Map, menus). It standardizes three things the app previously did
/// inconsistently:
///
/// - **Accessibility:** an icon alone is invisible to VoiceOver, so a text
///   `label` is always required even though only the symbol is shown.
/// - **Tap target:** the control is always `Theme.controlSize` (44pt), meeting
///   Apple's minimum touch area regardless of the glyph's visual size.
/// - **Feedback:** a selection haptic fires on every tap.
///
/// Pass `isActive` for toggle-style controls (e.g. free-flight on): it tints the
/// glyph and strengthens the ring so the on-state reads without relying on colour
/// alone.
struct CircleIconButton: View {
    let label: String
    let systemImage: String
    var tint: Color = Theme.accent
    var isActive: Bool = false
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? tint : .white.opacity(0.92))
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .background {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(tint.opacity(isActive ? 0.22 : 0.08))   // near-transparent accent wash
                }
                .overlay {
                    Circle().strokeBorder(tint.opacity(isActive ? 0.9 : 0.45), lineWidth: 1)
                }
                .shadow(color: tint.opacity(isActive ? 0.6 : 0.3), radius: isActive ? 11 : 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: taps)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                CircleIconButton(label: "Menu", systemImage: "square.grid.2x2") {}
                CircleIconButton(label: "Free flight", systemImage: "airplane",
                                 tint: .green, isActive: true) {}
            }
            Button { } label: { Label("Fly here", systemImage: "paperplane.fill") }
                .buttonStyle(LuminousButtonStyle())
            Button("Open Settings") { }
                .buttonStyle(LuminousButtonStyle(tint: .cyan))
        }
        .padding()
    }
    .ignoresSafeArea()
}
