// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Shared design tokens for MCAT Speedrun iOS. Mirrors the desktop web palette.
// Colors adapt automatically to light/dark via a dynamic UIColor provider, and
// text uses the system rounded face (SF Pro Rounded) to match the web app.

import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let bg = dyn(0xF3F4F9, 0x0F1422)
    static let surface = dyn(0xFFFFFF, 0x181F30)
    static let surface2 = dyn(0xF6F7FB, 0x202840)
    static let border = dyn(0xE8EAF2, 0x2A3349)
    static let text = dyn(0x232C3D, 0xE9ECF5)
    static let muted = dyn(0x8A93A6, 0x98A2B8)
    static let accent = dyn(0x5663EA, 0x6F7BF0)
    static let accent2 = dyn(0x6F7BF0, 0x8B94F4)
    static let green = dyn(0x2FA96B, 0x36B877)
    static let cyan = dyn(0x0EA5E9, 0x38BDF8)
    static let amber = dyn(0xDF9A2F, 0xE6A93F)
    static let red = dyn(0xDF5E79, 0xE87490)
    static let track = dyn(0xE9EBF2, 0x2A3349)

    /// Rounded system font (SF Pro Rounded) at the given size/weight.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let radius: CGFloat = 18
}
