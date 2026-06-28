import SwiftUI

/// The About / Sources screen. Credits every dataset, library, and reference the
/// app relies on, with licences and links — both to honour attribution terms
/// (several are required before shipping) and because the data provenance is part
/// of the product. Keep this in sync as new sources are added (see `CLAUDE.md`).
struct AboutView: View {
    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    ForEach(SourceCatalog.groups) { group in
                        sourceGroup(group)
                    }
                    footer
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 12) {
            LuminousGlyph(symbol: "books.vertical.fill", tint: .gray, size: 96, glyphSize: 40)
            Text("Sources & Credits")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.white).multilineTextAlignment(.center)
            Text("Every position, fact, and figure in Astrolabe comes from open astronomical data and published algorithms. The people and projects behind them:")
                .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func sourceGroup(_ group: SourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    sourceRow(entry, isLast: entry.id == group.entries.last?.id)
                }
            }
            .luminousSurface(group.tint)
        }
    }

    private func sourceRow(_ entry: SourceEntry, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name).font(.headline).foregroundStyle(.white)
                Spacer()
                if let license = entry.license {
                    Text(license).font(.caption2.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(entry.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if let url = entry.url, let link = URL(string: url) {
                Link(destination: link) {
                    Text(url.replacingOccurrences(of: "https://", with: ""))
                        .font(.caption).foregroundStyle(Theme.accent)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().background(.white.opacity(0.08)) }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Astrolabe")
                .font(.system(.headline, design: .serif)).foregroundStyle(.white.opacity(0.8))
            Text("Built with respect for the open astronomy community.")
                .font(.caption).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Source data

struct SourceEntry: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    var license: String? = nil
    var url: String? = nil
}

struct SourceGroup: Identifiable {
    let id = UUID()
    let title: String
    let tint: Color
    let entries: [SourceEntry]
}

/// The single source of truth for the app's attributions. Add to this whenever a
/// new dataset, library, or algorithm is introduced (see `CLAUDE.md` convention).
enum SourceCatalog {
    static let groups: [SourceGroup] = [
        SourceGroup(title: "Star Catalogs", tint: .yellow, entries: [
            SourceEntry(name: "HYG Database",
                        detail: "~119k stars combining the Hipparcos, Yale Bright Star, and Gliese catalogs — proper names, positions, parallax distances, magnitudes, spectral types, and B−V colour. Compiled by David Nash (astronexus).",
                        license: "Public domain",
                        url: "https://github.com/astronexus/HYG-Database"),
            SourceEntry(name: "Hipparcos & Tycho Catalogues",
                        detail: "ESA's astrometric survey — the parallax distances and precise positions underlying the HYG data.",
                        license: "ESA / public"),
            SourceEntry(name: "Constellation lines",
                        detail: "Stick-figure constellation geometry from the d3-celestial project by Olaf Frohn.",
                        license: "BSD-3-Clause",
                        url: "https://github.com/ofrohn/d3-celestial"),
        ]),
        SourceGroup(title: "Planets & Exoplanets", tint: .cyan, entries: [
            SourceEntry(name: "NASA Exoplanet Archive",
                        detail: "The Planetary Systems (PS) table — ~6,300 confirmed planets across ~4,700 systems with orbital, mass, radius, and host-star parameters. Operated by Caltech/IPAC under contract with NASA.",
                        license: "Public domain",
                        url: "https://exoplanetarchive.ipac.caltech.edu"),
            SourceEntry(name: "NASA/JPL Planetary Fact Sheets",
                        detail: "Physical data for the Solar System's planets and major moons (radii, masses, orbits, temperatures).",
                        license: "Public domain",
                        url: "https://nssdc.gsfc.nasa.gov/planetary/factsheet"),
            SourceEntry(name: "Meteor shower calendar",
                        detail: "Peak dates, activity windows, radiants, and rates for the major annual showers, from the International Meteor Organization (IMO) working list.",
                        url: "https://www.imo.net"),
            SourceEntry(name: "Habitable-zone model",
                        detail: "Conservative habitable-zone boundaries from Kopparapu et al. (2013), simplified to a stellar-luminosity form.",
                        url: "https://doi.org/10.1088/0004-637X/765/2/131"),
        ]),
        SourceGroup(title: "Ephemeris & Astronomy Math", tint: .purple, entries: [
            SourceEntry(name: "Astronomical Algorithms (Meeus)",
                        detail: "Jean Meeus' standard reference — the basis for our Julian date, sidereal time, coordinate transforms, and Sun (Ch. 25), Moon (Ch. 47), and Pluto (Ch. 37) positions.",
                        license: "Reference"),
            SourceEntry(name: "SwiftAA",
                        detail: "Swift port of Meeus' algorithms by onekiloparsec; used for Mercury–Neptune apparent geocentric ecliptic longitudes.",
                        license: "MIT",
                        url: "https://github.com/onekiloparsec/SwiftAA"),
            SourceEntry(name: "VSOP87 planetary theory",
                        detail: "Bretagnon & Francou's analytical planetary theory, underpinning the planet positions used in charts.",
                        license: "Reference"),
            SourceEntry(name: "Ballesteros' formula (2012)",
                        detail: "Estimates a star's surface temperature from its B−V colour index, used for the derived temperatures in the catalog.",
                        url: "https://doi.org/10.1209/0295-5075/97/34008"),
            SourceEntry(name: "Stefan–Boltzmann law",
                        detail: "Relates a star's luminosity, radius, and temperature (L ∝ R²T⁴); used with IAU 2015 nominal solar values to derive each star's approximate radius for the size comparisons.",
                        license: "Reference"),
            SourceEntry(name: "Stellar evolution (general)",
                        detail: "The plain-language 'life story' of each star — main-sequence lifetimes by spectral class and end states (white dwarf, supernova) — follows standard stellar-astrophysics references.",
                        license: "Reference"),
        ]),
        SourceGroup(title: "Astrology", tint: .orange, entries: [
            SourceEntry(name: "Rolled our own",
                        detail: "All astrology math (zodiac, ayanamsa, Ascendant/MC, house systems, aspects, charts) is computed on CelestialCore — no Swiss Ephemeris (AGPL/commercial). Validated against astro.com reference charts.",
                        license: "In-house"),
            SourceEntry(name: "House systems & aspects",
                        detail: "Placidus / Whole Sign / Equal / Porphyry cusps and major/minor aspect definitions from published astrological references.",
                        license: "Reference"),
            SourceEntry(name: "Lahiri ayanamsa",
                        detail: "Sidereal-zodiac offset for the sidereal calculation mode.",
                        license: "Reference"),
        ]),
    ]
}

#Preview {
    NavigationStack { AboutView() }
        .preferredColorScheme(.dark)
}
