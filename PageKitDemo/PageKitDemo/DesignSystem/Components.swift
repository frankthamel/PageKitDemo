import SwiftUI

/// A horizontal printer's rule.
struct Rule: View {
    var weight: CGFloat = 0.5
    var color: Color = Palette.rule

    var body: some View {
        color.frame(height: weight)
    }
}

/// The paper's one drawn motif: a planet, a tilted ring and a small satellite.
/// It appears in the masthead, on image placeholders and on the loading screen.
struct OrbitEmblem: View {
    var planet: Color
    var ring: Color
    var satellite: Color
    /// Where the satellite sits on the ring. Zero is the near-right side.
    var satelliteAngle: Angle = .degrees(35)

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.26
            let lineWidth = max(1, radius * 0.07)
            var tilted = context
            tilted.translateBy(x: size.width / 2, y: size.height / 2)
            tilted.rotate(by: .degrees(-22))

            tilted.stroke(ringHalf(radius, from: .degrees(180), to: .degrees(360)), with: .color(ring), lineWidth: lineWidth)
            tilted.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(planet))
            tilted.stroke(ringHalf(radius, from: .degrees(0), to: .degrees(180)), with: .color(ring), lineWidth: lineWidth)

            let centre = CGPoint(
                x: cos(satelliteAngle.radians) * radius * Self.ringWidth,
                y: sin(satelliteAngle.radians) * radius * Self.ringHeight
            )
            let dot = radius * 0.17
            tilted.fill(Path(ellipseIn: CGRect(x: centre.x - dot, y: centre.y - dot, width: dot * 2, height: dot * 2)), with: .color(satellite))
        }
        .accessibilityHidden(true)
    }

    private static let ringWidth = 1.8
    private static let ringHeight = 0.5

    private func ringHalf(_ radius: CGFloat, from start: Angle, to end: Angle) -> Path {
        Path { path in
            path.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        }
        .applying(CGAffineTransform(scaleX: Self.ringWidth, y: Self.ringHeight))
    }
}

/// Stands in for a story with no picture, or a picture that failed to load.
struct RetroPlaceholder: View {
    let swatch: Swatch
    let monogram: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: .bottomLeading) {
                swatch.color
                OrbitEmblem(
                    planet: swatch.markColor.opacity(0.14),
                    ring: swatch.markColor.opacity(0.4),
                    satellite: swatch.markColor
                )
                .frame(width: side * 1.5, height: side * 1.5)
                .position(x: proxy.size.width - side * 0.3, y: side * 0.3)
                Text(monogram)
                    .font(.system(size: side * 0.5, weight: .black, design: .serif))
                    .foregroundStyle(swatch.markColor)
                    .padding(.leading, side * 0.1)
                    .padding(.bottom, side * 0.04)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// A story's picture at a fixed size, so a late image never moves the list. The placeholder
/// shows only until the image arrives, so a loaded row doesn't draw both.
struct ArticleImage: View {
    let url: URL?
    let swatch: Swatch
    let monogram: String

    /// What to load. A change of either value starts a new load.
    private struct Request: Equatable {
        let url: URL?
        let pixelSize: CGSize
    }

    @Environment(\.displayScale) private var displayScale
    @State private var size = CGSize.zero
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RetroPlaceholder(swatch: swatch, monogram: monogram)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .task(id: Request(url: url, pixelSize: pixelSize)) {
                await load()
            }
    }

    private var pixelSize: CGSize {
        CGSize(width: size.width * displayScale, height: size.height * displayScale)
    }

    /// SwiftUI cancels this when the row leaves the screen, which stops the loader too.
    private func load() async {
        guard let url else {
            image = nil
            return
        }
        guard pixelSize != .zero else { return }
        let loaded = try? await ImageLoader.shared.image(for: url, filling: pixelSize)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}

/// The small dot and source name above a headline.
struct Kicker: View {
    let text: String
    let swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(swatch.color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Typography.kicker)
                .foregroundStyle(Palette.signalText)
                .lineLimit(1)
        }
    }
}
