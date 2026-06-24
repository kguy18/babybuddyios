import SwiftUI

/// Baby Buddy brand palette for widgets — mirrors the server's own colors so widgets match
/// the web app and the in-app design.
enum BBColor {
    static let brand   = Color(red: 0x37 / 255.0, green: 0xAB / 255.0, blue: 0xE9 / 255.0) // #37ABE9
    static let feeding = Color(red: 0x23 / 255.0, green: 0x95 / 255.0, blue: 0x56 / 255.0) // #239556
    static let sleep   = Color(red: 0x4A / 255.0, green: 0x5D / 255.0, blue: 0xB0 / 255.0) // #4A5DB0
    static let tummy   = Color(red: 0xFF / 255.0, green: 0x8F / 255.0, blue: 0x00 / 255.0) // #FF8F00
    static let pumping = Color(red: 0x44 / 255.0, green: 0xC4 / 255.0, blue: 0xDD / 255.0) // #44C4DD
    static let stop    = Color(red: 0xFF / 255.0, green: 0xBE / 255.0, blue: 0x42 / 255.0) // #FFBE42 (Baby Buddy "stop")

    static func tint(for activity: TimerActivity) -> Color {
        switch activity {
        case .feeding: return feeding
        case .sleep: return sleep
        case .tummyTime: return tummy
        case .pumping: return pumping
        }
    }
}
