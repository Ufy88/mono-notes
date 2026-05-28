import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes
    @State private var sidebarOpen = false

    // Drag tracking
    @State private var dragOffset: CGFloat = 0
    private let edgeWidth: CGFloat = 24      // left-edge hit zone width
    private let sidebarWidth: CGFloat = UIScreen.main.bounds.width * 0.8
    private let openThreshold: CGFloat = 60  // min swipe distance to open
    private let closeThreshold: CGFloat = 60 // min swipe distance to close

    var body: some View {
        ZStack(alignment: .leading) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Full-screen gesture: close sidebar by swiping left anywhere
                .gesture(closeSidebarGesture)

            if sidebarOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            sidebarOpen = false
                        }
                    }
                    .transition(.opacity)
            }

            if sidebarOpen {
                SidebarView(
                    selectedFile: $selectedFile,
                    selectedTab: $selectedTab,
                    sidebarOpen: $sidebarOpen
                )
                .frame(width: sidebarWidth)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 4, y: 0)
                .transition(.move(edge: .leading))
            }

            // Invisible left-edge swipe zone — opens sidebar
            if !sidebarOpen {
                Color.clear
                    .frame(width: edgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(openSidebarGesture)
                    .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: sidebarOpen)
        .onAppear { restoreLastOpened() }
    }

    // MARK: - Gestures

    /// Swipe right from the left edge → open sidebar
    private var openSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                // Only respond to mostly-horizontal rightward drags
                guard value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height) * 1.2
                else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let dx = value.translation.width
                let vx = value.predictedEndTranslation.width
                dragOffset = 0
                if dx > openThreshold || vx > sidebarWidth * 0.5 {
                    performOpen()
                }
            }
    }

    /// Swipe left while sidebar is open → close sidebar
    private var closeSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { _ in } // need onChanged for onEnded to fire
            .onEnded { value in
                guard sidebarOpen else { return }
                let dx = value.translation.width
                let vx = value.predictedEndTranslation.width
                if dx < -closeThreshold || vx < -sidebarWidth * 0.5 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        sidebarOpen = false
                    }
                }
            }
    }

    // MARK: - Helpers

    private func performOpen() {
        NotificationCenter.default.post(name: .sidebarWillOpen, object: nil)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            sidebarOpen = true
        }
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
            Button { performOpen() } label: {
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
