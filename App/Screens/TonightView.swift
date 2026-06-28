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
    @State private var computing = false

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
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Tonight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if fixedLocation == nil { observer.start() } }
        .onDisappear { observer.stop() }
        .task(id: observer.latitude) { await recompute() }
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
        if observer.denied && fixedLocation == nil {
            ContentUnavailableView("Location needed",
                                   systemImage: "location.slash",
                                   description: Text("Tonight's sky depends on where you are. Enable location for Astrolabe in Settings."))
                .foregroundStyle(.white)
        } else {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
        }
    }

    private func moonCard(_ phase: MoonPhase, _ moon: SkyBodyStatus) -> some View {
        HStack(spacing: 14) {
            Image(systemName: moonSymbol(phase))
                .font(.system(size: 40)).foregroundStyle(.white.opacity(0.9))
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

    private var sunCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill").font(.system(size: 34)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(sun?.isUp == true ? "The Sun is up" : "Night").font(.headline).foregroundStyle(.white)
                if let sun {
                    Text(sun.isUp ? (sun.nextSet.map { "Sets at \(time($0))" } ?? "")
                                  : (sun.nextRise.map { "Sunrise at \(time($0))" } ?? ""))
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(14).luminousSurface(.orange)
    }

    @ViewBuilder
    private var planetSection: some View {
        let up = planets.filter(\.isUp).sorted { $0.altitude.degrees > $1.altitude.degrees }
        let down = planets.filter { !$0.isUp }.sorted { ($0.nextRise ?? .distantFuture) < ($1.nextRise ?? .distantFuture) }

        if !up.isEmpty {
            sectionLabel("Planets up now", "sparkles")
            VStack(spacing: 0) { ForEach(up) { planetRow($0, up: true) } }.luminousSurface(.cyan)
        }
        if !down.isEmpty {
            sectionLabel("Below the horizon", "arrow.down.to.line")
            VStack(spacing: 0) { ForEach(down) { planetRow($0, up: false) } }
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
            VStack(spacing: 0) { ForEach(active) { showerRow($0) } }.luminousSurface(.pink)
        }
    }

    private func showerRow(_ shower: MeteorShower) -> some View {
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
        .overlay(Divider().background(.white.opacity(0.08)), alignment: .bottom)
    }

    private func sectionLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            .padding(.top, 4)
    }

    private func planetRow(_ body: SkyBodyStatus, up: Bool) -> some View {
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
        .overlay(Divider().background(.white.opacity(0.08)), alignment: .bottom)
    }

    // MARK: Compute

    private func recompute() async {
        guard let loc = fixedLocation ?? observer.location, !computing else { return }
        computing = true
        let date = Date()
        // Rise/set scanning is heavy (ephemeris over 24h); keep it off the main actor.
        let result = await Task.detached(priority: .userInitiated) {
            (VisibleSky.status(at: loc, date: date), VisibleSky.moonPhase(at: date))
        }.value
        statuses = result.0
        phase = result.1
        asOf = date
        computing = false
    }

    // MARK: Formatting

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    private func direction(_ azimuth: CelestialCore.Angle) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int((azimuth.degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5)
                    .truncatingRemainder(dividingBy: 360) / 45)
        return "to the \(points[i % 8])"
    }

    private func moonSymbol(_ phase: MoonPhase) -> String {
        let f = phase.illuminatedFraction
        if f < 0.04 { return "moonphase.new.moon" }
        if f > 0.96 { return "moonphase.full.moon" }
        if f < 0.46 { return phase.isWaxing ? "moonphase.waxing.crescent" : "moonphase.waning.crescent" }
        if f < 0.54 { return phase.isWaxing ? "moonphase.first.quarter" : "moonphase.last.quarter" }
        return phase.isWaxing ? "moonphase.waxing.gibbous" : "moonphase.waning.gibbous"
    }
}
