import SwiftUI

/// A top-down orbital view of a planetary system: the host star, its planets on
/// log-AU orbits (sized/coloured by type), and the habitable zone. Tap an orbit to
/// inspect a planet; orbits animate at correct relative (Keplerian) speeds.
struct SystemView: View {
    let system: PlanetarySystem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animate = true
    @State private var selected: Exoplanet?

    // Animation clock that starts at 0 and only advances while playing. Starting
    // near zero keeps sin/cos arguments small (feeding the raw ~7.7e8 s reference
    // interval in loses float precision and makes orbits jitter); accumulating
    // means pausing freezes bodies exactly where they are, not at phase zero.
    @State private var accumulated: Double = 0
    @State private var playStart = Date.timeIntervalSinceReferenceDate

    // Planets we can actually place (need a semi-major axis, directly or derived).
    private var placed: [(planet: Exoplanet, a: Double, phase: Double)] {
        system.planets.enumerated().compactMap { idx, planet in
            guard let a = system.semiMajorAxis(of: planet), a > 0 else { return nil }
            return (planet, a, Double(idx) * 1.4 + 0.3)   // spread starting angles
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.07), .black],
                               startPoint: .top, endPoint: .bottom)

                if placed.isEmpty {
                    ContentUnavailableView("No orbital data",
                                           systemImage: "circle.dashed",
                                           description: Text("The archive has no orbit sizes for \(system.hostName)'s planets yet."))
                        .foregroundStyle(.white)
                } else {
                    TimelineView(.animation(paused: !animate)) { timeline in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        let t = animate ? accumulated + (now - playStart) : accumulated
                        Canvas { context, _ in
                            draw(in: context, size: size, time: t)
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { select(at: $0.location, size: size) })
                }

                overlay(size: size, safe: .deviceSafeArea)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task { if reduceMotion { animate = false } }   // don't auto-spin orbits
    }

    // MARK: Geometry

    private func radii(_ size: CGSize) -> (inner: Double, outer: Double, aMin: Double, aMax: Double) {
        let aValues = placed.map(\.a)
        let aMin = aValues.min() ?? 1, aMax = aValues.max() ?? 1
        let outer = Double(min(size.width, size.height)) * 0.5 - 64
        return (54, max(80, outer), aMin, aMax)
    }

    private func screenRadius(_ a: Double, _ size: CGSize) -> Double {
        let (inner, outer, aMin, aMax) = radii(size)
        guard aMax > aMin else { return (inner + outer) / 2 }
        let f = (log(a) - log(aMin)) / (log(aMax) - log(aMin))
        return inner + f * (outer - inner)
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Habitable zone (conservative, from stellar luminosity).
        if let lum = system.luminositySun, lum > 0 {
            let inner = (lum / 1.1).squareRoot(), outer = (lum / 0.53).squareRoot()
            let ri = screenRadius(inner, size), ro = screenRadius(outer, size)
            if ro > ri {
                var ring = Path()
                ring.addEllipse(in: CGRect(x: center.x - ro, y: center.y - ro, width: ro * 2, height: ro * 2))
                ring.addEllipse(in: CGRect(x: center.x - ri, y: center.y - ri, width: ri * 2, height: ri * 2))
                context.fill(ring, with: .color(Color.green.opacity(0.10)), style: FillStyle(eoFill: true))
            }
        }

        // Orbits.
        for item in placed {
            let r = screenRadius(item.a, size)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(selected?.id == item.planet.id ? 0.45 : 0.16)), lineWidth: 1)
        }

        // Host star(s). For multiple-star systems, render the primary plus
        // companions clustered at the centre (we don't have their separations).
        let starColor = temperatureColor(system.stellarTempK)
        let starR = CGFloat(min(26, 12 + (system.stellarRadiusSun ?? 1) * 4))
        let companions = max(0, system.starCount - 1)
        let centers: [(CGPoint, CGFloat)] = {
            guard companions > 0 else { return [(center, starR)] }
            var out: [(CGPoint, CGFloat)] = []
            let sep = starR * 1.4
            for k in 0..<system.starCount {
                let a = Double(k) / Double(system.starCount) * 2 * .pi + time * 0.2
                let off = k == 0 ? 0 : sep
                out.append((CGPoint(x: center.x + CGFloat(cos(a)) * off,
                                    y: center.y + CGFloat(sin(a)) * off),
                            k == 0 ? starR : starR * 0.7))
            }
            return out
        }()
        context.drawLayer { l in
            l.blendMode = .plusLighter
            for (c, rr) in centers {
                l.fill(Path(ellipseIn: CGRect(x: c.x - rr * 2.4, y: c.y - rr * 2.4, width: rr * 4.8, height: rr * 4.8)),
                       with: .radialGradient(Gradient(colors: [starColor.opacity(0.5), .clear]), center: c, startRadius: 0, endRadius: rr * 2.4))
                l.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(starColor))
            }
        }

        // Planets.
        let minPeriod = placed.compactMap { $0.planet.periodDays }.min() ?? 1
        for item in placed {
            let r = screenRadius(item.a, size)
            let period = item.planet.periodDays ?? (item.a * 365.25)   // fallback
            let omega = time * (2 * .pi / 6) * (minPeriod / max(period, 0.01))
            let angle = item.phase + omega
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * CGFloat(r),
                            y: center.y + CGFloat(sin(angle)) * CGFloat(r))
            let pr = planetRadius(item.planet)
            let color = planetColor(item.planet)
            let isSelected = selected?.id == item.planet.id
            if isSelected {
                context.stroke(Path(ellipseIn: CGRect(x: p.x - pr - 4, y: p.y - pr - 4, width: pr * 2 + 8, height: pr * 2 + 8)),
                               with: .color(.white), lineWidth: 1.5)
            }
            context.fill(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                         with: .color(color))

            // Moons orbiting the selected planet.
            if isSelected, !item.planet.moons.isEmpty {
                drawMoons(item.planet, around: p, planetRadius: pr, in: context, time: time)
            }

            // Always-on name label, nudged outward from the centre.
            let dir = CGVector(dx: p.x - center.x, dy: p.y - center.y)
            let len = max(1, hypot(dir.dx, dir.dy))
            let lp = CGPoint(x: p.x + dir.dx / len * (pr + 6), y: p.y + dir.dy / len * (pr + 6))
            let text = Text(item.planet.name)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.6))
            context.draw(text, at: lp, anchor: dir.dx >= 0 ? .leading : .trailing)
        }
    }

    /// Render a selected planet's moons on small circular orbits around it.
    private func drawMoons(_ planet: Exoplanet, around p: CGPoint, planetRadius pr: CGFloat,
                           in context: GraphicsContext, time: Double) {
        let moons = planet.moons
        let aMax = moons.map(\.semiMajorAxisKm).max() ?? 1
        let aMin = moons.map(\.semiMajorAxisKm).min() ?? 1
        let inner = Double(pr) + 8, outer = Double(pr) + 8 + 26
        func moonR(_ a: Double) -> Double {
            guard aMax > aMin else { return (inner + outer) / 2 }
            let f = (log(a) - log(aMin)) / (log(aMax) - log(aMin))
            return inner + f * (outer - inner)
        }
        let minPeriod = moons.map(\.periodDays).min() ?? 1
        for (k, moon) in moons.enumerated() {
            let r = moonR(moon.semiMajorAxisKm)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            let omega = time * 1.2 * (minPeriod / max(moon.periodDays, 0.01))
            let a = Double(k) * 1.1 + omega
            let mp = CGPoint(x: p.x + CGFloat(cos(a)) * CGFloat(r), y: p.y + CGFloat(sin(a)) * CGFloat(r))
            context.fill(Path(ellipseIn: CGRect(x: mp.x - 2, y: mp.y - 2, width: 4, height: 4)),
                         with: .color(.white.opacity(0.85)))
        }
    }

    private func planetRadius(_ planet: Exoplanet) -> CGFloat {
        let earth = planet.radiusEarth ?? (planet.massEarth.map { pow($0, 0.27) } ?? 2)
        return CGFloat(min(15, max(3, 3 + 4 * log10(earth + 1))))
    }

    private func planetColor(_ planet: Exoplanet) -> Color {
        switch planet.kind {
        case .rocky: return Color(red: 0.80, green: 0.72, blue: 0.62)
        case .neptunian: return Color(red: 0.45, green: 0.75, blue: 0.95)
        case .giant: return Color(red: 0.92, green: 0.74, blue: 0.50)
        case .unknown: return Color(white: 0.7)
        }
    }

    private func temperatureColor(_ tempK: Double?) -> Color {
        guard let t = tempK else { return Color(red: 1.0, green: 0.92, blue: 0.7) }
        switch t {
        case ..<3700: return Color(red: 1.0, green: 0.72, blue: 0.5)
        case ..<5200: return Color(red: 1.0, green: 0.85, blue: 0.6)
        case ..<6000: return Color(red: 1.0, green: 0.96, blue: 0.85)
        case ..<7500: return .white
        default: return Color(red: 0.78, green: 0.86, blue: 1.0)
        }
    }

    private func togglePlay() {
        let now = Date.timeIntervalSinceReferenceDate
        if animate {
            accumulated += now - playStart   // bank elapsed time, freeze in place
        } else {
            playStart = now                  // resume from where we paused
        }
        animate.toggle()
    }

    // MARK: Selection

    private func select(at location: CGPoint, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dist = hypot(location.x - center.x, location.y - center.y)
        var best: (d: Double, planet: Exoplanet)?
        for item in placed {
            let d = abs(Double(dist) - screenRadius(item.a, size))
            if d < 26, best == nil || d < best!.d { best = (d, item.planet) }
        }
        selected = best?.planet
    }

    // MARK: Overlay

    private func overlay(size: CGSize, safe insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CircleIconButton(label: "Back", systemImage: "chevron.left") { dismiss() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(system.hostName).font(.headline).foregroundStyle(.white)
                    Text(systemSubtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                CircleIconButton(label: animate ? "Pause" : "Play",
                                 systemImage: animate ? "pause.fill" : "play.fill") { togglePlay() }
            }
            .padding(.horizontal).padding(.top, insets.top + 4)

            Spacer()

            if let selected {
                planetCard(selected)
            } else if !placed.isEmpty {
                Text("Tap an orbit to inspect a planet")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, insets.bottom + 10)
    }

    private var systemSubtitle: String {
        var parts: [String] = ["\(system.planets.count) planet\(system.planets.count == 1 ? "" : "s")"]
        if system.starCount > 1 { parts.append("\(system.starCount) stars") }
        if let s = system.spectralType { parts.append(s) }
        if let ly = system.distanceLightYears { parts.append(String(format: "%.0f ly", ly)) }
        return parts.joined(separator: " · ")
    }

    private func planetCard(_ planet: Exoplanet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(planet.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityLabel("Dismiss \(planet.name)")
            }
            .padding(.trailing, -10)   // pull the 44pt hit area back to the card edge
            let facts = [
                planet.radiusEarth.map { String(format: "%.1f R⊕", $0) },
                planet.massEarth.map { String(format: "%.1f M⊕", $0) },
                (system.semiMajorAxis(of: planet)).map { String(format: "%.3f AU", $0) },
                planet.periodDays.map { String(format: "%.1f d", $0) },
                planet.eccentricity.map { String(format: "e %.2f", $0) },
                planet.equilibriumTempK.map { String(format: "%.0f K", $0) },
            ].compactMap { $0 }.joined(separator: "  ·  ")
            Text(facts).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            Text(planet.summary(in: system))
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if !planet.moons.isEmpty {
                Label(planet.moons.map(\.name).joined(separator: ", "),
                      systemImage: "moon.circle")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }
            if let method = planet.method {
                Text("\(method)\(planet.year.map { ", \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
