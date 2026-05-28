import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes
    @State private var sidebarOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if sidebarOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) { sidebarOpen = false }
                    }
                    .transition(.opacity)
            }

            if sidebarOpen {
                SidebarView(
                    selectedFile: $selectedFile,
                    selectedTab: $selectedTab,
                    sidebarOpen: $sidebarOpen
                )
                .frame(width: UIScreen.main.bounds.width * 0.8)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 4, y: 0)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: sidebarOpen)
        .onAppear { restoreLastOpened() }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let file = selectedFile {
            FileEditorView(file: file, tab: selectedTab)
                .id(file.id)
                .safeAreaInset(edge: .top) { editorNavBar }
        } else if store.hasAnyContent() {
            PlaceholderView(sidebarOpen: $sidebarOpen)
        } else {
            EmptyScreenView(
                selectedFile: $selectedFile,
                selectedTab: $selectedTab,
                sidebarOpen: $sidebarOpen
            )
        }
    }

    private var editorNavBar: some View {
        HStack {
            Button {
                openSidebar()
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

    private func openSidebar() {
        // Notify editor to dismiss keyboard and clear focus BEFORE sidebar animates in.
        // UIApplication.resignFirstResponder alone is unreliable when SwiftUI state changes
        // happen in the same runloop tick as the animation.
        NotificationCenter.default.post(name: .sidebarWillOpen, object: nil)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(.easeInOut(duration: 0.22)) { sidebarOpen.toggle() }
    }

    private func restoreLastOpened() {
        if let (file, tab) = store.lastOpenedFile() {
            selectedFile = file
            selectedTab = tab
        }
    }
}
