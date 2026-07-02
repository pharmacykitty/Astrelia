import CelestialCore
import Foundation

/// A personalised "today" generated from the day's transits to a chart.
public struct DailyReading: Sendable {
    public let date: Date
    public let headline: String
    public let body: String
    /// The handful of transits the reading is built from (tightest first).
    public let highlights: [TransitHit]

    public init(date: Date, headline: String, body: String, highlights: [TransitHit]) {
        self.date = date; self.headline = headline; self.body = body; self.highlights = highlights
    }
}

public enum Daily {

    /// Bodies whose transits drive a *daily* read (fast movers matter most today).
    private static let dayMovers: Set<AstroBody> = [.moon, .sun, .mercury, .venus, .mars]

    public static func reading(
        for natal: NatalChart,
        on date: Date = Date(),
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> DailyReading {
        let transiting = NatalChart(at: JulianDay(date), location: natal.location,
                                    settings: natal.settings, ephemeris: ephemeris)
        let all = Transits.hits(transiting: transiting.positions, natal: natal.positions,
                                policy: natal.settings.orbs)
        // Prefer today's fast movers, then tightest orb.
        let ranked = all.sorted { lhs, rhs in
            let lf = dayMovers.contains(lhs.transiting), rf = dayMovers.contains(rhs.transiting)
            if lf != rf { return lf }
            return lhs.orb < rhs.orb
        }
        let highlights = Array(ranked.prefix(3))

        guard let lead = highlights.first else {
            return DailyReading(date: date, headline: "A quiet sky",
                                body: "No close transits to your chart today — a calm, unhurried day to set your own pace.",
                                highlights: [])
        }

        let headline = self.headline(for: lead)
        var lines = highlights.map { Interpretation.transit($0.kind, transiting: $0.transiting, natal: $0.natal) }
        // Keep the body to two sentences for a glanceable card.
        if lines.count > 2 { lines = Array(lines.prefix(2)) }
        return DailyReading(date: date, headline: headline, body: lines.joined(separator: " "),
                            highlights: highlights)
    }

    private static func headline(for hit: TransitHit) -> String {
        switch hit.kind {
        case .trine, .sextile: return "A day for momentum"
        case .conjunction: return "A day to begin something"
        case .square, .sesquiquadrate, .semisquare: return "A day that asks for effort"
        case .opposition: return "A day to find balance"
        case .quincunx: return "A day to adjust"
        case .quintile, .biquintile: return "A day for a creative spark"
        case .semisextile: return "A subtle, shifting day"
        }
    }
}
