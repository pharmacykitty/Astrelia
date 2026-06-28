import SwiftUI
import UIKit

extension EdgeInsets {
    /// The key window's safe-area insets. Full-bleed screens (which `ignoresSafeArea`
    /// so the sky/galaxy fills the display) read this to keep controls clear of the
    /// Dynamic Island and home indicator. `GeometryReader.safeAreaInsets` can't be
    /// used here — it reports zero once the reader itself ignores the safe area.
    @MainActor static var deviceSafeArea: EdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left,
                          bottom: insets.bottom, trailing: insets.right)
    }
}

/// Shared design constants so the app's chrome stays visually consistent and can
/// be tuned in one place. Keep this small and intentional — only values that are
/// genuinely reused across screens belong here.
enum Theme {
    /// Standard interactive control size. Also Apple's minimum tap target (44×44),
    /// so any control sized to this is guaranteed to be comfortably tappable.
    static let controlSize: CGFloat = 44

    // Corner radii for the glass cards and panels used throughout the chrome.
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 20

    /// The unifying chrome accent — a luminous periwinkle that glows over the
    /// dark sky. Per-feature tints (cyan/violet/gold) still live on `AppScreen`;
    /// this is the default for neutral controls.
    static let accent = Color(red: 0.56, green: 0.72, blue: 1.0)

    /// The deep-space background gradient shared by detail and placeholder screens.
    static let spaceGradient = LinearGradient(
        colors: [Color(red: 0.03, green: 0.04, blue: 0.12), .black],
        startPoint: .top, endPoint: .bottom
    )
}

extension View {
    /// The "luminous instrument" treatment for a glass surface: a hairline tinted
    /// ring and a soft outer glow in the same colour, over a near-transparent fill.
    /// Used by cards and panels so the whole UI shares one visual language.
    func luminousSurface(_ tint: Color = Theme.accent,
                         cornerRadius: CGFloat = Theme.cardRadius,
                         glow: CGFloat = 10) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.25), radius: glow)
    }
}
