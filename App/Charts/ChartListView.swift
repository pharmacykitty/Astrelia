import SwiftUI
import SwiftData

/// Lists the user's saved birth charts; add new ones or tap to open.
struct ChartListView: View {
    var store: StarCatalogStore? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedChart.createdAt, order: .reverse) private var charts: [SavedChart]
    @State private var editing = false

    private let tint = AppScreen.astrology.tint

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            if charts.isEmpty {
                empty
            } else {
                List {
                    ForEach(charts) { chart in
                        NavigationLink {
                            SavedChartView(chart: chart, store: store)
                        } label: {
                            row(chart)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Saved Charts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if charts.count >= 2 {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        RelationshipsView(store: store)
                    } label: {
                        Label("Compare", systemImage: "heart.circle")
                    }
                    .tint(tint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chart", systemImage: "plus") { editing = true }
                    .tint(tint)
            }
        }
        .sheet(isPresented: $editing) {
            ChartEditorView()
        }
    }

    private func row(_ chart: SavedChart) -> some View {
        HStack(spacing: 14) {
            LuminousGlyph(symbol: "person.crop.circle", tint: tint, size: 40, glyphSize: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(chart.name.isEmpty ? "Untitled chart" : chart.name)
                    .font(.headline).foregroundStyle(.white)
                Text(chart.subtitle)
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            LuminousGlyph(symbol: "person.crop.circle.badge.plus", tint: tint, size: 84, glyphSize: 34)
            Text("No saved charts").font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text("Add a birth date, time, and place to cast a natal chart.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button { editing = true } label: {
                Label("New Chart", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .padding(.top, 4)
        }
        .padding(40)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(charts[i]) }
    }
}
