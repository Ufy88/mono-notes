import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var sidebarOpen = false
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            mainContent
                .offset(x: sidebarOpen ? UIScreen.main.bounds.width * 0.8 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sidebarOpen)

            // Dim overlay
            if sidebarOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .offset(x: UIScreen.main.bounds.width * 0.8)
                    .onTapGesture { withAnimation { sidebarOpen = false } }
                    .transition(.opacity)
            }

            // Sidebar
            if sidebarOpen {
                SidebarView(
                    selectedFile: $selectedFile,
                    selectedTab: $selectedTab,
                    sidebarOpen: $sidebarOpen
                )
                .frame(width: UIScreen.main.bounds.width * 0.8)
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
        .onAppear { restoreLastOpened() }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if !store.hasAnyContent() && selectedFile == nil {
            EmptyScreenView(
                selectedFile: $selectedFile,
                selectedTab: $selectedTab,
                sidebarOpen: $sidebarOpen
            )
        } else if let file = selectedFile {
            FileEditorView(
                file: file,
                tab: selectedTab,
                sidebarOpen: $sidebarOpen
            )
        } else {
            // Has content but nothing selected
            PlaceholderView(sidebarOpen: $sidebarOpen)
        }
    }

    private func restoreLastOpened() {
        if let (file, tab) = store.lastOpenedFile() {
            selectedFile = file
            selectedTab = tab
        }
    }
}
