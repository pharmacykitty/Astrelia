import SwiftUI
import CelestialCore
import Astrology

/// Relationship astrology for two saved charts: a **Synastry** bi-wheel with a
/// compatibility score and inter-chart aspects, and a **Composite** midpoint
/// chart — toggled with a segmented control.
///
/// The two natal charts are built once off the render path (≈36 ephemeris evals
/// each), then synastry/composite are derived; nothing heavy runs in `body`.
struct SynastryView: View {
    let personA: SavedChart
    let personB: SavedChart

    enum Mode: String, CaseIterable { case synastry = "Synastry", composite = "Composite" }

    @State private var mode: Mode = .synastry
    @State private var natalA: NatalChart?
    @State private var natalB: NatalChart?
    @State private var report: SynastryReport?
    @State private var composite: CompositeChart?
    @State private var reading: Reading?
    private let tint = AppScreen.astrology.tint

    private var nameA: String { personA.name.isEmpty ? "Person A" : personA.name }
    private var nameB: String { personB.name.isEmpty ? "Person B" : personB.name }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .synastry:
                    if let a = natalA, let b = natalB, let report {
                        SynastryBiWheel(inner: a, outer: b, aspects: report.aspects)
                            .frame(height: 360)
                        scoreCard(report)
                        legend
                        aspectsCard(report)
                    } else {
                        loading
                    }
                case .composite:
                    if let composite {
                        CompositeWheel(composite: composite)
                            .frame(height: 340)
                        Text("The composite is a single chart built from the midpoints of both people — the relationship as its own entity.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        compositeAspectsCard(composite)
                    } else {
                        loading
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.spaceGradient.ignoresSafeArea())
        .navigationTitle("Compatibility")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            personChip(nameA, AppScreen.astrology.tint)
            Image(systemName: "heart.fill").font(.footnote).foregroundStyle(.white.opacity(0.4))
            personChip(nameB, Color(red: 1.0, green: 0.55, blue: 0.72))
        }
    }

    private func personChip(_ name: String, _ color: Color) -> some View {
        Text(name)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    // MARK: Score (synastry)

    private func scoreCard(_ r: SynastryReport) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(r.score) / 100)
                    .stroke(scoreColor(r.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(r.score)")
                    .font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPATIBILITY").font(.caption2.weight(.semibold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.45))
                Text(r.summary)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(AppScreen.astrology.tint, nameA)
            legendDot(Color(red: 1.0, green: 0.55, blue: 0.72), nameB)
            Spacer()
        }
        .font(.caption2).foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).lineLimit(1)
        }
    }

    // MARK: Aspects (synastry)

    private func aspectsCard(_ r: SynastryReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Inter-chart aspects")
            if r.aspects.isEmpty {
                Text("No aspects within orb between these charts.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
            } else {
                ForEach(r.aspects.prefix(40)) { a in
                    Button { reading = synastryReading(a) } label: {
                        HStack(spacing: 8) {
                            Text(a.a.glyph).foregroundStyle(AppScreen.astrology.tint).frame(width: 20)
                            Text(a.kind.glyph).foregroundStyle(SynastryStyle.aspect(a.kind)).frame(width: 20)
                            Text(a.b.glyph).foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.72)).frame(width: 20)
                            Text("\(nameA)'s \(a.a.name) \(a.kind.name.lowercased()) \(nameB)'s \(a.b.name)")
                                .font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f°", a.orb))
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

    private func synastryReading(_ a: SynastryAspect) -> Reading {
        let tone = a.harmony > 0.2 ? "a flowing, supportive contact"
                 : a.harmony < -0.2 ? "a charged, growth-demanding contact"
                 : "a contact that blends ease with friction"
        return Reading(title: "\(a.a.name) \(a.kind.name) \(a.b.name)", sections: [
            ReadingSection(title: "",
                body: "\(nameA)'s \(a.a.name) \(a.kind.name.lowercased()) \(nameB)'s \(a.b.name) — \(tone)."),
            ReadingSection(title: "What it means", body: Interpretation.aspect(a.kind, a.a, a.b)),
        ])
    }

    // MARK: Aspects (composite)

    private func compositeAspectsCard(_ c: CompositeChart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Composite aspects")
            if c.aspects.isEmpty {
                Text("No aspects within orb.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
            } else {
                ForEach(Array(c.aspects.enumerated()), id: \.offset) { _, a in
                    Button {
                        reading = Reading(title: "\(a.bodyA.name) \(a.kind.name) \(a.bodyB.name)",
                                          body: Interpretation.aspect(a.kind, a.bodyA, a.bodyB))
                    } label: {
                        HStack(spacing: 8) {
                            Text(a.bodyA.glyph).foregroundStyle(tint)
                            Text(a.kind.glyph).foregroundStyle(SynastryStyle.aspect(a.kind)).frame(width: 20)
                            Text(a.bodyB.glyph).foregroundStyle(tint)
                            Text(a.kind.name).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Text(String(format: "%.1f°", a.orb))
                                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                        }
                        .font(.system(size: 17))
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

    // MARK: Helpers

    private var loading: some View {
        ProgressView().controlSize(.large).padding(.top, 80)
    }

    private func cardTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(.white.opacity(0.45)).padding(.bottom, 8)
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 60...: .green
        case 45..<60: tint
        default: .orange
        }
    }

    private func load() async {
        // Pull value-type inputs on the main actor (SavedChart is a @Model and not
        // Sendable), then do the heavy chart math off the main actor.
        let inA = (jd: personA.julianDay, loc: personA.location, set: personA.settings)
        let inB = (jd: personB.julianDay, loc: personB.location, set: personB.settings)
        let result = await Task.detached(priority: .userInitiated) {
            let a = NatalChart(at: inA.jd, location: inA.loc, settings: inA.set)
            let b = NatalChart(at: inB.jd, location: inB.loc, settings: inB.set)
            return (a, b, Synastry.report(a, b), Composite.chart(a, b))
        }.value
        natalA = result.0
        natalB = result.1
        report = result.2
        composite = result.3
    }
}
