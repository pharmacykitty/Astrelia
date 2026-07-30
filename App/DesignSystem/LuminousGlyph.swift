import SwiftUI

/// A circular glyph in the luminous-instrument language: a tinted ring and soft
/// glow around a symbol, over a near-transparent wash. Shared by detail headers,
/// the Tonight screen and the About page so they read as one family.
struct LuminousGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 52
    var glyphSize: CGFloat = 21

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(tint.opacity(0.12))
            }
            .overlay { Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1) }
            .shadow(color: tint.opacity(0.45), radius: size * 0.18)
    }
}
