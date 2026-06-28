import SwiftUI

/// The "luminous instrument" treatment for text/pill buttons: an outlined capsule
/// with a near-transparent tinted fill, a hairline ring, and a soft glow that
/// brightens on press. The button's tint colours the text, ring, and glow so a
/// single style works for the neutral accent and per-feature colours alike.
///
/// Pair with a `Label` or `Text`; the label sets its own font.
struct LuminousButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background {
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.28 : 0.13))
            }
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.3 : 0.5),
                    radius: configuration.isPressed ? 4 : 9)
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
