import SwiftUI

/// A top-down orbital view of a planetary system: the host star, its planets on
/// log-AU orbits (sized/coloured by type), and the habitable zone. Tap an orbit to
/// inspect a planet; orbits animate at correct relative (Keplerian) speeds.
struct SystemView: View {
    let system: PlanetarySystem
    @Environment(\.dismiss) private var dismiss

    @State private var animate = true
    @State private var selected: Exoplanet?

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
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, _ in
                            draw(in: context, size: size, time: animate ? t : 0)
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { select(at: $0.location, size: size) })
                }

                overlay(size: size)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
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

        // Host star.
        let starColor = temperatureColor(system.stellarTempK)
        let starR = CGFloat(min(26, 12 + (system.stellarRadiusSun ?? 1) * 4))
        context.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: center.x - starR * 2.4, y: center.y - starR * 2.4, width: starR * 4.8, height: starR * 4.8)),
                   with: .radialGradient(Gradient(colors: [starColor.opacity(0.5), .clear]), center: center, startRadius: 0, endRadius: starR * 2.4))
            l.fill(Path(ellipseIn: CGRect(x: center.x - starR, y: center.y - starR, width: starR * 2, height: starR * 2)),
                   with: .color(starColor))
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
            if selected?.id == item.planet.id {
                context.stroke(Path(ellipseIn: CGRect(x: p.x - pr - 4, y: p.y - pr - 4, width: pr * 2 + 8, height: pr * 2 + 8)),
                               with: .color(.white), lineWidth: 1.5)
            }
            context.fill(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                         with: .color(color))
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

    private func overlay(size: CGSize) -> some View {
        let insets = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets) ?? .zero
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                CircleIconButton(label: "Back", systemImage: "chevron.left") { dismiss() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(system.hostName).font(.headline).foregroundStyle(.white)
                    Text(systemSubtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                CircleIconButton(label: animate ? "Pause" : "Play",
                                 systemImage: animate ? "pause.fill" : "play.fill") { animate.toggle() }
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
        if let s = system.spectralType { parts.append(s) }
        if let ly = system.distanceLightYears { parts.append(String(format: "%.0f ly", ly)) }
        return parts.joined(separator: " · ")
    }

    private func planetCard(_ planet: Exoplanet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(planet.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.white.opacity(0.5))
            }
            let facts = [
                planet.radiusEarth.map { String(format: "%.1f R⊕", $0) },
                planet.massEarth.map { String(format: "%.1f M⊕", $0) },
                (system.semiMajorAxis(of: planet)).map { String(format: "%.3f AU", $0) },
                planet.periodDays.map { String(format: "%.1f d", $0) },
                planet.eccentricity.map { String(format: "e %.2f", $0) },
                planet.equilibriumTempK.map { String(format: "%.0f K", $0) },
            ].compactMap { $0 }.joined(separator: "  ·  ")
            Text(facts).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
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
