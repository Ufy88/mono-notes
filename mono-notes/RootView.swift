import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes
    @State private var sidebarOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Dim overlay
            if sidebarOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { sidebarOpen = false } }
                    .transition(.opacity)
            }

            // Sidebar
            if sidebarOpen {
                SidebarView(selectedFile: $selectedFile, selectedTab: $selectedTab, sidebarOpen: $sidebarOpen)
                    .frame(width: UIScreen.main.bounds.width * 0.8)
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 4, y: 0)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: sidebarOpen)
        .onAppear { restoreLastOpened() }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if let file = selectedFile {
            FileEditorView(file: file, tab: selectedTab)
                .id(file.id)
                .safeAreaInset(edge: .top) { editorNavBar }
        } else if store.hasAnyContent() {
            PlaceholderView(sidebarOpen: $sidebarOpen)
        } else {
            EmptyScreenView(selectedFile: $selectedFile, selectedTab: $selectedTab)
        }
    }

    private var editorNavBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { sidebarOpen.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 20)
            Spacer()
        }
        .frame(height: 48)
        .background(Color(.systemBackground).opacity(0.95))
    }

    private func restoreLastOpened() {
        if let (file, tab) = store.lastOpenedFile() {
            selectedFile = file
            selectedTab = tab
        }
    }
}
