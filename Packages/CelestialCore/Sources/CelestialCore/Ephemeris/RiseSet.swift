import Foundation

/// Finds rise and set times by scanning a body's altitude over time. Works for any
/// body — stars, the Sun, the Moon, planets — because the caller supplies an
/// `altitude(at:)` closure (typically equatorial→horizontal for the observer). This
/// sampling approach handles bodies that move appreciably over a day (Sun, Moon)
/// without a closed-form solution, and stays pure and testable.
public enum RiseSet {

    public enum Event { case rise, set }

    /// Standard horizon altitude for a rise/set: −0.5667° accounts for atmospheric
    /// refraction at the horizon (the Sun/Moon's own semidiameter is left to the
    /// caller if wanted).
    public static let standardHorizon = Angle.degrees(-0.5667)

    /// The first time after `start` that the altitude crosses `horizon` in the given
    /// direction (rising = upward, setting = downward), or `nil` if it doesn't within
    /// `span`. The crossing is linearly interpolated between samples for sub-`step`
    /// accuracy.
    ///
    /// - Parameters:
    ///   - step: sampling interval; 120 s gives ~arc-minute timing for the Sun.
    public static func next(_ event: Event,
                            from start: Date,
                            span: TimeInterval = 86_400,
                            step: TimeInterval = 120,
                            horizon: Angle = standardHorizon,
                            altitude: (Date) -> Angle) -> Date? {
        let h0 = horizon.degrees
        var prev = altitude(start).degrees - h0
        let end = start.addingTimeInterval(span)
        var t = start.addingTimeInterval(step)
        while t <= end {
            let cur = altitude(t).degrees - h0
            let crossingUp = prev < 0 && cur >= 0
            let crossingDown = prev >= 0 && cur < 0
            if (event == .rise && crossingUp) || (event == .set && crossingDown) {
                let frac = -prev / (cur - prev)            // zero-crossing within [t-step, t]
                return t.addingTimeInterval(-step).addingTimeInterval(step * frac)
            }
            prev = cur
            t = t.addingTimeInterval(step)
        }
        return nil
    }

    /// Whether the body is above `horizon` at `date`.
    public static func isUp(at date: Date, horizon: Angle = standardHorizon,
                            altitude: (Date) -> Angle) -> Bool {
        altitude(date).degrees > horizon.degrees
    }
}
