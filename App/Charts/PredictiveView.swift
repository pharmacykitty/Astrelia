import SwiftUI
import CelestialCore
import Astrology

/// Predictive astrology for a birth chart: **Progressions** (the secondary-
/// progressed inner chart, "a day for a year") and **Returns** (the solar-return
/// year-ahead chart and the lunar-return month-ahead chart). Built on
/// `Astrology.Progressions` / `Astrology.Returns`; tap any row for a reading.
struct PredictiveView: View {
    let natal: NatalChart
    var title: String
    var store: StarCatalogStore? = nil
    var initialMode: Mode = .progressions

    enum Mode: String, CaseIterable { case progressions = "Progressions", solar = "Solar Return", lunar = "Lunar Return" }

    @State private var mode: Mode

    init(natal: NatalChart, title: String, store: StarCatalogStore? = nil, initialMode: Mode = .progressions) {
        self.natal = natal
        self.title = title
        self.store = store
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }
    @State private var progressed: ProgressedChart?
    @State private var solar: ReturnChart?
    @State private var lunar: ReturnChart?
    @State private var reading: Reading?
    private let tint = AppScreen.astrology.tint

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .progressions:
                    if let progressed { progressionsBody(progressed) }
                    else { loadingSpinner }
                case .solar:
                    returnBody(solar, kind: .solar)
                case .lunar:
                    returnBody(lunar, kind: .lunar)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.spaceGradient.ignoresSafeArea())
        .navigationTitle("Progressions & Returns")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProgressed() }
        .task(id: mode) { await loadReturnIfNeeded() }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
    }

    private var loadingSpinner: some View {
        ProgressView().controlSize(.large).padding(.top, 60)
    }

    // MARK: Progressions

    @ViewBuilder private func progressionsBody(_ p: ProgressedChart) -> some View {
        Button {
            reading = Reading(title: "Secondary progressions",
                              body: Interpretation.progressionsOverview(age: p.age))
        } label: {
            overviewCard(text: Interpretation.progressionsOverview(age: p.age))
        }
        .buttonStyle(.plain)

        // Headline movers: progressed Sun, Moon, and the directed Ascendant.
        HStack(spacing: 12) {
            progressedCell("Prog. Sun", .sun, p)
            progressedCell("Prog. Moon", .moon, p)
            directedAscCell(p)
        }

        progressedPositionsCard(p)
        progressedAspectsCard(p)
    }

    private func progressedCell(_ label: String, _ body: AstroBody, _ p: ProgressedChart) -> some View {
        let pos = p.position(of: body)?.position
        let house = p.house(of: body)
        return Button {
            if let pos, let house {
                reading = Reading(title: "Progressed \(body.name) in \(pos.sign.name)",
                                  body: Interpretation.progressedPlacement(body, sign: pos.sign, house: house))
            }
        } label: {
            bigCell(label: label, glyph: pos?.sign.glyph, name: pos?.sign.name)
        }
        .buttonStyle(.plain)
    }

    private func directedAscCell(_ p: ProgressedChart) -> some View {
        let pos = ZodiacPosition(longitude: p.directedAscendant)
        return Button {
            reading = Reading(title: "Directed Ascendant in \(pos.sign.name)",
                body: "Your Ascendant, advanced by the solar arc of \(String(format: "%.1f°", p.solarArc.degrees)), now points to \(pos.sign.name). " + Interpretation.sign(pos.sign))
        } label: {
            bigCell(label: "Dir. Asc", glyph: pos.sign.glyph, name: pos.sign.name)
        }
        .buttonStyle(.plain)
    }

    private func bigCell(label: String, glyph: String?, name: String?) -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            Text(glyph ?? "–").font(.title).foregroundStyle(tint)
            Text(name ?? "—").font(.caption.weight(.medium)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .luminousSurface(tint, cornerRadius: Theme.cardRadius, glow: 10)
    }

    private func progressedPositionsCard(_ p: ProgressedChart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Progressed positions")
            ForEach(p.positions, id: \.body) { pos in
                let house = p.house(of: pos.body) ?? 1
                Button {
                    reading = Reading(title: "Progressed \(pos.body.name) in \(pos.position.sign.name)",
                                      body: Interpretation.progressedPlacement(pos.body, sign: pos.position.sign, house: house))
                } label: {
                    HStack(spacing: 6) {
                        Text(pos.body.glyph).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
                        Text(pos.body.name).font(.subheadline).foregroundStyle(.white)
                        if pos.isRetrograde {
                            Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(pos.position.description)
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                        Text(ChartDetailView.roman(house))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                            .frame(width: 34, alignment: .trailing)
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

    private func progressedAspectsCard(_ p: ProgressedChart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Aspects to your natal chart")
            if p.aspectsToNatal.isEmpty {
                Text("No progressed aspects within orb right now.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
            } else {
                ForEach(Array(p.aspectsToNatal.prefix(30).enumerated()), id: \.offset) { _, h in
                    Button {
                        reading = Reading(
                            title: "Prog. \(h.transiting.name) \(h.kind.name) natal \(h.natal.name)",
                            body: Interpretation.progressedAspect(h.kind, progressed: h.transiting, natal: h.natal))
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

    // MARK: Returns

    @ViewBuilder private func returnBody(_ ret: ReturnChart?, kind: ReturnKind) -> some View {
        if let ret {
            Button {
                reading = Reading(title: kind.title, body: Interpretation.returnOverview(kind))
            } label: {
                overviewCard(text: Interpretation.returnOverview(kind))
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Text("PERFECTS").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(tint)
                Text(ret.exactDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 10)

            ChartWheel(chart: ret.chart)
                .frame(height: 320)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                returnCell("Sun", ret.chart.position(of: .sun)?.position)
                returnCell("Moon", ret.chart.position(of: .moon)?.position)
                returnCell("Rising", ZodiacPosition(longitude: ret.chart.angles.ascendant))
            }

            NavigationLink {
                ChartDetailView(chart: ret.chart, title: kind.title,
                                subtitle: ret.exactDate.formatted(date: .abbreviated, time: .shortened))
            } label: {
                HubCard(symbol: "chart.pie", title: "View full \(kind == .solar ? "year" : "month") chart",
                        subtitle: "Positions, houses & aspects of the return", tint: tint)
            }
            .buttonStyle(.plain)
        } else {
            loadingSpinner
        }
    }

    private func returnCell(_ label: String, _ pos: ZodiacPosition?) -> some View {
        bigCell(label: label, glyph: pos?.sign.glyph, name: pos?.sign.name)
    }

    // MARK: Shared

    private func overviewCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").foregroundStyle(tint).font(.system(size: 16))
            Text(text)
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 10)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(.white.opacity(0.45)).padding(.bottom, 8)
    }

    // MARK: Loading

    private func loadProgressed() async {
        guard progressed == nil else { return }
        let n = natal
        progressed = await Task.detached(priority: .userInitiated) {
            Progressions.chart(for: n, at: Date())
        }.value
    }

    private func loadReturnIfNeeded() async {
        let n = natal
        switch mode {
        case .solar where solar == nil:
            solar = await Task.detached(priority: .userInitiated) {
                Returns.solarReturn(of: n, onOrAfter: Date())
            }.value
        case .lunar where lunar == nil:
            lunar = await Task.detached(priority: .userInitiated) {
                Returns.lunarReturn(of: n, onOrAfter: Date())
            }.value
        default:
            break
        }
    }
}
