import Foundation

/// A major annual meteor shower. Unlike satellite passes (which need fresh orbital
/// elements), showers recur on a near-fixed calendar year to year, so they bundle
/// cleanly offline. Dates are (month, day); the radiant lets us say where to look.
///
/// Data: International Meteor Organization (IMO) working list — see About → Sources.
public struct MeteorShower: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let activeStart: MonthDay
    public let peak: MonthDay
    public let activeEnd: MonthDay
    /// Zenithal hourly rate at peak under ideal skies (a rough "how rich").
    public let zhr: Int
    public let radiantConstellation: String
    public let radiantRA: Angle
    public let radiantDec: Angle
    public let parentBody: String

    public struct MonthDay: Sendable, Hashable {
        public let month: Int
        public let day: Int
        public init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
        var ordinal: Int { month * 100 + day }   // MMDD, for same-window comparison
    }
}

public enum MeteorShowers {

    /// The major showers worth surfacing (IMO working list; ZHR ≥ ~10).
    public static let all: [MeteorShower] = [
        MeteorShower(name: "Quadrantids", activeStart: .init(12, 28), peak: .init(1, 3), activeEnd: .init(1, 12),
                     zhr: 110, radiantConstellation: "Boötes", radiantRA: .degrees(230), radiantDec: .degrees(49),
                     parentBody: "asteroid 2003 EH₁"),
        MeteorShower(name: "Lyrids", activeStart: .init(4, 16), peak: .init(4, 22), activeEnd: .init(4, 25),
                     zhr: 18, radiantConstellation: "Lyra", radiantRA: .degrees(271), radiantDec: .degrees(34),
                     parentBody: "comet Thatcher"),
        MeteorShower(name: "Eta Aquariids", activeStart: .init(4, 19), peak: .init(5, 6), activeEnd: .init(5, 28),
                     zhr: 50, radiantConstellation: "Aquarius", radiantRA: .degrees(338), radiantDec: .degrees(-1),
                     parentBody: "comet Halley"),
        MeteorShower(name: "Delta Aquariids", activeStart: .init(7, 12), peak: .init(7, 30), activeEnd: .init(8, 23),
                     zhr: 25, radiantConstellation: "Aquarius", radiantRA: .degrees(340), radiantDec: .degrees(-16),
                     parentBody: "comet 96P/Machholz"),
        MeteorShower(name: "Perseids", activeStart: .init(7, 17), peak: .init(8, 12), activeEnd: .init(8, 24),
                     zhr: 100, radiantConstellation: "Perseus", radiantRA: .degrees(48), radiantDec: .degrees(58),
                     parentBody: "comet Swift–Tuttle"),
        MeteorShower(name: "Orionids", activeStart: .init(10, 2), peak: .init(10, 21), activeEnd: .init(11, 7),
                     zhr: 20, radiantConstellation: "Orion", radiantRA: .degrees(95), radiantDec: .degrees(16),
                     parentBody: "comet Halley"),
        MeteorShower(name: "Leonids", activeStart: .init(11, 6), peak: .init(11, 17), activeEnd: .init(11, 30),
                     zhr: 15, radiantConstellation: "Leo", radiantRA: .degrees(152), radiantDec: .degrees(22),
                     parentBody: "comet Tempel–Tuttle"),
        MeteorShower(name: "Geminids", activeStart: .init(12, 4), peak: .init(12, 14), activeEnd: .init(12, 20),
                     zhr: 150, radiantConstellation: "Gemini", radiantRA: .degrees(112), radiantDec: .degrees(33),
                     parentBody: "asteroid 3200 Phaethon"),
        MeteorShower(name: "Ursids", activeStart: .init(12, 17), peak: .init(12, 22), activeEnd: .init(12, 26),
                     zhr: 10, radiantConstellation: "Ursa Minor", radiantRA: .degrees(217), radiantDec: .degrees(76),
                     parentBody: "comet 8P/Tuttle"),
    ]

    /// Whether a shower is within its active window on `date` (inclusive). Handles
    /// windows that wrap the new year (e.g. Quadrantids, Dec 28 → Jan 12).
    public static func isActive(_ shower: MeteorShower, on date: Date) -> Bool {
        let md = monthDay(of: date)
        let start = shower.activeStart.ordinal, end = shower.activeEnd.ordinal, now = md.ordinal
        return start <= end ? (now >= start && now <= end)   // within one calendar year
                            : (now >= start || now <= end)   // wraps the new year
    }

    /// Showers active on `date`, soonest peak first.
    public static func active(on date: Date = Date()) -> [MeteorShower] {
        all.filter { isActive($0, on: date) }
           .sorted { daysUntilPeak($0, from: date) < daysUntilPeak($1, from: date) }
    }

    /// The next shower to reach its peak after `date` (wrapping into next year).
    public static func nextUpcoming(after date: Date = Date()) -> MeteorShower? {
        all.min { daysUntilPeak($0, from: date) < daysUntilPeak($1, from: date) }
    }

    /// Whole days from `date` to a shower's next peak (0 = peaks today; always ≥ 0).
    public static func daysUntilPeak(_ shower: MeteorShower, from date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: date)
        let year = cal.component(.year, from: today)
        for y in [year, year + 1] {
            if let peak = cal.date(from: DateComponents(year: y, month: shower.peak.month, day: shower.peak.day)) {
                let days = cal.dateComponents([.day], from: today, to: peak).day ?? 0
                if days >= 0 { return days }
            }
        }
        return 0
    }

    private static func monthDay(of date: Date) -> MeteorShower.MonthDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.month, .day], from: date)
        return .init(c.month ?? 1, c.day ?? 1)
    }
}
