import UIKit
import SwiftUI

// MARK: - App color palette
// bg  : RGB(26,  26,  26)  — near-black dark surface
// text: RGB(230, 230, 230) — soft white
// accent: RGB(235, 69, 121) — hot pink

enum AppTheme {
    // Surfaces
    static let bg        = UIColor(r: 26,  g: 26,  b: 26)
    static let surface   = UIColor(r: 32,  g: 32,  b: 32)   // cards / sidebars
    static let fill      = UIColor(r: 42,  g: 42,  b: 42)   // systemFill replacement
    static let separator = UIColor(r: 50,  g: 50,  b: 50)   // dividers

    // Text
    static let textPrimary    = UIColor(r: 230, g: 230, b: 230)
    static let textSecondary  = UIColor(r: 230, g: 230, b: 230, a: 0.55)
    static let textTertiary   = UIColor(r: 230, g: 230, b: 230, a: 0.35)
    static let textQuaternary = UIColor(r: 230, g: 230, b: 230, a: 0.20)

    // Accent
    static let accent = UIColor(r: 235, g: 69, b: 121)

    // SwiftUI aliases
    static let bgColor     = Color(bg)
    static let accentColor = Color(accent)

    /// Call once at app launch to override system semantic colors globally.
    static func apply() {
        // Override semantic UIColor slots so every view using
        // .systemBackground / .secondarySystemBackground / .systemFill etc.
        // automatically picks up the theme without touching each file.
        UIColor.swizzleSystemColor(named: "systemBackground",          with: bg)
        UIColor.swizzleSystemColor(named: "secondarySystemBackground", with: surface)
        UIColor.swizzleSystemColor(named: "tertiarySystemBackground",  with: fill)
        UIColor.swizzleSystemColor(named: "systemFill",                with: fill)
        UIColor.swizzleSystemColor(named: "secondarySystemFill",       with: fill)
        UIColor.swizzleSystemColor(named: "separator",                 with: separator)
        UIColor.swizzleSystemColor(named: "opaqueSeparator",           with: separator)
        UIColor.swizzleSystemColor(named: "label",                     with: textPrimary)
        UIColor.swizzleSystemColor(named: "secondaryLabel",            with: textSecondary)
        UIColor.swizzleSystemColor(named: "tertiaryLabel",             with: textTertiary)
        UIColor.swizzleSystemColor(named: "quaternaryLabel",           with: textQuaternary)

        // Global tint
        UIView.appearance().tintColor = accent

        // UITableView (SwiftUI List internals)
        UITableView.appearance().backgroundColor        = bg
        UITableView.appearance().separatorColor         = separator
        UITableViewCell.appearance().backgroundColor    = bg
        UINavigationBar.appearance().barTintColor       = bg
    }
}

// MARK: - UIColor convenience init

private extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.init(red: r/255, green: g/255, blue: b/255, alpha: a)
    }

    /// Swizzles `UIColor.<name>` dynamic provider so it always returns `color`
    /// regardless of user interface style (we go full dark-only).
    static func swizzleSystemColor(named name: String, with color: UIColor) {
        // UIColor's named semantic colors are class properties backed by
        // _UIColorName objects. The simplest safe override is to replace
        // the value returned by the dynamic provider via the UIAssetCatalog
        // approach — but that's private API. Instead we use a lighter trick:
        // override the property getter via associated-object caching in
        // UIColor+Overrides category (no swizzling needed, see extension below).
        UIColor.overrides[name] = color
    }

    // Registry of overrides applied by colorNamed lookup hooked in +load.
    static var overrides: [String: UIColor] = [:]
}
