import SwiftUI

/// Plain-language definitions of the astronomy terms that appear in the app, so a
/// curious newcomer never hits an unexplained word. Terms are matched against the
/// labels used on the detail screens (see `GlossaryButton`), and the whole set is
/// browsable from About → Glossary.
struct GlossaryEntry: Identifiable {
    var id: String { title }
    let title: String
    let definition: String
    /// Lowercase fragments that, if found in a row label, surface this entry. The
    /// longest match wins, so "surface temperature" beats the generic "temperature".
    let keywords: [String]
}

enum Glossary {
    static let all: [GlossaryEntry] = [
        GlossaryEntry(title: "Apparent magnitude",
                      definition: "How bright a star looks from Earth. The scale runs backwards — smaller numbers are brighter — and each step of 1 is about 2.5× in brightness.",
                      keywords: ["apparent magnitude"]),
        GlossaryEntry(title: "Absolute magnitude",
                      definition: "How bright a star would appear from a standard distance of 10 parsecs (32.6 light-years) — a fair measure of its true output.",
                      keywords: ["absolute magnitude"]),
        GlossaryEntry(title: "Magnitude",
                      definition: "A measure of brightness on a backwards scale: smaller numbers are brighter.",
                      keywords: ["magnitude"]),
        GlossaryEntry(title: "Luminosity",
                      definition: "The total energy a star radiates each second, given here as a multiple of the Sun's output (L☉).",
                      keywords: ["luminosity"]),
        GlossaryEntry(title: "Spectral type",
                      definition: "A star's classification by temperature and colour — the sequence O B A F G K M, hottest to coolest — often with a number and a luminosity class (I supergiant … V dwarf).",
                      keywords: ["spectral"]),
        GlossaryEntry(title: "Colour index (B−V)",
                      definition: "The difference between a star's brightness in blue and visual light. It tracks colour and temperature: smaller or negative is bluer and hotter.",
                      keywords: ["colour index", "color index", "b−v", "b-v"]),
        GlossaryEntry(title: "Surface temperature",
                      definition: "The temperature of a star's visible surface, in kelvin — what sets its colour.",
                      keywords: ["surface temperature"]),
        GlossaryEntry(title: "Equilibrium temperature",
                      definition: "A planet's estimated temperature from the starlight it absorbs alone, before any greenhouse warming from an atmosphere.",
                      keywords: ["equilibrium"]),
        GlossaryEntry(title: "Temperature",
                      definition: "A body's characteristic temperature in kelvin (and °C). For planets this is the equilibrium temperature; for stars, the surface temperature.",
                      keywords: ["temperature"]),
        GlossaryEntry(title: "Parsec",
                      definition: "The standard astronomical distance unit — about 3.26 light-years (30.9 trillion km) — based on a star's parallax shift.",
                      keywords: ["parsec", "distance"]),
        GlossaryEntry(title: "Light-year",
                      definition: "The distance light travels in one year — about 9.46 trillion km.",
                      keywords: ["light-year", "light year"]),
        GlossaryEntry(title: "Radius",
                      definition: "The size of a body. Stars are given in solar radii (R☉); planets in Earth radii (R⊕).",
                      keywords: ["radius"]),
        GlossaryEntry(title: "Mass",
                      definition: "How much matter a body contains. Planets are given in Earth masses (M⊕).",
                      keywords: ["mass"]),
        GlossaryEntry(title: "Orbit radius (semi-major axis)",
                      definition: "The average size of an orbit — half its longest diameter — here in astronomical units (AU, the Earth–Sun distance).",
                      keywords: ["orbit radius", "semi-major", "semimajor"]),
        GlossaryEntry(title: "Orbital period",
                      definition: "The time a body takes to complete one orbit — its 'year'.",
                      keywords: ["orbital period", "period"]),
        GlossaryEntry(title: "Eccentricity",
                      definition: "How stretched an orbit is: 0 is a perfect circle; closer to 1 is a long, narrow ellipse.",
                      keywords: ["eccentricity"]),
        GlossaryEntry(title: "Habitable zone",
                      definition: "The band of orbits around a star where a planet could hold liquid water on its surface — not too hot, not too cold.",
                      keywords: ["habitable"]),
        GlossaryEntry(title: "Right ascension",
                      definition: "The sky's version of longitude — an object's east–west coordinate, measured in hours.",
                      keywords: ["right ascension", "ascension"]),
        GlossaryEntry(title: "Declination",
                      definition: "The sky's version of latitude — an object's north–south coordinate, in degrees.",
                      keywords: ["declination"]),
        GlossaryEntry(title: "Constellation",
                      definition: "One of 88 official regions of the sky, each anchored by a named star pattern.",
                      keywords: ["constellation"]),
        GlossaryEntry(title: "Hipparcos (HIP)",
                      definition: "A star's identifier in the Hipparcos Catalogue, ESA's precise astrometric survey.",
                      keywords: ["hipparcos"]),
        GlossaryEntry(title: "Henry Draper (HD)",
                      definition: "A star's identifier in the Henry Draper Catalogue, which classified stars by spectrum.",
                      keywords: ["henry draper"]),
        GlossaryEntry(title: "Bright Star (HR)",
                      definition: "A star's number in the Yale Bright Star Catalogue of naked-eye stars.",
                      keywords: ["bright star"]),
        GlossaryEntry(title: "Gliese",
                      definition: "A designation from the Gliese Catalogue of nearby stars.",
                      keywords: ["gliese"]),
    ]

    /// The glossary entry that best matches a row label, or `nil` if none. Picks the
    /// entry whose longest keyword is contained in the (normalised) label.
    static func define(_ label: String) -> GlossaryEntry? {
        let normalized = label.lowercased()
        var best: (entry: GlossaryEntry, length: Int)?
        for entry in all {
            for keyword in entry.keywords where normalized.contains(keyword) {
                if best == nil || keyword.count > best!.length { best = (entry, keyword.count) }
            }
        }
        return best?.entry
    }
}

/// A small "ⓘ" affordance that, when a row label has a glossary entry, reveals a
/// one-line plain-language definition in a popover. Renders nothing for labels with
/// no entry, so it can be dropped beside any label freely.
struct GlossaryButton: View {
    let label: String
    @State private var show = false

    var body: some View {
        if let entry = Glossary.define(label) {
            Button { show = true } label: {
                Image(systemName: "info.circle").font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What is \(entry.title)?")
            .popover(isPresented: $show) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title).font(.headline)
                    Text(entry.definition).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// A browsable list of every glossary term, reached from About → Glossary.
struct GlossaryView: View {
    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Glossary.all.sorted { $0.title < $1.title }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.headline).foregroundStyle(.white)
                            Text(entry.definition).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .luminousSurface(.gray)
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }
}
