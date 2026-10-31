import SwiftUI

/// The type scale. Stories are set in New York, the system serif; labels are set in
/// the system sans. Every style is tied to a text style so it follows Dynamic Type.
enum Typography {
    static let leadHeadline = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let headline = Font.system(.body, design: .serif).weight(.semibold)
    static let leadSummary = Font.system(.body, design: .serif)
    static let summary = Font.system(.footnote, design: .serif)
    static let kicker = Font.system(.footnote).weight(.semibold)
    static let meta = Font.system(.caption)
    static let notice = Font.system(.subheadline, design: .serif).italic()
    static let stateTitle = Font.system(.title2, design: .serif).weight(.bold)
}
