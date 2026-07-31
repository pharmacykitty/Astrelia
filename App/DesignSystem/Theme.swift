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

    /// The night's own ink: a deep blue-black derived from `spaceGradient`, used
    /// (translucent) as the fill of every utility surface. Neutral materials over
    /// the near-black sky render as flat *gray* slabs — this keeps the chrome in
    /// the night's palette instead of on top of it.
    static let nightInk = Color(red: 0.06, green: 0.08, blue: 0.16)

    /// One gold for everything star-tinted (catalog rows, star detail, About's
    /// star-catalog card) — softer than system yellow, matching the ecliptic's.
    static let gold = Color(red: 0.96, green: 0.82, blue: 0.51)

    // MARK: Text emphasis

    // One vocabulary for text over the dark sky instead of ad-hoc opacities.
    // Primary text is plain `.white`; informational text never drops below
    // `textTertiary` — that's the legibility floor on black.
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.55)

    // MARK: Motion

    /// The app's one motion curve for chrome: every state-driven show/hide,
    /// selection change, and layout shift animates with this spring so the whole
    /// UI moves like a single instrument. (Press feedback stays faster — see
    /// `LuminousButtonStyle`.)
    static let spring = Animation.spring(duration: 0.35, bounce: 0.15)

    /// How chrome enters and leaves: sliding from the nearest screen edge while
    /// fading. Pass the edge the element lives against (`.top` for bars under the
    /// control cluster, `.bottom` for panels above the readout).
    static func slide(from edge: Edge) -> AnyTransition {
        .move(edge: edge).combined(with: .opacity)
    }
}

extension View {
    /// The "luminous instrument" treatment for a glass surface: a hairline tinted
    /// ring and a soft outer glow in the same colour, over a near-transparent fill.
    /// Used by cards and panels so the whole UI shares one visual language.
    func luminousSurface(_ tint: Color = Theme.accent,
                         cornerRadius: CGFloat = Theme.cardRadius,
                         glow: CGFloat = 10) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            // Clip the content to the rounded shape so row separators (and anything
            // else at the edges) can't poke past the corners.
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.25), radius: glow)
    }

    /// The quieter sibling of `luminousSurface`, for utility panels over live
    /// content (readouts, legends, plot insets): night ink and a hairline ring,
    /// untinted and glowless, so it recedes instead of glowing. Deliberately NOT
    /// a neutral material — over the near-black sky those render as gray slabs.
    func quietSurface(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.nightInk.opacity(0.55), in: .rect(cornerRadius: cornerRadius))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}
