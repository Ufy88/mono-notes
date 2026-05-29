import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedFile: FileItem? = nil
    @State private var selectedTab: AppTab = .notes
    @State private var sidebarOpen = false

    @State private var dragOffset: CGFloat = 0
    private let edgeWidth: CGFloat = 24
    private let openThreshold: CGFloat = 60
    private let closeThreshold: CGFloat = 60

    // Spring used for both open and close
    private let sidebarSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = geo.size.width * 0.8
            // Sidebar is ALWAYS in the hierarchy — we just slide it in/out via offset.
            // This ensures the closing transition plays identically to the opening one.
            let offset: CGFloat = sidebarOpen
                ? min(dragOffset, 0)          // can't drag further right when open
                : sidebarWidth - max(dragOffset, 0) // partially reveal while dragging open

            ZStack(alignment: .leading) {
                // Main content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(closeSidebarGesture(sidebarWidth: sidebarWidth))

                // Dim overlay — fades with sidebar position
                let progress = 1 - (offset / sidebarWidth)
                Color.black
                    .opacity(0.25 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(sidebarOpen)
                    .onTapGesture {
                        withAnimation(sidebarSpring) { sidebarOpen = false }
                    }

                // Sidebar — always present, moved by offset
                SidebarView(
                    selectedFile: $selectedFile,
                    selectedTab: $selectedTab,
                    sidebarOpen: $sidebarOpen
                )
                .frame(width: sidebarWidth)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 4, y: 0)
                .offset(x: -offset)
                .animation(dragOffset == 0 ? sidebarSpring : nil, value: sidebarOpen)

                // Edge swipe zone when sidebar is closed
                if !sidebarOpen {
                    Color.clear
                        .frame(width: edgeWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(openSidebarGesture(sidebarWidth: sidebarWidth))
                        .ignoresSafeArea()
                }
            }
        }
        .onAppear { restoreLastOpened() }
    }

    // MARK: - Gestures

    private func openSidebarGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
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

    private func closeSidebarGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { _ in }
            .onEnded { value in
                guard sidebarOpen else { return }
                let dx = value.translation.width
                let vx = value.predictedEndTranslation.width
                if dx < -closeThreshold || vx < -sidebarWidth * 0.5 {
                    withAnimation(sidebarSpring) { sidebarOpen = false }
                }
            }
    }

    // MARK: - Helpers

    private func performOpen() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(sidebarSpring) { sidebarOpen = true }
    }

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
