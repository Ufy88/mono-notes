import SwiftUI
import UIKit

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
                // Force dark user-interface style so system colors
                // render on the dark surface as expected.
                .preferredColorScheme(.dark)
        }
    }
}
