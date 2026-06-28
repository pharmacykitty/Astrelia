import SwiftUI
import CoreLocation
import Astrology

/// Form to enter birth data and save a chart. Place search resolves both the
/// coordinates and the IANA timezone (so historical/foreign births compute
/// correctly), via `CLGeocoder`.
struct ChartEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var timeKnown = true

    @State private var placeQuery = ""
    @State private var search = PlaceSearch()
    @State private var selected: ResolvedPlace?

    @State private var houseSystem: HouseSystem = .placidus
    @State private var isSidereal = false

    private let tint = AppScreen.astrology.tint

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                }

                Section("Birth time") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Time known", isOn: $timeKnown)
                    if timeKnown {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    } else {
                        Text("Cast for local noon; houses & angles will be unreliable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Birth place") {
                    HStack {
                        TextField("City, country", text: $placeQuery)
                            .onSubmit { search.run(placeQuery) }
                        Button("Search") { search.run(placeQuery) }
                            .buttonStyle(.borderless)
                    }
                    if search.isSearching { ProgressView() }
                    ForEach(search.results) { place in
                        Button {
                            selected = place
                            placeQuery = place.name
                            search.results = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(.primary)
                                Text(place.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let selected {
                        LabeledContent("Selected", value: selected.name)
                        LabeledContent("Timezone", value: selected.timeZoneIdentifier)
                        LabeledContent("Coordinates",
                                       value: String(format: "%.3f, %.3f", selected.latitude, selected.longitude))
                    }
                }

                Section("Chart options") {
                    Picker("House system", selection: $houseSystem) {
                        ForEach(HouseSystem.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Toggle("Sidereal (Lahiri)", isOn: $isSidereal)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.spaceGradient.ignoresSafeArea())
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(selected == nil).bold()
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(tint)
    }

    private func save() {
        guard let place = selected else { return }
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let t = cal.dateComponents([.hour, .minute], from: time)
        let chart = SavedChart(
            name: name,
            year: d.year ?? 2000, month: d.month ?? 1, day: d.day ?? 1,
            hour: timeKnown ? (t.hour ?? 12) : 12,
            minute: timeKnown ? (t.minute ?? 0) : 0,
            timeKnown: timeKnown,
            latitude: place.latitude, longitude: place.longitude,
            timeZoneIdentifier: place.timeZoneIdentifier, placeName: place.name,
            houseSystem: houseSystem,
            zodiac: isSidereal ? .sidereal(.lahiri) : .tropical
        )
        context.insert(chart)
        dismiss()
    }
}

/// A geocoded place with its resolved timezone.
struct ResolvedPlace: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
}

/// Wraps `CLGeocoder` to turn a free-text place into candidates with coordinates
/// and IANA timezones.
@MainActor
@Observable
final class PlaceSearch {
    var results: [ResolvedPlace] = []
    var isSearching = false

    private let geocoder = CLGeocoder()

    func run(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        geocoder.cancelGeocode()
        geocoder.geocodeAddressString(q) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSearching = false
                self.results = (placemarks ?? []).prefix(6).compactMap { Self.resolve($0) }
            }
        }
    }

    private static func resolve(_ p: CLPlacemark) -> ResolvedPlace? {
        guard let loc = p.location, let tz = p.timeZone else { return nil }
        let primary = [p.locality, p.name].compactMap { $0 }.first ?? (p.country ?? "Place")
        let detail = [p.administrativeArea, p.country].compactMap { $0 }.joined(separator: ", ")
        return ResolvedPlace(
            name: primary,
            detail: detail.isEmpty ? tz.identifier : detail,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timeZoneIdentifier: tz.identifier
        )
    }
}
