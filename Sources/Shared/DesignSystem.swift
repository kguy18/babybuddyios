import SwiftUI
import UIKit

/// Baby Buddy design tokens — the single source of truth for color, type, and metrics
/// shared by the app and the widget extension. Mirrors the design spec (`design/`):
/// the authentic Baby Buddy palette, activity color coding, and the action-color grammar.
///
/// Colors are adaptive: each resolves to a light value and a dimmed dark value, so every
/// screen and widget gets correct light/dark rendering for free.
enum BBColor {
    // MARK: Brand & surfaces
    static let brand   = Color(uiColor: UIColor(hex: "37ABE9"))     // primary brand
    static let primary = Color.adaptive(light: "37ABE9", dark: "2F93CC") // filled primary buttons (dimmed in dark)
    static let surface = Color.adaptive(light: "F2F4F6", dark: "0C0E12") // page background
    static let card    = Color.adaptive(light: "FFFFFF", dark: "15181D") // elevated card background

    // MARK: Semantic roles (action-color grammar + status)
    static let success = Color.adaptive(light: "239556", dark: "3AD27E") // synced / running
    static let stop    = Color.adaptive(light: "FFBE42", dark: "E0A52F") // timer stop
    static let restart = Color.adaptive(light: "FF8F00", dark: "E3A55C") // timer restart
    static let danger  = Color.adaptive(light: "A72431", dark: "E0727D") // delete
    static let info    = Color.adaptive(light: "44C4DD", dark: "5FC6DA")
    static let warning = stop

    // MARK: Activity color coding (glyph/accent per record type)
    static let feeding = Color.adaptive(light: "239556", dark: "6CC191")
    static let sleep   = Color.adaptive(light: "4A5DB0", dark: "9AA8E0")
    static let tummy   = Color.adaptive(light: "FF8F00", dark: "E3A55C")
    static let pumping = Color.adaptive(light: "44C4DD", dark: "5FC6DA")
    static let change  = Color.adaptive(light: "8A6D3B", dark: "C9AF83") // diaper — warm tan
    static let note    = Color.adaptive(light: "6C757D", dark: "9AA0A6")

    // MARK: Timeline & inline tag chips
    static let railLine = Color.adaptive(light: "DDE2E7", dark: "23272E") // timeline spine
    /// Fixed green for the timeline "Repeat" swipe action — identical in light & dark (locked decision).
    static let repeatAction = Color(uiColor: UIColor(hex: "239556"))
    static let tagChipFill = Color.adaptive(light: "F1F3F5", dark: "20242A") // neutral inline-tag pill
    static let tagChipText = Color.adaptive(light: "495057", dark: "C2C0B6")

    /// Tint for a running-timer activity (used by the widgets).
    static func tint(for activity: TimerActivity) -> Color {
        switch activity {
        case .feeding: return feeding
        case .sleep: return sleep
        case .tummyTime: return tummy
        case .pumping: return pumping
        }
    }

    /// The accent/glyph color for a record kind, per the activity color coding.
    static func activity(_ kind: EntityKind) -> Color {
        switch kind {
        case .feeding: return feeding
        case .sleep: return sleep
        case .tummyTime: return tummy
        case .pumping: return pumping
        case .change: return change
        case .note: return note
        case .medication: return danger
        case .weight, .height, .headCircumference, .temperature, .bmi: return brand
        case .timer, .child: return brand
        }
    }
}

/// Type tokens. Durations and times use tabular figures so digits don't jitter as they tick.
enum BBFont {
    /// Hero timer readout (active-timer card).
    static let timer = Font.system(size: 40, weight: .semibold).monospacedDigit()
}

/// Corner-radius tokens — generous, calm rounding is core to the look.
enum BBRadius {
    static let card: CGFloat = 20
    static let row: CGFloat = 18
    static let tile: CGFloat = 16
    static let control: CGFloat = 13
}

// MARK: - Color helpers

extension Color {
    /// A color that resolves to `light` in light mode and `dark` in dark mode.
    /// (A failable `Color(hex:)` already exists for server tag colors; here we go through
    /// `UIColor(hex:)` so this token layer stays usable in the widget target too.)
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
