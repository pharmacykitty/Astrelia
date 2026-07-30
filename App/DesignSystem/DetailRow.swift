import SwiftUI

/// One label/value fact row inside a luminous data card — shared by every detail
/// page (stars, planets, deep sky, constellations) so the affordances (glossary
/// popover, divider treatment) can't drift between screens.
struct DetailRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            GlossaryButton(label: label)
            Spacer()
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().background(.white.opacity(0.08)) }
    }
}
