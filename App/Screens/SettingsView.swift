import SwiftUI

/// App-wide settings (docs/preferences-spec.md): units, sky defaults, galaxy
/// toggles, a home observing location, and motion. Everything binds straight
/// into `AppPreferences` — the surfaces it configures re-read on appear.
struct SettingsView: View {
    @Bindable private var prefs = AppPreferences.shared
    @State private var observer = ObserverLocation()
    @State private var confirmReset = false

    var body: some View {
        // No NavigationStack of its own: the presenter (ContentView's
        // full-screen cover, or the snapshot harness) provides it — a nested
        // stack would draw a second bar above the Close button.
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            Form {
                unitsSection
                skySection
                galaxySection
                locationSection
                motionSection
                resetSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Only warm up location if the user already granted it — opening
            // Settings must not itself trigger the system permission prompt
            // (the Save-home button requests on demand instead).
            if observer.authorization == .authorizedWhenInUse || observer.authorization == .authorizedAlways {
                observer.start()
            }
        }
        .onDisappear { observer.stop() }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Temperature", selection: $prefs.temperatureUnit) {
                ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
            }
            Picker("Distance", selection: $prefs.distanceUnit) {
                ForEach(DistanceUnit.allCases) { Text($0.label).tag($0) }
            }
            Picker("Star distances", selection: $prefs.largeDistanceUnit) {
                ForEach(LargeDistanceUnit.allCases) { Text($0.rawValue == "parsecs" ? "parsecs" : "light-years").tag($0) }
            }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var skySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Faintest magnitude")
                    Spacer()
                    Text(prefs.skyFilters.magnitudeLimit.formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $prefs.skyFilters.magnitudeLimit, in: 1...6.5, step: 0.5)
            }
        } header: {
            Text("Sky")
        } footer: {
            Text("Sky/AR mode, zoom and all sky filters are remembered automatically as you change them.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var galaxySection: some View {
        Section("Galaxy Map") {
            Toggle("Milky Way backdrop", isOn: $prefs.galaxyMilkyWay)
            Toggle("Planet hosts only", isOn: $prefs.galaxyHostsOnly)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var locationSection: some View {
        Section {
            Toggle("Use home when location unavailable", isOn: $prefs.useHomeFallback)
            if prefs.hasHome, let lat = prefs.homeLatitude, let lon = prefs.homeLongitude {
                LabeledContent("Home") {
                    Text(String(format: "%.2f°, %.2f°", lat, lon))
                        .monospacedDigit()
                }
                Button("Clear home location", role: .destructive) {
                    prefs.homeLatitude = nil
                    prefs.homeLongitude = nil
                    prefs.homeName = nil
                }
            }
            Button {
                if observer.location != nil {
                    prefs.homeLatitude = observer.latitude
                    prefs.homeLongitude = observer.longitude
                    prefs.homeName = nil
                } else {
                    observer.start()   // prompts if not yet determined; a fix enables the save
                }
            } label: {
                Label(observer.location == nil ? "Get current location…"
                                               : "Save current location as home",
                      systemImage: "house")
            }
            .disabled(observer.denied)
        } header: {
            Text("Observing location")
        } footer: {
            Text(observer.denied
                 ? "Location access is off — Tonight can use your saved home instead."
                 : "Tonight and the sky status fall back to your home location when live location is unavailable.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var motionSection: some View {
        Section {
            Toggle("Respect Reduce Motion", isOn: $prefs.respectReduceMotion)
        } header: {
            Text("Motion")
        } footer: {
            Text("Softens the sky and map animations when the system Reduce Motion setting is on.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var resetSection: some View {
        Section {
            Button("Reset all settings", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset all settings to their defaults?",
                                    isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { prefs.reset() }
                }
        } footer: {
            Text("Astrelia \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }
}
