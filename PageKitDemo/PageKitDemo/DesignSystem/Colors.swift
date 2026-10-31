import SwiftUI
import UIKit

/// The Orbital's inks. Paper and ink swap for the night edition; the red block,
/// mustard and teal stay recognisably the same colours in both.
enum Palette {
    /// Cream newsprint by day, a deep blue-black night sky after dark.
    static let paper = Color(light: 0xF3E8D2, dark: 0x141C24)
    /// A slightly darker sheet, for strips that sit on the paper.
    static let paperShade = Color(light: 0xE8DABE, dark: 0x1E2933)
    /// Headlines and body text.
    static let ink = Color(light: 0x211C17, dark: 0xF1E6D0)
    /// Summaries and bylines.
    static let inkSoft = Color(light: 0x5A5044, dark: 0xB8AE9C)
    /// Thin rules between stories.
    static let rule = Color(light: 0xC9B99B, dark: 0x3A4753)
    /// The masthead block. White text sits on it in both modes.
    static let signal = Color(hex: 0xC4291C)
    /// Red for small text, lifted after dark so it stays readable.
    static let signalText = Color(light: 0xB32317, dark: 0xF47B6B)
    /// Space-age yellow, for fills only: it has too little contrast for text on paper.
    static let mustard = Color(hex: 0xDDA52A)
    /// Faded teal, for fills.
    static let teal = Color(hex: 0x3E7E7B)
    /// Text and marks on the red block.
    static let onSignal = Color(hex: 0xFFF6E6)
}

/// One of the paper's three spot colours.
nonisolated enum Swatch: CaseIterable, Hashable {
    case signal, mustard, teal
}

extension Swatch {
    /// The fill for this swatch.
    var color: Color {
        switch self {
        case .signal: Palette.signal
        case .mustard: Palette.mustard
        case .teal: Palette.teal
        }
    }

    /// The colour that reads on top of `color`.
    var markColor: Color {
        switch self {
        case .signal, .teal: Palette.onSignal
        case .mustard: Color(hex: 0x211C17)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
