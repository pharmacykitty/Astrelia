import SwiftUI
import CelestialCore
import Astrology

/// Transits to a natal chart: **Now** (today's aspects, tightest first) and
/// **Upcoming** (a dated timeline of exact hits over the next 90 days), with a
/// Mercury-retrograde banner and optional alerts.
struct TransitsView: View {
    let natal: NatalChart
    var title: String

    enum Mode: String, CaseIterable { case now = "Now", upcoming = "Upcoming" }

    @State private var mode: Mode = .now
    @State private var now = Date()
    @State private var reading: Reading?
    // Cached once — building these is expensive, so never recompute in `body`.
    @State private var transiting: NatalChart?
    @State private var hits: [TransitHit] = []
    @State private var forecast: [ForecastEvent] = []
    @State private var mercuryRetro: RetrogradePeriod?
    @State private var notifyState: NotifyState = .idle
    private let tint = AppScreen.astrology.tint

    enum NotifyState { case idle, on, denied }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let retro = mercuryRetro { retrogradeBanner(retro) }

                switch mode {
                case .now:
                    if let transiting {
                        Text("As of \(now.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                        hitsCard
                        positionsCard(transiting)
                    } else {
                        ProgressView().controlSize(.large).padding(.top, 60)
                    }
                case .upcoming:
                    forecastCard
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.spaceGradient.ignoresSafeArea())
        .navigationTitle("Transits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNow() }
        .task(id: mode) { await loadForecastIfNeeded() }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
    }

    // MARK: Retrograde banner (F5)

    private func retrogradeBanner(_ r: RetrogradePeriod) -> some View {
        let active = r.start <= Date()
        return HStack(spacing: 12) {
            Text("☿℞").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(active ? "Mercury retrograde" : "Mercury retrograde soon")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("\(r.start.formatted(date: .abbreviated, time: .omitted)) – \(r.end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button {
                Task { await enableAlerts() }
            } label: {
                Text(notifyState == .on ? "Alerts on" : notifyState == .denied ? "Denied" : "Notify")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background((notifyState == .on ? Color.green : tint).opacity(0.18), in: Capsule())
                    .foregroundStyle(notifyState == .on ? .green : tint)
            }
            .buttonStyle(.plain)
            .disabled(notifyState != .idle)
        }
        .padding(14)
        .luminousSurface(.orange, cornerRadius: Theme.panelRadius, glow: 10)
    }

    // MARK: Upcoming timeline (F5)

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Next 90 days")
            if forecast.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 24)
            } else {
                ForEach(forecast.prefix(40)) { e in
                    Button {
                        reading = Reading(
                            title: "\(e.transiting.name) \(e.kind.name) natal \(e.natal.name)",
                            body: Interpretation.transit(e.kind, transiting: e.transiting, natal: e.natal))
                    } label: {
                        HStack(spacing: 8) {
                            Text(e.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(tint).frame(width: 52, alignment: .leading)
                            Text(e.transiting.glyph).foregroundStyle(.white)
                            Text(e.kind.glyph).foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                            Text(e.natal.glyph).foregroundStyle(.white.opacity(0.7))
                            Text("\(e.transiting.name) \(e.kind.name.lowercased()) \(e.natal.name)")
                                .font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 16))
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    // MARK: Now (existing)

    private var hitsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Active transits")
            if hits.isEmpty {
                Text("No transits within orb right now.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
            } else {
                ForEach(Array(hits.prefix(40).enumerated()), id: \.offset) { _, h in
                    Button {
                        reading = Reading(
                            title: "\(h.transiting.name) \(h.kind.name) natal \(h.natal.name)",
                            body: Interpretation.transit(h.kind, transiting: h.transiting, natal: h.natal))
                    } label: {
                        HStack(spacing: 8) {
                            Text(h.transiting.glyph).foregroundStyle(tint)
                            Text(h.kind.glyph).foregroundStyle(.white.opacity(0.7)).frame(width: 20)
                            Text(h.natal.glyph).foregroundStyle(.white.opacity(0.7))
                            Text("\(h.transiting.name) \(h.kind.name.lowercased()) \(h.natal.name)")
                                .font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            if h.isApplying == true {
                                Text("↑").font(.caption2.bold()).foregroundStyle(.green.opacity(0.8))
                            }
                            Spacer()
                            Text(String(format: "%.1f°", h.orb))
                                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                        }
                        .font(.system(size: 16))
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func positionsCard(_ transiting: NatalChart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Transiting now")
            ForEach(transiting.positions, id: \.body) { p in
                HStack {
                    Text(p.body.glyph).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
                    Text(p.body.name).font(.subheadline).foregroundStyle(.white)
                    if p.isRetrograde {
                        Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(p.position.description)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.vertical, 7)
                Divider().overlay(.white.opacity(0.08))
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(.white.opacity(0.45)).padding(.bottom, 8)
    }

    // MARK: Loading

    private func loadNow() async {
        let n = natal
        let t = await Task.detached(priority: .userInitiated) {
            NatalChart(at: JulianDay(Date()), location: n.location, settings: n.settings)
        }.value
        now = Date()
        transiting = t
        hits = Transits.hits(transiting: t.positions, natal: n.positions, policy: n.settings.orbs)
        // Mercury retrograde for the banner (cheap-ish; off the main actor).
        mercuryRetro = await Task.detached(priority: .utility) {
            Forecast.retrogrades(of: .mercury, days: 150, from: Date()).first { $0.end > Date() }
        }.value
        if notifyState == .idle, await TransitNotifications.authorizationStatus() == .authorized {
            notifyState = .on
        }
    }

    private func loadForecastIfNeeded() async {
        guard mode == .upcoming, forecast.isEmpty else { return }
        let n = natal
        forecast = await Task.detached(priority: .userInitiated) {
            Forecast.upcoming(for: n, days: 90)
        }.value
    }

    private func enableAlerts() async {
        let ok = await TransitNotifications.schedule(
            retrograde: mercuryRetro,
            events: forecast.isEmpty ? Forecast.upcoming(for: natal, days: 90) : forecast,
            chartName: title)
        notifyState = ok ? .on : .denied
    }
}
