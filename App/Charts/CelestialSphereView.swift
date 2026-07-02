import SwiftUI
import simd
import CelestialCore
import Astrology

// SwiftUI also declares `Angle`; here we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// A rotating 3D celestial sphere of a chart — the local sky as a luminous globe:
/// the real star field, the horizon ring, celestial equator, the ecliptic ringed
/// with the zodiac, the planets, and the aspect chords across the interior.
/// Auto-rotates; drag to turn, tap to pause. Inspired by Astrolog's globe.
///
/// Everything is computed in the **local horizon frame** (z = zenith, x = north,
/// y = east): a body's ecliptic longitude → equatorial → horizontal → a unit
/// vector, then rotated (yaw about the vertical, pitch from the drag) and drawn
/// orthographically. Geometry is built once per chart and cached; only the cheap
/// per-frame projection runs in the render loop.
struct CelestialSphereView: View {
    let chart: NatalChart
    var title: String
    var subtitle: String?
    var stars: [Star] = []
    var constellations: [Constellation] = []
    /// Debug-only: auto-start "tour" or "time" so the simulator can screenshot
    /// those overlays (the real toggles live behind a nav-bar menu).
    var debugMode: String? = nil

    @State private var geo: SphereGeometry?
    /// The chart the current geometry was built from — equals `chart` unless the
    /// time scrubber has shifted it. Readings/selection use this so they match
    /// what's drawn.
    @State private var activeChart: NatalChart?
    @State private var dragYaw = 0.0
    @State private var pitch = 18.0 * .pi / 180.0
    @GestureState private var live: (yaw: Double, pitch: Double) = (0, 0)
    // nil ⇒ auto-spinning; non-nil ⇒ frozen at this yaw (tap a planet or empty space).
    @State private var frozenYaw: Double? = nil
    @State private var selected: AstroBody?
    @State private var reading: Reading?
    private static let spinRate = 2 * Double.pi / 60   // one turn per minute

    @State private var showGuide = false
    // Guided tour: spotlight the Sun, Moon, Rising, and the tightest aspect in turn.
    @State private var tourActive = false
    @State private var tourIndex = 0
    // Time travel: shift the sky by ±hours and watch it wheel (diurnal motion).
    @State private var showTime = false
    @State private var timeOffsetHours = 0.0
    @State private var playingTime = false
    // Bumped on every interaction; resets the idle countdown that auto-starts the tour.
    @State private var interactionTick = 0
    // Export (F13): a full-rotation GIF / MP4.
    @State private var showExportDialog = false
    @State private var exporting = false
    @State private var renderProgress = 0.0
    @State private var shareItem: ShareItem?
    @State private var exportMessage: String?

    private var rebuildKey: String {
        // Quantise the time offset to ~3-minute steps so scrubbing rebuilds the
        // geometry smoothly without thrashing.
        let q = (timeOffsetHours * 20).rounded() / 20
        return "\(chart.julianDay.value)|\(chart.location.latitude.degrees)|\(chart.location.longitude.degrees)|\(stars.count)|\(constellations.count)|\(q)"
    }

    /// The chart shifted by the current time offset (the live chart while scrubbing).
    private var effectiveChart: NatalChart {
        guard timeOffsetHours != 0 else { return chart }
        return NatalChart(at: JulianDay(chart.julianDay.value + timeOffsetHours / 24.0),
                          location: chart.location, settings: chart.settings)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.black.ignoresSafeArea()
                if let geo {
                    TimelineView(.animation(paused: frozenYaw != nil && !tourActive)) { tl in
                        // The camera spins gently unless frozen (a tap) or while
                        // time-travelling (then the *sky* moves, so the camera holds).
                        let spinning = frozenYaw == nil && !playingTime
                        let base = frozenYaw ?? (spinning ? tl.date.timeIntervalSinceReferenceDate * Self.spinRate + dragYaw : dragYaw)
                        let yaw = base + live.yaw
                        let p = clampPitch(pitch + live.pitch)
                        Canvas { ctx, sz in
                            geo.draw(in: ctx, size: sz, yaw: yaw, pitch: p,
                                     highlight: highlightSet, phase: tl.date.timeIntervalSinceReferenceDate)
                        }
                    }
                }
                footer
                if tourActive {
                    tourCaption
                } else if let selected, let pos = (activeChart ?? chart).position(of: selected) {
                    selectionCard(selected, pos)
                }
                if showTime { timeScrubber }
                if exporting { exportOverlay }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($live) { v, state, _ in
                        state = (v.translation.width * 0.01, -v.translation.height * 0.01)
                    }
                    .onEnded { v in
                        if frozenYaw != nil { frozenYaw! += v.translation.width * 0.01 }
                        else { dragYaw += v.translation.width * 0.01 }
                        pitch = clampPitch(pitch - v.translation.height * 0.01)
                        if tourActive { withAnimation { tourActive = false } }
                        interactionTick += 1
                    }
            )
            .simultaneousGesture(SpatialTapGesture().onEnded { handleTap(at: $0.location, size: size) })
            .frame(width: size.width, height: size.height)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("What am I seeing?", systemImage: "questionmark.circle") { showGuide = true }
                    .tint(AppScreen.astrology.tint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation { toggleTour() }
                    } label: {
                        Label(tourActive ? "Stop tour" : "Guided tour",
                              systemImage: tourActive ? "stop.circle" : "play.circle")
                    }
                    Button {
                        withAnimation { toggleTime() }
                    } label: {
                        Label(showTime ? "Hide time travel" : "Time travel",
                              systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    Button("Export rotation…", systemImage: "square.and.arrow.up") { showExportDialog = true }
                        .disabled(geo == nil || exporting)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(AppScreen.astrology.tint)
            }
        }
        .sheet(isPresented: $showGuide) {
            SphereGuideSheet(chart: chart)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: AppScreen.astrology.tint) }
        .confirmationDialog("Export a full rotation", isPresented: $showExportDialog, titleVisibility: .visible) {
            ForEach(SphereExportFormat.allCases) { format in
                Button(format.title) { export(format) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Render one slow turn of the sphere.")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]).presentationDetents([.medium, .large])
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil },
                                              set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
        .task(id: rebuildKey) {
            let c = effectiveChart
            activeChart = c
            geo = SphereGeometry(chart: c, stars: stars, constellations: constellations)
        }
        .task(id: tourActive) { await runTour() }
        .task(id: playingTime) { await runTimePlay() }
        .task {
            if debugMode == "tour" { tourActive = true }
            if debugMode == "time" { showTime = true; timeOffsetHours = 6 }
        }
        .task(id: interactionTick) { await runIdleTour() }
    }

    /// After a spell of no interaction, gently begin the guided tour on its own.
    private func runIdleTour() async {
        guard debugMode == nil, !tourActive, !showTime, selected == nil, !exporting else { return }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, !tourActive, !showTime, selected == nil, !exporting else { return }
        withAnimation(.easeInOut(duration: 0.6)) { tourIndex = 0; tourActive = true }
    }

    // MARK: Guided tour & time travel

    /// One auto-advancing pass through the tour steps while `tourActive`.
    private func runTour() async {
        guard tourActive else { return }
        while !Task.isCancelled && tourActive {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled || !tourActive { break }
            withAnimation(.easeInOut(duration: 0.5)) {
                tourIndex = (tourIndex + 1) % max(1, tourSteps.count)
            }
        }
    }

    /// Advance the time offset smoothly while `playingTime` (≈ a day every ~30s).
    private func runTimePlay() async {
        guard playingTime else { return }
        while !Task.isCancelled && playingTime {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled || !playingTime { break }
            timeOffsetHours += 0.1
            if timeOffsetHours > 24 { timeOffsetHours = -24 }   // loop the day
        }
    }

    private func toggleTour() {
        interactionTick += 1
        tourActive.toggle()
        if tourActive {
            tourIndex = 0
            selected = nil
            showTime = false; playingTime = false; timeOffsetHours = 0
        }
    }

    private func toggleTime() {
        interactionTick += 1
        showTime.toggle()
        if showTime {
            tourActive = false; selected = nil; frozenYaw = nil
        } else {
            playingTime = false
            withAnimation { timeOffsetHours = 0 }
        }
    }

    /// The bodies to spotlight + the caption for the current tour step.
    private var tourSteps: [(highlight: Set<AstroBody>, caption: String)] {
        let c = activeChart ?? chart
        var steps: [(Set<AstroBody>, String)] = []
        if let sun = c.position(of: .sun) {
            steps.append(([.sun], "Your Sun in \(sun.position.sign.name) — your core identity and vitality, the steady centre of who you are."))
        }
        if let moon = c.position(of: .moon) {
            steps.append(([.moon], "Your Moon in \(moon.position.sign.name) — your inner emotional world and what you need to feel safe."))
        }
        let asc = ZodiacSign(longitude: c.angles.ascendant)
        steps.append(([], "\(asc.name) rising — the face you meet the world with, climbing the eastern horizon at AC."))
        if let t = geo?.tightestAspect, let arc = geo?.aspects[t] {
            steps.append(([arc.bodyA, arc.bodyB],
                "Your tightest aspect: \(arc.bodyA.name) \(arc.kind.name.lowercased()) \(arc.bodyB.name) — \(aspectFlavour(arc.kind))"))
        }
        return steps
    }

    private func aspectFlavour(_ k: AspectKind) -> String {
        switch k {
        case .trine, .sextile: "two parts of you that work together with natural ease."
        case .square, .opposition: "a charged tension between two drives that pushes you to grow."
        case .conjunction: "two energies fused into a single, concentrated force."
        default: "a subtle, ongoing conversation between two parts of you."
        }
    }

    /// The bodies currently spotlit (selection + the active tour step).
    private var highlightSet: Set<AstroBody> {
        var s: Set<AstroBody> = []
        if let selected { s.insert(selected) }
        if tourActive, !tourSteps.isEmpty {
            s.formUnion(tourSteps[min(tourIndex, tourSteps.count - 1)].highlight)
        }
        return s
    }

    // MARK: Export (F13)

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: renderProgress)
                    .progressViewStyle(.linear)
                    .tint(AppScreen.astrology.tint)
                    .frame(width: 180)
                Text(renderProgress < 1 ? "Rendering rotation…" : "Encoding…")
                    .font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            .padding(24)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        }
        .transition(.opacity)
    }

    private func export(_ format: SphereExportFormat) {
        guard let geo else { return }
        let pitchNow = clampPitch(pitch + live.pitch)
        // One graceful ~5-second turn. A star-field GIF compresses poorly, so it
        // gets fewer, smaller frames; the video stays full-res and smooth.
        let plan = format.renderPlan
        exporting = true
        renderProgress = 0
        Task {
            let frames = await renderRotationFrames(geo: geo, pitch: pitchNow, plan: plan)
            let result = await SphereExport.make(format, frames: frames, fps: plan.fps, title: title)
            exporting = false
            switch result {
            case .shareFile(let url): shareItem = ShareItem(url: url)
            case .failure(let message): exportMessage = message
            }
        }
    }

    /// Render one full turn as CGImages via `ImageRenderer`. Runs on the main actor
    /// (ImageRenderer requires it) but yields between frames so the progress bar
    /// animates and taps stay responsive.
    @MainActor
    private func renderRotationFrames(geo: SphereGeometry, pitch: Double,
                                      plan: SphereRenderPlan) async -> [CGImage] {
        var images: [CGImage] = []
        images.reserveCapacity(plan.count)
        for i in 0..<plan.count {
            let yaw = 2 * Double.pi * Double(i) / Double(plan.count)
            let renderer = ImageRenderer(content: SphereFrame(geo: geo, yaw: yaw, pitch: pitch, dimension: plan.dimension))
            renderer.scale = plan.scale
            if let image = renderer.cgImage { images.append(image) }
            renderProgress = Double(i + 1) / Double(plan.count)
            await Task.yield()
        }
        return images
    }

    private func clampPitch(_ p: Double) -> Double { max(-(.pi / 2 - 0.05), min(.pi / 2 - 0.05, p)) }

    // MARK: Tap-to-identify

    /// Tap a planet to freeze the globe and read it; tap an aspect chord to read it;
    /// tap empty space to pause/resume.
    private func handleTap(at location: CGPoint, size: CGSize) {
        guard let geo else { return }
        interactionTick += 1
        if tourActive { withAnimation { toggleTour() }; return }
        let spinning = frozenYaw == nil && !playingTime
        let yaw = frozenYaw ?? (spinning ? Date().timeIntervalSinceReferenceDate * Self.spinRate + dragYaw : dragYaw)
        let p = clampPitch(pitch)
        if let body = geo.hitTestPlanet(at: location, yaw: yaw, pitch: p, size: size) {
            withAnimation(.easeOut(duration: 0.2)) {
                frozenYaw = yaw       // freeze exactly where it was tapped
                selected = body
            }
        } else if let arc = geo.hitTestAspect(at: location, yaw: yaw, pitch: p, size: size) {
            frozenYaw = yaw
            reading = Reading(title: "\(arc.bodyA.name) \(arc.kind.name) \(arc.bodyB.name)",
                              body: Interpretation.aspect(arc.kind, arc.bodyA, arc.bodyB))
        } else if frozenYaw != nil {
            // Resume spinning without a visual jump: fold the frozen offset into dragYaw.
            dragYaw = frozenYaw! - Date().timeIntervalSinceReferenceDate * Self.spinRate
            withAnimation(.easeOut(duration: 0.2)) {
                frozenYaw = nil
                selected = nil
            }
        } else {
            frozenYaw = yaw           // freeze in place
        }
    }

    private func selectionCard(_ body: AstroBody, _ pos: BodyPosition) -> some View {
        let color = SphereGeometry.planetColor(body)
        let house = (activeChart ?? chart).houses.house(of: pos.longitude)
        return VStack {
            Spacer()
            Button { reading = sphereReading(body, pos) } label: {
                HStack(spacing: 12) {
                    Text(body.glyph).font(.title2).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(body.name).font(.headline).foregroundStyle(.white)
                            if pos.isRetrograde {
                                Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                            }
                        }
                        Text("\(pos.position.sign.name) · \(pos.position.description) · House \(house)")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.white.opacity(0.5))
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 54)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func sphereReading(_ body: AstroBody, _ pos: BodyPosition) -> Reading {
        let c = activeChart ?? chart
        let house = c.houses.house(of: pos.longitude)
        let dignity = Dignities.dignity(of: body, in: pos.position.sign)
        let asp: [(kind: AspectKind, other: AstroBody)] = c.aspects.compactMap {
            if $0.bodyA == body { return ($0.kind, $0.bodyB) }
            if $0.bodyB == body { return ($0.kind, $0.bodyA) }
            return nil
        }
        return Reading(title: "\(body.name) in \(pos.position.sign.name)",
                       sections: Interpretation.planetReading(body, sign: pos.position.sign,
                                                              house: house, dignity: dignity,
                                                              retrograde: pos.isRetrograde, aspects: asp))
    }

    // MARK: Tour caption & time scrubber

    private var tourCaption: some View {
        let step = tourSteps.isEmpty ? nil : tourSteps[min(tourIndex, tourSteps.count - 1)]
        return VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption)
                    Text("GUIDED TOUR").font(.caption2.weight(.bold)).tracking(1.4)
                    Spacer()
                    Button { withAnimation { toggleTour() } } label: {
                        Image(systemName: "xmark.circle.fill").font(.body)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(AppScreen.astrology.tint)
                Text(step?.caption ?? "")
                    .font(.callout).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(tourIndex)   // cross-fade as the step changes
                    .transition(.opacity)
                if tourSteps.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<tourSteps.count, id: \.self) { i in
                            Circle().fill(.white.opacity(i == tourIndex ? 0.9 : 0.25))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppScreen.astrology.tint.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 54)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var timeScrubber: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Text(timeLabel)
                        .font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.white)
                    Spacer()
                    Button { withAnimation { timeOffsetHours = 0 } } label: {
                        Text("Now").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(AppScreen.astrology.tint)
                    .disabled(timeOffsetHours == 0)
                }
                HStack(spacing: 12) {
                    Button { playingTime.toggle() } label: {
                        Image(systemName: playingTime ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain).foregroundStyle(AppScreen.astrology.tint)
                    Slider(value: $timeOffsetHours, in: -24...24)
                        .tint(AppScreen.astrology.tint)
                }
                Text("Drag to move the sky ±24 h, or play to watch it wheel.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppScreen.astrology.tint.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 54)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The effective time as a readable label (offset relative to the chart moment).
    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: (effectiveChart.julianDay.value - 2440587.5) * 86400)
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM HH:mm 'UTC'"
        df.timeZone = .gmt
        let h = timeOffsetHours
        let sign = h > 0 ? "+" : (h < 0 ? "−" : "")
        let mag = abs(h)
        let off = h == 0 ? "now" : String(format: "%@%.1f h", sign, mag)
        return "\(df.string(from: date))  (\(off))"
    }

    private var footer: some View {
        VStack {
            Spacer()
            Text(subtitle ?? geo?.defaultSubtitle ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 12)
                .opacity(showTime || tourActive ? 0 : 1)
        }
    }
}

extension CelestialSphereView {
    /// Runs the real frame-render + encode path for a chart, for simulator
    /// verification of the export pipeline (see `SphereSnapshotHarness.runExportTest`).
    @MainActor
    static func debugExport(_ format: SphereExportFormat, chart: NatalChart) async -> SphereExportResult {
        let geo = SphereGeometry(chart: chart, stars: [], constellations: [])
        let plan = format.renderPlan
        var frames: [CGImage] = []
        for i in 0..<plan.count {
            let yaw = 2 * Double.pi * Double(i) / Double(plan.count)
            let renderer = ImageRenderer(content: SphereFrame(geo: geo, yaw: yaw, pitch: 0.3, dimension: plan.dimension))
            renderer.scale = plan.scale
            if let image = renderer.cgImage { frames.append(image) }
        }
        return await SphereExport.make(format, frames: frames, fps: plan.fps, title: "DebugTest")
    }
}

/// Explains the sphere: a colour-keyed legend of every element, then a tappable
/// list of the chart's placements (→ a full reading). Turns the mesmerizing-but-
/// opaque globe into something you can actually read.
struct SphereGuideSheet: View {
    let chart: NatalChart
    @Environment(\.dismiss) private var dismiss
    @State private var reading: Reading?
    private let tint = AppScreen.astrology.tint

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    legendSection
                    placementsSection
                }
                .padding(20)
            }
            .background(Theme.spaceGradient.ignoresSafeArea())
            .navigationTitle("Reading the sphere")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(tint)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
    }

    private var intro: some View {
        Text("This is your sky as a globe — the real stars, the zodiac belt, and your planets, seen from your exact place and moment. Drag to turn it; tap a planet to read it, or tap empty space to pause.")
            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Legend

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("What you're seeing")
            ring("Horizon", colors: [.white.opacity(0.5)],
                 "The edge of your sky, with N E S W. Anything above it was up; below it had set.")
            dot("Zenith (Z)", colors: [.yellow],
                "The point straight overhead at your moment of birth.")
            ring("Ecliptic", colors: [SphereGeometry.planetColor(.sun)],
                 "The Sun's path through the year. The twelve zodiac signs are measured along this gold band.")
            glyphRow("Zodiac signs", ZodiacSign.aries.glyph + ZodiacSign.taurus.glyph + ZodiacSign.gemini.glyph,
                     "Each sign spans 30° of the ecliptic — the belt the planets travel through.")
            ring("Celestial equator", colors: [.white.opacity(0.7)],
                 "Earth's equator projected onto the sky.")
            ring("House circles", colors: [.white.opacity(0.3)],
                 "Faint great circles dividing the sky into the twelve houses — areas of life.")
            glyphRow("AC / MC", "AC", "Ascendant (eastern horizon) and Midheaven (highest point) — your chart's angles.", tinted: true)
            dot("Planets", colors: [SphereGeometry.planetColor(.mars), SphereGeometry.planetColor(.venus), SphereGeometry.planetColor(.jupiter)],
                "Each glowing glyph is a planet at its true position, colour-coded so you can tell them apart.")
            dot("Aspects", colors: [SphereGeometry.aspectColor(.trine), SphereGeometry.aspectColor(.square), .white, SphereGeometry.aspectColor(.quincunx)],
                "Lines between planets: blue = flowing (trine/sextile), red = tense (square/opposition), white = conjunction, purple = minor.")
            dot("Stars & figures", colors: [SphereGeometry.starColor(-0.2), SphereGeometry.starColor(1.2)],
                "Real catalogue stars (coloured by temperature) with faint constellation figures behind everything.")
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func ring(_ title: String, colors: [Color], _ text: String) -> some View {
        legendRow(title, text) {
            Circle().strokeBorder(colors[0], lineWidth: 2).frame(width: 22, height: 22)
        }
    }

    private func dot(_ title: String, colors: [Color], _ text: String) -> some View {
        legendRow(title, text) {
            HStack(spacing: 3) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 8, height: 8)
                }
            }
            .frame(width: 22)
        }
    }

    private func glyphRow(_ title: String, _ glyph: String, _ text: String, tinted: Bool = false) -> some View {
        legendRow(title, text) {
            Text(glyph).font(.system(size: 13, weight: tinted ? .bold : .regular))
                .foregroundStyle(tinted ? tint : .white.opacity(0.85))
                .frame(width: 22)
        }
    }

    private func legendRow<Icon: View>(_ title: String, _ text: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon().padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: Placements

    private var placementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Your placements")
            Text("Tap any planet to read what it means here.")
                .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.bottom, 6)
            ForEach(chart.positions, id: \.body) { p in
                Button { reading = placementReading(p) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(SphereGeometry.planetColor(p.body)).frame(width: 9, height: 9)
                        Text(p.body.glyph).font(.system(size: 16)).foregroundStyle(.white).frame(width: 22)
                        Text(p.body.name).font(.subheadline).foregroundStyle(.white)
                        if p.isRetrograde {
                            Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(p.position.description)
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                        Text(ChartDetailView.roman(chart.houses.house(of: p.longitude)))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                            .frame(width: 30, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Divider().overlay(.white.opacity(0.08))
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func placementReading(_ p: BodyPosition) -> Reading {
        let house = chart.houses.house(of: p.longitude)
        let dignity = Dignities.dignity(of: p.body, in: p.position.sign)
        let aspects: [(kind: AspectKind, other: AstroBody)] = chart.aspects.compactMap { a in
            if a.bodyA == p.body { return (a.kind, a.bodyB) }
            if a.bodyB == p.body { return (a.kind, a.bodyA) }
            return nil
        }
        return Reading(title: "\(p.body.name) in \(p.position.sign.name)",
                       sections: Interpretation.planetReading(p.body, sign: p.position.sign, house: house,
                                                              dignity: dignity, retrograde: p.isRetrograde,
                                                              aspects: aspects))
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(.white.opacity(0.45)).padding(.bottom, 8)
    }
}

/// One still of the sphere at a fixed yaw/pitch — rasterized by `ImageRenderer`
/// for the rotation export.
private struct SphereFrame: View {
    let geo: SphereGeometry
    let yaw: Double
    let pitch: Double
    let dimension: CGFloat

    var body: some View {
        ZStack {
            Color.black
            Canvas { ctx, sz in geo.draw(in: ctx, size: sz, yaw: yaw, pitch: pitch) }
        }
        .frame(width: dimension, height: dimension)
    }
}

/// Precomputed sphere geometry (horizon-frame base vectors). Built once per chart;
/// rotation/projection happen per frame in `draw`.
private struct SphereGeometry {
    struct StarDot { let v: SIMD3<Double>; let color: Color; let size: Double; let alpha: Double; let spike: Double }
    struct Planet { let v: SIMD3<Double>; let body: AstroBody; let retro: Bool }
    struct AspectArc {
        let a: SIMD3<Double>; let b: SIMD3<Double>
        let kind: AspectKind; let bodyA: AstroBody; let bodyB: AstroBody; let orb: Double
    }

    let horizon: [SIMD3<Double>]
    let equator: [SIMD3<Double>]
    let ecliptic: [SIMD3<Double>]
    let meridian: [SIMD3<Double>]
    let cuspTicks: [SIMD3<Double>]
    let houseCircles: [(points: [SIMD3<Double>], isAngle: Bool)]
    let houseNumbers: [(v: SIMD3<Double>, label: String)]
    let zodiac: [(v: SIMD3<Double>, glyph: String)]
    let constellationSegments: [(a: SIMD3<Double>, b: SIMD3<Double>)]
    let milkyWay: [(v: SIMD3<Double>, glow: Double)]
    let starField: [StarDot]
    let planets: [Planet]
    let aspects: [AspectArc]
    /// Index (into `aspects`) of the single tightest aspect — pulsed in the draw.
    let tightestAspect: Int?
    let cardinals: [(v: SIMD3<Double>, label: String)]
    let zenith: SIMD3<Double>
    let ascendant: SIMD3<Double>
    let midheaven: SIMD3<Double>
    let defaultSubtitle: String

    init(chart: NatalChart, stars: [Star], constellations: [Constellation] = []) {
        let ob = chart.angles.obliquity
        let ramc = chart.angles.ramc
        let loc = chart.location

        func vec(eclipticLon lon: Angle, lat: Angle = .zero) -> SIMD3<Double> {
            let eq = CoordinateTransform.equatorial(
                fromEcliptic: EclipticCoordinates(longitude: lon, latitude: lat), obliquity: ob)
            let h = CoordinateTransform.horizontal(eq, at: loc, localSiderealTime: ramc)
            return SphereGeometry.unit(altitude: h.altitude, azimuth: h.azimuth)
        }
        func vecEquatorial(_ eq: EquatorialCoordinates) -> SIMD3<Double> {
            let h = CoordinateTransform.horizontal(eq, at: loc, localSiderealTime: ramc)
            return SphereGeometry.unit(altitude: h.altitude, azimuth: h.azimuth)
        }

        let step = 2.0
        horizon = stride(from: 0.0, through: 360.0, by: step).map {
            SphereGeometry.unit(altitude: .zero, azimuth: .degrees($0))
        }
        equator = stride(from: 0.0, through: 360.0, by: step).map {
            vecEquatorial(EquatorialCoordinates(rightAscension: .degrees($0), declination: .zero))
        }
        ecliptic = stride(from: 0.0, through: 360.0, by: step).map { vec(eclipticLon: .degrees($0)) }
        meridian = stride(from: 0.0, through: 360.0, by: step).map {
            SIMD3(cos(Angle.degrees($0).radians), 0, sin(Angle.degrees($0).radians))
        }

        zodiac = ZodiacSign.allCases.map {
            (vec(eclipticLon: .degrees(Double($0.rawValue) * 30 + 15)), $0.glyph)
        }
        cuspTicks = (1...12).map { vec(eclipticLon: chart.houses.cusp($0)) }

        // House great-circles: the meridian of each cusp's ecliptic longitude
        // (a full circle through the ecliptic poles), segmenting the globe like
        // orange slices. Angular cusps (1/4/7/10) are drawn brighter.
        houseCircles = (1...12).map { i in
            let L = chart.houses.cusp(i).degrees
            let pts = stride(from: 0.0, through: 360.0, by: 6.0).map { φ -> SIMD3<Double> in
                let lon = φ <= 180 ? L : L + 180
                let lat = φ <= 180 ? -90 + φ : 90 - (φ - 180)
                return vec(eclipticLon: .degrees(lon), lat: .degrees(lat))
            }
            return (pts, i == 1 || i == 4 || i == 7 || i == 10)
        }

        // House numerals, placed at each house's mid-longitude on the ecliptic,
        // nudged just inside (negative ecliptic latitude) so they don't collide
        // with the zodiac glyphs sitting on the band.
        houseNumbers = (1...12).map { i in
            let a = chart.houses.cusp(i).degrees
            var span = chart.houses.cusp(i % 12 + 1).degrees - a
            if span <= 0 { span += 360 }
            let mid = a + span / 2
            return (vec(eclipticLon: .degrees(mid), lat: .degrees(-7)), ChartDetailView.roman(i))
        }

        // Real star field: brightest first, capped for a clean, fast render.
        let bright = stars.sorted { $0.apparentMagnitude < $1.apparentMagnitude }.prefix(900)
        starField = bright.map { s in
            let m = s.apparentMagnitude
            return StarDot(v: vecEquatorial(s.equatorial),
                           color: SphereGeometry.starColor(s.colorIndex),
                           size: max(0.5, 2.3 - 0.34 * m),
                           alpha: max(0.18, min(1.0, 1.15 - 0.16 * m)),
                           // Diffraction-spike sparkle for the few brightest stars.
                           spike: m < 1.6 ? (8.0 - 3.0 * m) : 0)
        }

        // Constellation stick-figures (RA/Dec polylines) → horizon-frame segments.
        var segs: [(a: SIMD3<Double>, b: SIMD3<Double>)] = []
        for c in constellations {
            for line in c.polylines where line.count > 1 {
                let pts = line.map { vecEquatorial(EquatorialCoordinates(
                    rightAscension: .degrees($0.x), declination: .degrees($0.y))) }
                for i in 0..<(pts.count - 1) { segs.append((pts[i], pts[i + 1])) }
            }
        }
        constellationSegments = segs

        // Planets at their true sky position — real ecliptic latitude, not flat on
        // the ecliptic (latitude is ayanamsa-invariant, so this is right for
        // tropical and sidereal charts alike).
        planets = chart.positions.map {
            Planet(v: vec(eclipticLon: $0.longitude,
                          lat: SphereGeometry.eclipticLatitude(of: $0.body, at: chart.julianDay)),
                   body: $0.body, retro: $0.isRetrograde)
        }

        // Milky Way: sample the galactic equator (±9° band) → equatorial → horizon
        // frame, brightest along the galactic midplane.
        var mw: [(SIMD3<Double>, Double)] = []
        for l in stride(from: 0.0, to: 360.0, by: 3.0) {
            for b in stride(from: -9.0, through: 9.0, by: 3.0) {
                let eq = SphereGeometry.galacticToEquatorial(l: l, b: b)
                let falloff = cos(b / 9.0 * .pi / 2)
                mw.append((vecEquatorial(eq), falloff * falloff))
            }
        }
        milkyWay = mw

        let posByBody = Dictionary(uniqueKeysWithValues: chart.positions.map { ($0.body, $0.longitude) })
        let arcs: [AspectArc] = chart.aspects.compactMap { asp in
            guard let la = posByBody[asp.bodyA], let lb = posByBody[asp.bodyB] else { return nil }
            return AspectArc(a: vec(eclipticLon: la), b: vec(eclipticLon: lb),
                             kind: asp.kind, bodyA: asp.bodyA, bodyB: asp.bodyB, orb: asp.orb)
        }
        aspects = arcs
        // The single tightest aspect (prefer a major one) — gently pulsed in the draw.
        tightestAspect = arcs.indices
            .filter { arcs[$0].kind.isMajor }.min { arcs[$0].orb < arcs[$1].orb }
            ?? arcs.indices.min { arcs[$0].orb < arcs[$1].orb }

        cardinals = [(0.0, "N"), (90, "E"), (180, "S"), (270, "W")].map {
            (SphereGeometry.unit(altitude: .zero, azimuth: .degrees($0.0)), $0.1)
        }

        zenith = SIMD3(0, 0, 1)
        ascendant = vec(eclipticLon: chart.angles.ascendant)
        midheaven = vec(eclipticLon: chart.angles.midheaven)

        let date = Date(timeIntervalSince1970: (chart.julianDay.value - 2440587.5) * 86400)
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM yyyy HH:mm 'UTC'"
        df.timeZone = .gmt
        defaultSubtitle = String(format: "%@   %.2f°, %.2f°",
                                 df.string(from: date), loc.latitude.degrees, loc.longitude.degrees)
    }

    /// True geocentric ecliptic latitude of a body, of date (0 for the Sun, the
    /// nodes, and Lilith, which lie on the ecliptic by definition).
    static func eclipticLatitude(of body: AstroBody, at jd: JulianDay) -> Angle {
        switch body {
        case .sun, .northNode, .southNode, .blackMoonLilith: return .zero
        case .moon: return Moon.geocentric(at: jd).ecliptic.latitude
        case .mercury: return Planets.eclipticCoordinates(.mercury, at: jd).latitude
        case .venus: return Planets.eclipticCoordinates(.venus, at: jd).latitude
        case .mars: return Planets.eclipticCoordinates(.mars, at: jd).latitude
        case .jupiter: return Planets.eclipticCoordinates(.jupiter, at: jd).latitude
        case .saturn: return Planets.eclipticCoordinates(.saturn, at: jd).latitude
        case .uranus: return Planets.eclipticCoordinates(.uranus, at: jd).latitude
        case .neptune: return Planets.eclipticCoordinates(.neptune, at: jd).latitude
        case .pluto: return Planets.eclipticCoordinates(.pluto, at: jd).latitude
        case .chiron: return MinorBodies.eclipticCoordinates(.chiron, at: jd).latitude
        case .ceres: return MinorBodies.eclipticCoordinates(.ceres, at: jd).latitude
        case .pallas: return MinorBodies.eclipticCoordinates(.pallas, at: jd).latitude
        case .juno: return MinorBodies.eclipticCoordinates(.juno, at: jd).latitude
        case .vesta: return MinorBodies.eclipticCoordinates(.vesta, at: jd).latitude
        }
    }

    /// Galactic (l, b) → equatorial RA/Dec (J2000), via the standard rotation
    /// matrix transpose. Used to trace the Milky Way's band across the sky.
    static func galacticToEquatorial(l: Double, b: Double) -> EquatorialCoordinates {
        let lr = l * .pi / 180, br = b * .pi / 180
        let g = SIMD3(cos(br) * cos(lr), cos(br) * sin(lr), sin(br))
        // Equatorial→galactic matrix rows (J2000); its transpose maps galactic→equatorial.
        let r0 = SIMD3(-0.0548755604, -0.8734370902, -0.4838350155)
        let r1 = SIMD3( 0.4941094279, -0.4448296300,  0.7469822445)
        let r2 = SIMD3(-0.8676661490, -0.1980763734,  0.4559837762)
        let ex = r0.x * g.x + r1.x * g.y + r2.x * g.z
        let ey = r0.y * g.x + r1.y * g.y + r2.y * g.z
        let ez = r0.z * g.x + r1.z * g.y + r2.z * g.z
        let ra = atan2(ey, ex) * 180 / .pi
        let dec = asin(max(-1, min(1, ez))) * 180 / .pi
        return EquatorialCoordinates(rightAscension: .degrees(ra), declination: .degrees(dec))
    }

    /// The nearest planet to a screen point at the given orientation, if within
    /// tap range and on the near hemisphere.
    func hitTestPlanet(at point: CGPoint, yaw: Double, pitch: Double, size: CGSize) -> AstroBody? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) / 2 - 22
        var best: (AstroBody, CGFloat)?
        for pl in planets {
            let (pt, depth) = project(pl.v, yaw: yaw, pitch: pitch, center: center, radius: radius)
            guard depth >= -0.15 else { continue }
            let d = hypot(pt.x - point.x, pt.y - point.y)
            if d < 32, best == nil || d < best!.1 { best = (pl.body, d) }
        }
        return best?.0
    }

    /// The nearest aspect chord to a screen point, if within tap range. Returns the
    /// underlying `AspectArc` so the caller can open its reading.
    func hitTestAspect(at point: CGPoint, yaw: Double, pitch: Double, size: CGSize) -> AspectArc? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) / 2 - 22
        var best: (AspectArc, CGFloat)?
        for arc in aspects {
            let (pa, da) = project(arc.a, yaw: yaw, pitch: pitch, center: center, radius: radius)
            let (pb, db) = project(arc.b, yaw: yaw, pitch: pitch, center: center, radius: radius)
            guard (da + db) / 2 >= -0.1 else { continue }   // chord mostly on the near side
            let d = SphereGeometry.distance(from: point, toSegment: pa, pb)
            if d < 14, best == nil || d < best!.1 { best = (arc, d) }
        }
        return best?.0
    }

    /// Shortest distance from a point to a line segment.
    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-6 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Horizon-frame unit vector: x = north, y = east, z = zenith.
    static func unit(altitude alt: Angle, azimuth az: Angle) -> SIMD3<Double> {
        SIMD3(cos(alt.radians) * cos(az.radians),
              cos(alt.radians) * sin(az.radians),
              sin(alt.radians))
    }

    static func aspectColor(_ k: AspectKind) -> Color {
        switch k {
        case .trine, .sextile: return Color(red: 0.4, green: 0.85, blue: 1.0)
        case .square, .opposition: return Color(red: 1.0, green: 0.4, blue: 0.45)
        case .conjunction: return .white
        default: return Color(red: 0.75, green: 0.6, blue: 1.0)
        }
    }

    static func starColor(_ bv: Double?) -> Color {
        guard let bv else { return .white }
        switch bv {
        case ..<0.0: return Color(red: 0.74, green: 0.82, blue: 1.0)
        case 0.0..<0.3: return Color(red: 0.92, green: 0.95, blue: 1.0)
        case 0.3..<0.6: return Color(red: 1.0, green: 0.98, blue: 0.92)
        case 0.6..<1.0: return Color(red: 1.0, green: 0.92, blue: 0.76)
        default: return Color(red: 1.0, green: 0.82, blue: 0.66)
        }
    }

    static func planetColor(_ b: AstroBody) -> Color {
        switch b {
        case .sun: return Color(red: 1.0, green: 0.85, blue: 0.4)
        case .moon: return Color(red: 0.86, green: 0.89, blue: 0.96)
        case .mercury: return Color(red: 0.82, green: 0.78, blue: 0.66)
        case .venus: return Color(red: 0.96, green: 0.92, blue: 0.72)
        case .mars: return Color(red: 0.97, green: 0.47, blue: 0.37)
        case .jupiter: return Color(red: 0.96, green: 0.78, blue: 0.55)
        case .saturn: return Color(red: 0.9, green: 0.85, blue: 0.6)
        case .uranus: return Color(red: 0.62, green: 0.92, blue: 0.95)
        case .neptune: return Color(red: 0.5, green: 0.66, blue: 1.0)
        case .pluto: return Color(red: 0.82, green: 0.58, blue: 0.5)
        case .northNode, .southNode: return Color(red: 0.72, green: 0.72, blue: 0.8)
        case .chiron: return Color(red: 0.6, green: 0.85, blue: 0.78)
        case .ceres, .pallas, .juno, .vesta: return Color(red: 0.62, green: 0.86, blue: 0.95)
        case .blackMoonLilith: return Color(red: 0.75, green: 0.6, blue: 0.85)
        }
    }

    // MARK: Rotation & projection

    private func project(_ v: SIMD3<Double>, yaw: Double, pitch: Double,
                         center: CGPoint, radius: Double) -> (CGPoint, Double) {
        let cyaw = cos(yaw), syaw = sin(yaw)
        let x1 = v.x * cyaw - v.y * syaw
        let y1 = v.x * syaw + v.y * cyaw
        let z1 = v.z
        let cp = cos(pitch), sp = sin(pitch)
        let y2 = y1 * cp - z1 * sp     // depth toward viewer
        let z2 = y1 * sp + z1 * cp     // screen vertical
        return (CGPoint(x: center.x + radius * x1, y: center.y - radius * z2), y2)
    }

    func draw(in ctx: GraphicsContext, size: CGSize, yaw: Double, pitch: Double,
              highlight: Set<AstroBody> = [], phase: Double = 0) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) / 2 - 22
        func p(_ v: SIMD3<Double>) -> (CGPoint, Double) {
            project(v, yaw: yaw, pitch: pitch, center: center, radius: radius)
        }
        let limb = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)

        // Globe volume + atmosphere rim.
        ctx.fill(Path(ellipseIn: limb),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.12),
                                      Color(red: 0.01, green: 0.01, blue: 0.04)]),
                    center: center, startRadius: 0, endRadius: radius))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.stroke(Path(ellipseIn: limb),
                         with: .color(Color(red: 0.4, green: 0.55, blue: 1.0).opacity(0.4)), lineWidth: 2.5)
        }
        ctx.stroke(Path(ellipseIn: limb), with: .color(.white.opacity(0.10)), lineWidth: 1)

        // The additive backdrop (Milky Way, constellations, stars) is drawn in two
        // depth passes around an opaque "globe body" veil, so the **near** hemisphere
        // occludes the far one instead of the far side shining through.
        func drawMilkyWay(front: Bool) {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                for m in milkyWay {
                    let (pt, depth) = p(m.v)
                    guard (depth >= 0) == front else { continue }
                    let a = m.glow * (front ? 0.11 : 0.05)
                    let r = 7.0
                    layer.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(Color(red: 0.82, green: 0.86, blue: 1.0).opacity(a)))
                }
            }
        }
        func drawConstellations(front: Bool) {
            for seg in constellationSegments {
                let (pa, da) = p(seg.a); let (pb, db) = p(seg.b)
                guard ((da + db) / 2 >= 0) == front else { continue }
                ctx.stroke(Path { $0.move(to: pa); $0.addLine(to: pb) },
                           with: .color(Color(red: 0.6, green: 0.7, blue: 1.0).opacity(front ? 0.16 : 0.06)),
                           lineWidth: 0.5)
            }
        }
        func drawStars(front: Bool) {
            for s in starField {
                let (pt, depth) = p(s.v)
                guard (depth >= 0) == front else { continue }
                let a = s.alpha * (front ? 1.0 : 1.0)   // far stars are revealed by the veil, not pre-dimmed
                let r = s.size * (front ? 1.0 : 0.8)
                if s.spike > 0, front {
                    let L = s.spike
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 1.2))
                        var path = Path()
                        path.move(to: CGPoint(x: pt.x - L, y: pt.y)); path.addLine(to: CGPoint(x: pt.x + L, y: pt.y))
                        path.move(to: CGPoint(x: pt.x, y: pt.y - L)); path.addLine(to: CGPoint(x: pt.x, y: pt.y + L))
                        layer.stroke(path, with: .color(s.color.opacity(a * 0.7)), lineWidth: 0.6)
                    }
                }
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(s.color.opacity(a)))
            }
        }

        // Far hemisphere first…
        drawMilkyWay(front: false); drawConstellations(front: false); drawStars(front: false)
        // …then the globe body, a translucent veil that suppresses the far side
        // (denser at the centre where the near surface faces us, thinner at the limb
        // so a faint rim of far-side light still bleeds through). This is the
        // depth-occlusion approximation in the additive painter's model.
        ctx.fill(Path(ellipseIn: limb),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.82),
                                      Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.35)]),
                    center: center, startRadius: 0, endRadius: radius))
        // …then the near hemisphere on top.
        drawMilkyWay(front: true); drawConstellations(front: true); drawStars(front: true)

        // House great-circles (faint; angular cusps a touch brighter).
        for hc in houseCircles {
            circle(hc.points, color: AppScreen.astrology.tint,
                   base: hc.isAngle ? 0.4 : 0.13, width: hc.isAngle ? 1.0 : 0.6, ctx: ctx, p: p)
        }

        // Great circles.
        circle(equator, color: .init(red: 0.45, green: 0.6, blue: 1.0), base: 0.45, ctx: ctx, p: p)
        circle(meridian, color: .gray, base: 0.28, ctx: ctx, p: p, dashed: true)
        circle(ecliptic, color: .init(red: 0.5, green: 1.0, blue: 0.6), base: 0.85, width: 1.5, glow: true, ctx: ctx, p: p)
        circle(horizon, color: .white, base: 0.7, width: 1.2, ctx: ctx, p: p)

        // Graduated horizon ticks every 10°, longer at the cardinals.
        for az in stride(from: 0.0, to: 360.0, by: 10.0) {
            let major = az.truncatingRemainder(dividingBy: 90) == 0
            let (a0, d0) = p(SphereGeometry.unit(altitude: .degrees(major ? -3 : -1.6), azimuth: .degrees(az)))
            let (a1, _) = p(SphereGeometry.unit(altitude: .degrees(major ? 3 : 1.6), azimuth: .degrees(az)))
            ctx.stroke(Path { $0.move(to: a0); $0.addLine(to: a1) },
                       with: .color(.white.opacity(d0 >= 0 ? 0.5 : 0.16)), lineWidth: major ? 1.2 : 0.6)
        }

        // House-cusp ticks on the ecliptic.
        for v in cuspTicks {
            let (pt, depth) = p(v)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1.3, y: pt.y - 1.3, width: 2.6, height: 2.6)),
                     with: .color(.white.opacity(depth >= 0 ? 0.5 : 0.18)))
        }

        // Zodiac glyphs.
        for z in zodiac {
            let (pt, depth) = p(z.v)
            let a = depth >= 0 ? 0.9 : 0.25
            ctx.draw(Text(z.glyph).font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.85, green: 0.6, blue: 1.0).opacity(a)), at: pt)
        }

        // House numerals at each house's mid-longitude.
        for h in houseNumbers {
            let (pt, depth) = p(h.v)
            let a = depth >= 0 ? 0.42 : 0.12
            ctx.draw(Text(h.label).font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(a)), at: pt)
        }

        // Aspect chords. Coloured by harmony; when a planet is selected only the
        // aspects it makes stay bright; the single tightest aspect gently pulses.
        let pulse = 0.5 + 0.5 * sin(phase * 2.0)
        for (i, asp) in aspects.enumerated() {
            let (pa, da) = p(asp.a); let (pb, db) = p(asp.b)
            var a = (da + db) / 2 >= 0 ? 0.55 : 0.18
            var width = 1.0
            if !highlight.isEmpty {
                let involved = highlight.contains(asp.bodyA) || highlight.contains(asp.bodyB)
                a *= involved ? 1.5 : 0.22
                if involved { width = 1.7 }
            }
            if i == tightestAspect {
                a *= 0.75 + 0.7 * pulse
                width += 0.9 * pulse
            }
            ctx.stroke(Path { $0.move(to: pa); $0.addLine(to: pb) },
                       with: .color(SphereGeometry.aspectColor(asp.kind).opacity(min(1, a))), lineWidth: width)
        }

        // Planets, drawn back-to-front, with a soft glow. Glyph labels are spread
        // apart so a tight stellium stays legible (with a leader line when moved).
        let proj = planets.map { ($0, p($0.v)) }.sorted { $0.1.1 < $1.1.1 }
        for entry in proj {
            let (pt, depth) = entry.1
            let color = SphereGeometry.planetColor(entry.0.body)
            let a = depth >= 0 ? 1.0 : 0.4
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)),
                           with: .color(color.opacity(0.5 * a)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2)),
                     with: .color(color.opacity(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1, y: pt.y - 1, width: 2, height: 2)),
                     with: .color(.white.opacity(a)))
            if highlight.contains(entry.0.body) {
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18)),
                           with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }
        // Labels placed after dots so they sit on top; nearest planets get priority.
        var placed: [CGRect] = []
        for entry in proj.reversed() {
            let (pt, depth) = entry.1
            let a = depth >= 0 ? 1.0 : 0.4
            let size = CGSize(width: entry.0.retro ? 26 : 16, height: 15)
            let labelPos = freeLabelPosition(anchor: pt, size: size, placed: placed)
            placed.append(CGRect(x: labelPos.x - size.width / 2, y: labelPos.y - size.height / 2,
                                 width: size.width, height: size.height))
            if hypot(labelPos.x - pt.x, labelPos.y - (pt.y - 14)) > 8 {
                ctx.stroke(Path { $0.move(to: pt); $0.addLine(to: labelPos) },
                           with: .color(.white.opacity(0.2 * a)), lineWidth: 0.5)
            }
            var label = Text(entry.0.body.glyph).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(a))
            if entry.0.retro {
                label = label + Text(" ℞").font(.system(size: 8)).foregroundStyle(.orange.opacity(a))
            }
            ctx.draw(label, at: labelPos)
        }

        // Cardinal directions + key points.
        for c in cardinals { label(c.label, c.v, .white.opacity(0.55), size: 9, ctx: ctx, p: p) }
        label("Z", zenith, .yellow, ctx: ctx, p: p)
        label("AC", ascendant, AppScreen.astrology.tint, ctx: ctx, p: p)
        label("MC", midheaven, AppScreen.astrology.tint, ctx: ctx, p: p)
    }

    private func circle(_ pts: [SIMD3<Double>], color: Color, base: Double, width: Double = 1,
                        glow: Bool = false, ctx: GraphicsContext,
                        p: (SIMD3<Double>) -> (CGPoint, Double), dashed: Bool = false) {
        var front = Path(), back = Path()
        var inFront = false, inBack = false
        for v in pts {
            let (pt, depth) = p(v)
            if depth >= 0 {
                if inFront { front.addLine(to: pt) } else { front.move(to: pt); inFront = true }
                inBack = false
            } else {
                if inBack { back.addLine(to: pt) } else { back.move(to: pt); inBack = true }
                inFront = false
            }
        }
        let style = StrokeStyle(lineWidth: width, dash: dashed ? [2, 4] : [])
        ctx.stroke(back, with: .color(color.opacity(base * 0.28)), style: style)
        if glow {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(front, with: .color(color.opacity(base * 0.6)),
                             style: StrokeStyle(lineWidth: width + 2))
            }
        }
        ctx.stroke(front, with: .color(color.opacity(base)), style: style)
    }

    /// First candidate offset (from just-above the glyph) that doesn't collide
    /// with already-placed labels; falls back to the default if all collide.
    private func freeLabelPosition(anchor: CGPoint, size: CGSize, placed: [CGRect]) -> CGPoint {
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: -14), CGPoint(x: 0, y: -28), CGPoint(x: 0, y: -42),
            CGPoint(x: 18, y: -14), CGPoint(x: -18, y: -14), CGPoint(x: 18, y: -30),
            CGPoint(x: -18, y: -30), CGPoint(x: 0, y: 16), CGPoint(x: 28, y: 2),
            CGPoint(x: -28, y: 2), CGPoint(x: 0, y: 30),
        ]
        for off in offsets {
            let pos = CGPoint(x: anchor.x + off.x, y: anchor.y + off.y)
            let rect = CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                              width: size.width, height: size.height).insetBy(dx: -2, dy: -2)
            if !placed.contains(where: { $0.intersects(rect) }) { return pos }
        }
        return CGPoint(x: anchor.x, y: anchor.y - 14)
    }

    private func label(_ s: String, _ v: SIMD3<Double>, _ color: Color, size: Double = 10,
                       ctx: GraphicsContext, p: (SIMD3<Double>) -> (CGPoint, Double)) {
        let (pt, depth) = p(v)
        let a = depth >= 0 ? 1.0 : 0.3
        ctx.draw(Text(s).font(.system(size: size, weight: .bold)).foregroundStyle(color.opacity(a)), at: pt)
    }
}
