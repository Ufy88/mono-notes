import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes
    @State private var sidebarOpen = false

    // Single source of truth for sidebar position:
    // 0 = fully open, sidebarWidth = fully hidden.
    @State private var visualOffset: CGFloat = 0   // set after geo is known
    @State private var sidebarWidth: CGFloat = 0
    @State private var isDragging = false

    private let edgeWidth: CGFloat = 24
    private let sidebarSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width * 0.8
            ZStack(alignment: .leading) {

                // Main content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dim overlay proportional to how far sidebar is open
                let progress = sw > 0 ? max(0, 1 - visualOffset / sw) : 0
                Color.black
                    .opacity(0.3 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(progress > 0.01)
                    .onTapGesture { closeSidebar() }

                // Sidebar — always in hierarchy, moved by visualOffset
                SidebarView(
                    selectedFile: $selectedFile,
                    selectedTab: $selectedTab,
                    sidebarOpen: $sidebarOpen
                )
                .frame(width: sw)
                .shadow(color: .black.opacity(0.15), radius: 16, x: 4, y: 0)
                .offset(x: -visualOffset)

                // Edge swipe-open zone
                Color.clear
                    .frame(width: edgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(edgeDrag(sidebarWidth: sw))
            }
            .gesture(closeDrag(sidebarWidth: sw))
            .onAppear {
                sidebarWidth = sw
                visualOffset = sw   // start hidden
            }
            .onChange(of: geo.size) { _, size in
                sidebarWidth = size.width * 0.8
                visualOffset = sidebarOpen ? 0 : sidebarWidth
            }
        }
        .onAppear { restoreLastOpened() }
    }

    // MARK: - Gestures

    /// Swipe from left edge to open
    private func edgeDrag(sidebarWidth sw: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                isDragging = true
                let raw = sw - value.translation.width
                visualOffset = max(0, min(sw, raw))
            }
            .onEnded { value in
                isDragging = false
                let vx = value.predictedEndTranslation.width
                if value.translation.width > 50 || vx > sw * 0.4 {
                    openSidebar(sw: sw)
                } else {
                    closeSidebar(sw: sw)
                }
            }
    }

    /// Swipe left anywhere to close
    private func closeDrag(sidebarWidth sw: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard sidebarOpen,
                      value.translation.width < 0,
                      abs(value.translation.width) > abs(value.translation.height) * 1.2
                else { return }
                isDragging = true
                let raw = abs(value.translation.width)
                visualOffset = max(0, min(sw, raw))
            }
            .onEnded { value in
                guard sidebarOpen else { return }
                isDragging = false
                let vx = value.predictedEndTranslation.width
                if value.translation.width < -50 || vx < -sw * 0.4 {
                    closeSidebar(sw: sw)
                } else {
                    openSidebar(sw: sw)
                }
            }
    }

    // MARK: - Open / Close

    private func openSidebar(sw: CGFloat? = nil) {
        let w = sw ?? sidebarWidth
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(sidebarSpring) {
            visualOffset = 0
            sidebarOpen = true
        }
    }

    private func closeSidebar(sw: CGFloat? = nil) {
        let w = sw ?? sidebarWidth
        withAnimation(sidebarSpring) {
            visualOffset = w
            sidebarOpen = false
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if let file = selectedFile {
            FileEditorView(file: file, tab: selectedTab, sidebarIsOpen: $sidebarOpen)
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
            Button { openSidebar() } label: {
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
