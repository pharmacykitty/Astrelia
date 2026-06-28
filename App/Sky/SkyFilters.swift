import SwiftUI
import CelestialCore

/// What the sky view shows. Tweaked from the filter sheet.
struct SkyFilters: Equatable {
    var showStars = true
    var magnitudeLimit = 4.5          // faintest star shown (higher = more, dimmer stars)
    var showLabels = true             // names on stars (more appear as you zoom in)
    var showConstellations = true     // stick-figure lines
    var showSunMoon = true
    var showBelowHorizon = true       // keep showing things beneath the horizon
}

/// A tidy settings sheet for the sky filters.
struct FilterSheet: View {
    @Binding var filters: SkyFilters
    let catalog: StarCatalog?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show stars", isOn: $filters.showStars)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Faintest magnitude")
                            Spacer()
                            Text(String(format: "%.1f", filters.magnitudeLimit))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $filters.magnitudeLimit, in: 1...7.5, step: 0.5)
                        Text(countLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!filters.showStars)

                    Toggle("Star labels", isOn: $filters.showLabels)
                        .disabled(!filters.showStars)
                } header: {
                    Text("Stars")
                } footer: {
                    if filters.showStars && filters.showLabels {
                        Text("Pinch to zoom in — more names appear as you do. Tap any star to identify it.")
                    }
                }

                Section("Figures") {
                    Toggle("Constellation lines", isOn: $filters.showConstellations)
                }

                Section("Solar system") {
                    Toggle("Sun & Moon", isOn: $filters.showSunMoon)
                }

                Section {
                    Toggle("Show below the horizon", isOn: $filters.showBelowHorizon)
                } footer: {
                    Text("Point at the ground to find things that have set — like the Sun at night.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.spaceGradient.ignoresSafeArea())
            .listRowBackground(Color.white.opacity(0.05))
            .tint(Theme.accent)
            .navigationTitle("Sky filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var countLabel: String {
        guard let catalog else { return "Loading catalog…" }
        let count = catalog.stars.lazy.filter { $0.apparentMagnitude <= filters.magnitudeLimit }.count
        return "\(count) stars visible"
    }
}
