import SwiftUI
import SwiftData

/// Pick two saved charts to compare, then open the synastry / composite view.
/// Shared destination for the "Relationships" hub card and the Saved Charts
/// "Compare" button.
struct RelationshipsView: View {
    var store: StarCatalogStore? = nil

    @Query(sort: \SavedChart.createdAt, order: .reverse) private var charts: [SavedChart]
    @State private var aID: PersistentIdentifier?
    @State private var bID: PersistentIdentifier?

    private let tint = AppScreen.astrology.tint

    private var personA: SavedChart? { charts.first { $0.persistentModelID == aID } }
    private var personB: SavedChart? { charts.first { $0.persistentModelID == bID } }
    private var ready: Bool { personA != nil && personB != nil && aID != bID }

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            if charts.count < 2 {
                needTwo
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        intro
                        picker("First person", selection: $aID, exclude: bID)
                        Image(systemName: "heart.fill").font(.title3).foregroundStyle(tint.opacity(0.7))
                        picker("Second person", selection: $bID, exclude: aID)

                        if ready, let a = personA, let b = personB {
                            NavigationLink {
                                SynastryView(personA: a, personB: b)
                            } label: {
                                HubCard(symbol: "sparkles", title: "View compatibility",
                                        subtitle: "Bi-wheel, score & composite", tint: tint)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Relationships")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    private var intro: some View {
        Text("Compare two birth charts to see how they interact — the contacts between them and the chart they form together.")
            .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func picker(_ label: String, selection: Binding<PersistentIdentifier?>,
                        exclude: PersistentIdentifier?) -> some View {
        let selected = charts.first { $0.persistentModelID == selection.wrappedValue }
        return Menu {
            ForEach(charts) { c in
                Button {
                    selection.wrappedValue = c.persistentModelID
                } label: {
                    Label(c.name.isEmpty ? "Untitled" : c.name,
                          systemImage: c.persistentModelID == selection.wrappedValue ? "checkmark" : "")
                }
                .disabled(c.persistentModelID == exclude)
            }
        } label: {
            HStack(spacing: 12) {
                LuminousGlyph(symbol: "person.crop.circle", tint: tint, size: 40, glyphSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(selected.map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "Choose a chart")
                        .font(.headline).foregroundStyle(selected == nil ? .white.opacity(0.4) : .white)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(tint.opacity(0.6))
            }
            .padding(16)
            .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 10)
        }
        .buttonStyle(.plain)
    }

    private var needTwo: some View {
        VStack(spacing: 14) {
            LuminousGlyph(symbol: "heart.text.square", tint: tint, size: 84, glyphSize: 34)
            Text("Save two charts first").font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text("Relationship astrology compares two people. Add at least two saved charts to compare them.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func prefill() {
        if aID == nil { aID = charts.first?.persistentModelID }
        if bID == nil, charts.count > 1 { bID = charts.dropFirst().first?.persistentModelID }
    }
}
