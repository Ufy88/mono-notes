import SwiftUI
import UIKit

// MARK: - App color palette
// bg    : RGB(26,  26,  26)
// text  : RGB(230, 230, 230)
// accent: RGB(235, 69,  121)

enum AppTheme {
    static let bg           = UIColor(r: 26,  g: 26,  b: 26)
    static let surface      = UIColor(r: 32,  g: 32,  b: 32)
    static let fill         = UIColor(r: 42,  g: 42,  b: 42)
    static let separatorClr = UIColor(r: 50,  g: 50,  b: 50)

    static let textPrimary    = UIColor(r: 230, g: 230, b: 230)
    static let textSecondary  = UIColor(r: 230, g: 230, b: 230, a: 0.55)
    static let textTertiary   = UIColor(r: 230, g: 230, b: 230, a: 0.35)
    static let textQuaternary = UIColor(r: 230, g: 230, b: 230, a: 0.20)

    static let accent = UIColor(r: 235, g: 69, b: 121)

    static func apply() {
        // Global tint (icons, buttons, chevrons)
        UIView.appearance().tintColor = accent

        // List / TableView internals
        UITableView.appearance().backgroundColor     = bg
        UITableView.appearance().separatorColor      = separatorClr
        UITableViewCell.appearance().backgroundColor = bg

        // Navigation (if ever used)
        UINavigationBar.appearance().barTintColor = bg
    }
}

// MARK: - UIColor convenience

private extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.init(red: r/255, green: g/255, blue: b/255, alpha: a)
    }
}

// MARK: - App entry point

@main
struct MonoNotesApp: App {
    @StateObject private var store = AppStore()

    init() {
        AppTheme.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
