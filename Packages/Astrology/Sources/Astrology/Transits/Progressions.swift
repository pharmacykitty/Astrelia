import CelestialCore
import Foundation

/// A **secondary-progressed** chart — the most widely used predictive technique
/// after transits. The principle is "a day for a year": the chart for age *N*
/// years is the real sky *N* days after birth. The slow inner unfolding of a
/// life, read against the *natal* houses and as cross-aspects to the natal
/// positions (see `docs/astrology-features.md`).
///
/// The headline mover is the **progressed Moon** (a full sign roughly every two
/// and a half years) and the **progressed Sun** (about a degree a year, changing
/// sign roughly every thirty years).
public struct ProgressedChart: Sendable, Hashable {
    /// The calendar moment this progression is calculated for.
    public let date: Date
    /// The natal chart being progressed.
    public let natal: NatalChart
    /// The "day-for-a-year" instant whose sky gives the progressed positions.
    public let progressedJD: JulianDay
    /// Whole + fractional tropical years of life elapsed at `date`.
    public let age: Double
    /// Progressed body positions, in the natal chart's zodiac frame.
    public let positions: [BodyPosition]
    /// The solar arc — how far the Sun has progressed from its natal place.
    /// The basis of solar-arc directions (every point advanced by this amount).
    public let solarArc: Angle
    /// The natal Ascendant advanced by the solar arc (chart frame).
    public let directedAscendant: Angle
    /// The natal Midheaven advanced by the solar arc (chart frame).
    public let directedMidheaven: Angle
    /// Progressed→natal cross-aspects, tightest first.
    public let aspectsToNatal: [TransitHit]

    /// The natal house a progressed body currently occupies (1...12).
    public func house(of body: AstroBody) -> Int? {
        guard let p = position(of: body) else { return nil }
        return natal.houses.house(of: p.longitude)
    }

    /// The progressed position record for a body, if present.
    public func position(of body: AstroBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }
}

/// Secondary progressions ("a day for a year") and the solar-arc directions that
/// fall out of them. Pure computation on `CelestialCore`; no UI, no licensing.
public enum Progressions {

    /// Length of the tropical year in days — the day↔year conversion factor.
    public static let tropicalYear = 365.2422

    /// The secondary-progressed Julian Day for `date`: the natal JD plus one day
    /// for every elapsed tropical year of life.
    public static func progressedJD(natalJD: JulianDay, at date: Date) -> JulianDay {
        let years = (JulianDay(date).value - natalJD.value) / tropicalYear
        return JulianDay(natalJD.value + years)
    }

    /// Build the secondary-progressed chart for `date`.
    public static func chart(
        for natal: NatalChart,
        at date: Date = Date(),
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> ProgressedChart {
        let pJD = progressedJD(natalJD: natal.julianDay, at: date)
        let age = (JulianDay(date).value - natal.julianDay.value) / tropicalYear
        let zodiac = natal.settings.zodiac

        var positions: [BodyPosition] = []
        for body in natal.settings.bodies {
            if let p = ephemeris.position(of: body, at: pJD, zodiac: zodiac) {
                positions.append(p)
            }
        }

        // Solar arc = progressed Sun − natal Sun (the subtraction cancels any
        // ayanamsa, so it is the same in tropical or sidereal frames).
        let natalSun = natal.position(of: .sun)?.longitude
        let progSun = positions.first { $0.body == .sun }?.longitude
        let arc: Angle = (natalSun != nil && progSun != nil)
            ? (progSun! - natalSun!).normalized
            : .zero

        // Direct the natal angles by the solar arc, in the chart's zodiac frame.
        let natalAscFrame = zodiac.longitude(fromTropical: natal.angles.ascendant, at: natal.julianDay)
        let natalMCFrame = zodiac.longitude(fromTropical: natal.angles.midheaven, at: natal.julianDay)
        let directedAsc = (natalAscFrame + arc).normalized
        let directedMC = (natalMCFrame + arc).normalized

        // The reading: progressed planets cross-aspecting the fixed natal chart.
        let aspects = Transits.hits(
            transiting: positions, natal: natal.positions, policy: natal.settings.orbs)

        return ProgressedChart(
            date: date, natal: natal, progressedJD: pJD, age: age,
            positions: positions, solarArc: arc,
            directedAscendant: directedAsc, directedMidheaven: directedMC,
            aspectsToNatal: aspects)
    }
}
