import SwiftUI
import CelestialCore
import Astrology

/// The three shareable chart-card designs.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case wheel = "Wheel chart"
    case poster = "Big Three poster"
    case readout = "Full readout"
    var id: String { rawValue }
}

/// A poster-format (4:5) card of a chart for sharing — three styles over the app's
/// luminous-instrument language. Rendered to an image with `ImageRenderer`.
struct ChartShareCard: View {
    let chart: NatalChart
    let title: String
    let subtitle: String
    let style: ShareCardStyle

    private let tint = AppScreen.astrology.tint
    private let side: CGFloat = 540   // points; rendered at 2× → 1080×1350

    var body: some View {
        ZStack {
            Theme.spaceGradient
            LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                switch style {
                case .wheel: wheelBody
                case .poster: posterBody
                case .readout: readoutBody
                }
                Spacer(minLength: 0)
                wordmark
            }
            .padding(28)
        }
        .frame(width: side, height: side * 1.25)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(spacing: 4) {
            Text(title.isEmpty ? "Birth Chart" : title)
                .font(.system(size: 30, weight: .bold).width(.expanded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
    }

    private var wordmark: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 11))
            Text("ASTROLABE").font(.system(size: 12, weight: .semibold)).tracking(3)
        }
        .foregroundStyle(tint.opacity(0.8))
        .padding(.top, 8)
    }

    // MARK: Wheel style

    private var wheelBody: some View {
        VStack(spacing: 20) {
            ChartWheel(chart: chart)
                .frame(width: side - 70, height: side - 70)
            bigThreeStrip
        }
    }

    private var bigThreeStrip: some View {
        HStack(spacing: 14) {
            bigThreeChip("Sun", chart.position(of: .sun)?.position.sign)
            bigThreeChip("Moon", chart.position(of: .moon)?.position.sign)
            bigThreeChip("Rising", ZodiacSign(longitude: chart.angles.ascendant))
        }
    }

    private func bigThreeChip(_ label: String, _ sign: ZodiacSign?) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            Text(sign?.glyph ?? "–").font(.system(size: 22)).foregroundStyle(tint)
            Text(sign?.name ?? "—").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }

    // MARK: Poster style

    private var posterBody: some View {
        VStack(spacing: 26) {
            posterRow("Sun", chart.position(of: .sun)?.position.sign, "your core self")
            posterRow("Moon", chart.position(of: .moon)?.position.sign, "your inner world")
            posterRow("Rising", ZodiacSign(longitude: chart.angles.ascendant), "your outward face")
        }
        .padding(.vertical, 10)
    }

    private func posterRow(_ label: String, _ sign: ZodiacSign?, _ blurb: String) -> some View {
        HStack(spacing: 18) {
            Text(sign?.glyph ?? "–")
                .font(.system(size: 56))
                .foregroundStyle(tint)
                .frame(width: 76)
                .shadow(color: tint.opacity(0.6), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(.white.opacity(0.5))
                Text(sign?.name ?? "—").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                Text(blurb).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: Full readout style

    private var readoutBody: some View {
        VStack(spacing: 16) {
            ChartWheel(chart: chart)
                .frame(width: side - 220, height: side - 220)
            let bodies = chart.positions
            let half = (bodies.count + 1) / 2
            HStack(alignment: .top, spacing: 18) {
                readoutColumn(Array(bodies.prefix(half)))
                readoutColumn(Array(bodies.suffix(from: half)))
            }
        }
    }

    private func readoutColumn(_ bodies: [BodyPosition]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(bodies, id: \.body) { p in
                HStack(spacing: 7) {
                    Text(p.body.glyph).font(.system(size: 15)).foregroundStyle(tint).frame(width: 20)
                    Text(p.position.sign.glyph).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                    Text(p.position.description).font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    if p.isRetrograde {
                        Text("℞").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a share card to a PNG file URL (off the view tree). Main-actor because
/// `ImageRenderer` is.
@MainActor
func renderChartShareCard(chart: NatalChart, title: String, subtitle: String,
                          style: ShareCardStyle) -> URL? {
    let renderer = ImageRenderer(content: ChartShareCard(chart: chart, title: title, subtitle: subtitle, style: style))
    renderer.scale = 2
    guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
    let safe = title.isEmpty ? "chart" : title.replacingOccurrences(of: " ", with: "-")
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("astrolabe-\(safe)-\(style.rawValue.prefix(4))").appendingPathExtension("png")
    do { try data.write(to: url); return url } catch { return nil }
}
