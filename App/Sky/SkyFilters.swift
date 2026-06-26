import SwiftUI
import CelestialCore

/// What the sky view shows. Tweaked from the filter sheet.
struct SkyFilters: Equatable {
    var showStars = true
    var magnitudeLimit = 4.5          // faintest star shown (higher = more, dimmer stars)
    var showLabels = true             // names on the brightest stars
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
                Section("Stars") {
                    Toggle("Show stars", isOn: $filters.showStars)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Faintest magnitude")
                            Spacer()
                            Text(String(format: "%.1f", filters.magnitudeLimit))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $filters.magnitudeLimit, in: 1...6.5, step: 0.5)
                        Text(countLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!filters.showStars)

                    Toggle("Star labels", isOn: $filters.showLabels)
                        .disabled(!filters.showStars)
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
            .navigationTitle("Sky filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
