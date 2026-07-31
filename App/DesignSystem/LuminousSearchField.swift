import SwiftUI

/// The app's search field, in the luminous language: a glass capsule with a
/// sparkle in place of the system magnifying glass. Callers pin it to the bottom
/// of the screen via `.safeAreaInset(edge: .bottom)` so it sits in thumb reach.
struct LuminousSearchField: View {
    @Binding var query: String
    var prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.footnote)
                .foregroundStyle(Theme.accent.opacity(0.8))
            TextField(prompt, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        // Night ink, not neutral material: rows scrolling beneath dim to a shadow
        // instead of ghosting legibly through a gray plate.
        .background(Theme.nightInk.opacity(0.82), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
