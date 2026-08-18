import SwiftUI
import CelestialCore

/// "What's in the sky right now" — the Moon's phase, whether it's day or night, and
/// which naked-eye planets are up (with where to look and when they rise/set),
/// computed from the observer's location on the same ephemeris as the planetarium.
struct TonightView: View {
    /// Bypasses CoreLocation for previews/snapshots.
    var fixedLocation: GeographicLocation? = nil

    @State private var observer = ObserverLocation()
    @State private var statuses: [SkyBodyStatus] = []
    @State private var phase: MoonPhase?
    @State private var asOf = Date()
    @State private var events: [AstroEvent] = []

    private var sun: SkyBodyStatus? { statuses.first { $0.kind == .sun } }
    private var moon: SkyBodyStatus? { statuses.first { $0.kind == .moon } }
    private var planets: [SkyBodyStatus] { statuses.filter { $0.kind == .planet } }
    private var isNight: Bool { (sun?.altitude.degrees ?? 90) < -6 }   // civil dusk

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if statuses.isEmpty {
                        loadingOrPermission
                    } else {
                        if let phase, let moon { moonCard(phase, moon) }
                        sunCard
                        planetSection
                    }
                    meteorSection   // calendar-based; shown regardless of location
                    eventsSection   // ephemeris-based; shown regardless of location
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        // No nav-bar title: the serif "Tonight's Sky" hero owns the name — a bar
        // saying "Tonight" directly above it printed the word twice.
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if fixedLocation == nil { observer.start() } }
        .onDisappear { observer.stop() }
        // Keyed on the full coordinate (not just latitude!) so an east–west move
        // recomputes rise/set times too. `.task(id:)` cancels and restarts on
        // change, which is the whole dedup story — no busy flag needed.
        .task(id: locationKey) { await recompute() }
        .task {
            // Events are geocentric (location-independent) and the 60-day search is
            // heavy, so compute once off the main actor — never in the view body.
            events = await Task.detached(priority: .utility) {
                AstroEvent.upcoming(after: Date(), within: 60)
            }.value
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            LuminousGlyph(symbol: "moon.stars.fill", tint: .indigo, size: 84, glyphSize: 36)
            Text("Tonight's Sky").font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.white)
            Text(isNight ? "The Sun is down — good viewing." : "Daytime — planets show best after sunset.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    @ViewBuilder
    private var loadingOrPermission: some View {
        if observer.denied && fixedLocation == nil && homeLocation == nil {
            ContentUnavailableView("Location needed",
                                   systemImage: "location.slash",
                                   description: Text("Tonight's sky depends on where you are. Enable location for Stellaria in Settings — or save a home location in the app's Settings."))
                .foregroundStyle(.white)
        } else {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
        }
    }

    private func moonCard(_ phase: MoonPhase, _ moon: SkyBodyStatus) -> some View {
        HStack(spacing: 14) {
            MoonPhaseDisc(fraction: phase.illuminatedFraction, waxing: phase.isWaxing)
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)   // the text beside it says the same
            VStack(alignment: .leading, spacing: 3) {
                Text(phase.name).font(.headline).foregroundStyle(.white)
                Text("\(Int((phase.illuminatedFraction * 100).rounded()))% lit · \(phase.isWaxing ? "waxing" : "waning")")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Text(moon.isUp ? "Up now — \(direction(moon.azimuth)), \(Int(moon.altitude.degrees))° high"
                              : "Below the horizon" + (moon.nextRise.map { " · rises \(time($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(14).luminousSurface(.indigo)
    }

    /// The day/night card. At night the glyph is the *next* event — a sunrise on
    /// the horizon, in a cooler dawn amber — not a blazing midday sun contradicting
    /// the "Night" title beside it.
    private var sunCard: some View {
        let isUp = sun?.isUp == true
        let dawnAmber = Color(red: 0.93, green: 0.71, blue: 0.45)
        return HStack(spacing: 14) {
            Image(systemName: isUp ? "sun.max.fill" : "sunrise.fill")
                .font(.system(size: 34))
                .foregroundStyle(isUp ? .orange : dawnAmber)
            VStack(alignment: .leading, spacing: 3) {
                Text(isUp ? "The Sun is up" : "Night").font(.headline).foregroundStyle(.white)
                if let sun {
                    Text(sun.isUp ? (sun.nextSet.map { "Sets at \(time($0))" } ?? "")
                                  : (sun.nextRise.map { "Sunrise at \(time($0))" } ?? ""))
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(14).luminousSurface(isUp ? .orange : .indigo)
    }

    @ViewBuilder
    private var planetSection: some View {
        let up = planets.filter(\.isUp).sorted { $0.altitude.degrees > $1.altitude.degrees }
        let down = planets.filter { !$0.isUp }.sorted { ($0.nextRise ?? .distantFuture) < ($1.nextRise ?? .distantFuture) }

        if !up.isEmpty {
            sectionLabel("Planets up now", "sparkles")
            VStack(spacing: 0) {
                ForEach(Array(up.enumerated()), id: \.element.id) { i, body in
                    planetRow(body, up: true, divider: i < up.count - 1)
                }
            }
            .luminousSurface(.cyan)
        }
        if !down.isEmpty {
            sectionLabel("Below the horizon", "arrow.down.to.line")
            VStack(spacing: 0) {
                ForEach(Array(down.enumerated()), id: \.element.id) { i, body in
                    planetRow(body, up: false, divider: i < down.count - 1)
                }
            }
            .luminousSurface(Color(white: 0.6))
        }
    }

    @ViewBuilder
    private var meteorSection: some View {
        let active = MeteorShowers.active(on: asOf)
        sectionLabel("Meteor showers", "sparkles")
        if active.isEmpty {
            if let next = MeteorShowers.nextUpcoming(after: asOf) {
                VStack(spacing: 0) { showerRow(next) }.luminousSurface(.pink)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(active.enumerated()), id: \.element.id) { i, shower in
                    showerRow(shower, divider: i < active.count - 1)
                }
            }
            .luminousSurface(.pink)
        }
    }

    private func showerRow(_ shower: MeteorShower, divider: Bool = false) -> some View {
        let days = MeteorShowers.daysUntilPeak(shower, from: asOf)
        let when = days == 0 ? "peaks tonight" : days == 1 ? "peaks tomorrow" : "peaks in \(days) days"
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shower.name).foregroundStyle(.white)
                Text("from \(shower.radiantConstellation) · up to \(shower.zhr)/hr at peak")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(when).font(.subheadline).foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { if divider { Divider().background(.white.opacity(0.08)) } }
    }

    @ViewBuilder
    private var eventsSection: some View {
        let shown = Array(events.prefix(8))
        if !shown.isEmpty {
            sectionLabel("Upcoming events", "calendar")
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, event in
                    eventRow(event, divider: i < shown.count - 1)
                }
            }
            .luminousSurface(.teal)
        }
    }

    private func eventRow(_ event: AstroEvent, divider: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: eventSymbol(event.kind)).font(.caption)
                .foregroundStyle(.teal).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).foregroundStyle(.white)
                Text(event.detail).font(.caption).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(relativeDay(event.date)).font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { if divider { Divider().background(.white.opacity(0.08)) } }
    }

    private func eventSymbol(_ kind: AstroEvent.Kind) -> String {
        switch kind {
        case .solstice, .equinox: "sun.max"
        case .newMoon: "moonphase.new.moon"
        case .firstQuarter: "moonphase.first.quarter"
        case .fullMoon: "moonphase.full.moon"
        case .lastQuarter: "moonphase.last.quarter"
        case .opposition, .conjunction: "circle.circle"
        case .greatestElongation: "arrow.left.and.right"
        case .perigee, .apogee: "moon.circle"
        case .perihelion, .aphelion: "sun.min"
        case .solarEclipse, .lunarEclipse: "circle.lefthalf.filled"
        }
    }

    private func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: asOf),
                                      to: cal.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "tomorrow" }
        if days < 7 { return "in \(days) days" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func sectionLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            .padding(.top, 4)
    }

    private func planetRow(_ body: SkyBodyStatus, up: Bool, divider: Bool = true) -> some View {
        HStack {
            Text(body.name).foregroundStyle(.white)
            Spacer()
            if up {
                Text("\(direction(body.azimuth)) · \(Int(body.altitude.degrees))° high")
                    .foregroundStyle(.white.opacity(0.7))
                if let set = body.nextSet {
                    Text("sets \(time(set))").foregroundStyle(.white.opacity(0.45)).font(.caption)
                }
            } else if let rise = body.nextRise {
                Text("rises \(time(rise))").foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { if divider { Divider().background(.white.opacity(0.08)) } }
    }

    // MARK: Compute

    /// A stable identity for the observer's coordinate, driving `.task(id:)`.
    private var locationKey: String? {
        (fixedLocation ?? observer.location ?? homeLocation).map {
            "\($0.latitude.degrees),\($0.longitude.degrees)"
        }
    }

    /// Settings' saved home observing spot — the fallback when live location
    /// is denied or hasn't arrived yet (docs/preferences-spec.md).
    private var homeLocation: GeographicLocation? {
        let p = AppPreferences.shared
        guard p.useHomeFallback, let lat = p.homeLatitude, let lon = p.homeLongitude else { return nil }
        return GeographicLocation(latitude: .degrees(lat), longitude: .degrees(lon))
    }

    private func recompute() async {
        guard let loc = fixedLocation ?? observer.location ?? homeLocation else { return }
        let date = Date()
        // Rise/set scanning is heavy (ephemeris over 24h); keep it off the main actor.
        let result = await Task.detached(priority: .userInitiated) {
            (VisibleSky.status(at: loc, date: date), VisibleSky.moonPhase(at: date))
        }.value
        guard !Task.isCancelled else { return }   // a newer location's task took over
        statuses = result.0
        phase = result.1
        asOf = date
    }

    // MARK: Formatting

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    private func direction(_ azimuth: CelestialCore.Angle) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int((azimuth.degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5)
                    .truncatingRemainder(dividingBy: 360) / 45)
        return "to the \(points[i % 8])"
    }

}

/// The Moon drawn as it actually looks tonight — warm lunar surface, a few maria,
/// and the terminator placed from the live `illuminatedFraction`/`isWaxing`
/// (northern-hemisphere convention: a waxing Moon lights up from the right limb).
/// The flat white disc this replaced was the one dead element on the screen.
struct MoonPhaseDisc: View {
    let fraction: Double   // illuminated fraction, 0…1
    let waxing: Bool

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 1
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let discRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
            let disc = Path(ellipseIn: discRect)

            // The lit surface: warm regolith with a soft top-left highlight.
            context.fill(disc, with: .radialGradient(
                Gradient(colors: [Color(red: 0.96, green: 0.93, blue: 0.86),
                                  Color(red: 0.76, green: 0.73, blue: 0.66)]),
                center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3),
                startRadius: 0, endRadius: radius * 1.7))

            // Maria — the familiar dark seas, fixed like the real near side.
            var seas = context
            seas.clip(to: disc)
            let maria: [(x: Double, y: Double, r: Double)] = [
                (-0.28, -0.30, 0.30), (0.16, -0.08, 0.24), (0.02, 0.32, 0.17),
                (-0.42, 0.14, 0.15), (0.40, -0.42, 0.12),
            ]
            for sea in maria {
                let r = radius * sea.r
                seas.fill(Path(ellipseIn: CGRect(x: center.x + sea.x * radius - r,
                                                 y: center.y + sea.y * radius - r,
                                                 width: r * 2, height: r * 2)),
                          with: .color(Color(red: 0.42, green: 0.43, blue: 0.48).opacity(0.30)))
            }

            // The shadow: dark half-disc plus/minus the terminator's half-ellipse.
            let f = max(0, min(1, fraction))
            if f < 0.995 {
                let darkOnRight = !waxing
                let darkHalf = disc.intersection(Path(CGRect(
                    x: darkOnRight ? center.x : center.x - radius,
                    y: center.y - radius, width: radius, height: radius * 2)))
                let k = abs(1 - 2 * f)
                let terminator = Path(ellipseIn: CGRect(x: center.x - radius * k, y: center.y - radius,
                                                        width: radius * 2 * k, height: radius * 2))
                let shadow: Path
                if f >= 0.5 {   // gibbous: the terminator bites into the dark half
                    shadow = darkHalf.subtracting(terminator)
                } else {        // crescent: the shadow bulges across the midline
                    let litHalf = CGRect(x: darkOnRight ? center.x - radius : center.x,
                                         y: center.y - radius, width: radius, height: radius * 2)
                    shadow = darkHalf.union(terminator.intersection(Path(litHalf)))
                }
                // Not quite black — the unlit limb keeps a breath of earthshine.
                context.fill(shadow, with: .color(Color(red: 0.05, green: 0.06, blue: 0.11).opacity(0.93)))
            }

            context.stroke(disc, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
        }
        .shadow(color: Color(red: 0.96, green: 0.93, blue: 0.86).opacity(0.35), radius: 8)
    }
}
