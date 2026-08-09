import Foundation

// Display-unit preferences (docs/preferences-spec.md). Each enum knows how to
// format the SI/astronomy-native value the engines produce — call sites keep
// computing in K / km / light-years and route the *presentation* through these.

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit, kelvin
    var id: Self { self }

    var label: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kelvin: "K"
        }
    }

    /// Format a temperature given in kelvin, e.g. "5,772 K" / "15 °C" / "59 °F".
    func format(kelvin: Double) -> String {
        let value: Double
        switch self {
        case .celsius: value = kelvin - 273.15
        case .fahrenheit: value = (kelvin - 273.15) * 9 / 5 + 32
        case .kelvin: value = kelvin
        }
        let rounded = value.rounded()
        let s = rounded.formatted(.number.precision(.fractionLength(0)))
        return "\(s)\(self == .kelvin ? " K" : " \(label)")"
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometres, miles
    var id: Self { self }

    var label: String {
        switch self {
        case .kilometres: "km"
        case .miles: "mi"
        }
    }

    /// Format a distance given in km, keeping the magnitude readable
    /// ("384,400 km", "238,900 mi", "1.27×10⁷ km" stays plain: "12.7 million km").
    func format(km: Double) -> String {
        let value = self == .miles ? km * 0.6213712 : km
        if value >= 1e6 {
            return "\((value / 1e6).formatted(.number.precision(.fractionLength(0...1)))) million \(label)"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(label)"
    }
}

enum LargeDistanceUnit: String, CaseIterable, Identifiable {
    case lightYears, parsecs
    var id: Self { self }

    var label: String {
        switch self {
        case .lightYears: "ly"
        case .parsecs: "pc"
        }
    }

    /// Format a stellar distance given in light-years.
    func format(lightYears ly: Double) -> String {
        let value = self == .parsecs ? ly / 3.2615638 : ly
        let digits = value < 100 ? 1 : 0
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(label)"
    }
}
