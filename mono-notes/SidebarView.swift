import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedFile: FileItem?
    @Binding var selectedTab: AppTab
    @Binding var sidebarOpen: Bool

    @State private var activeTab: AppTab = .notes
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var draggingID: UUID? = nil
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 60)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchQuery.isEmpty {
                        // Normal tree view
                        RootDropZone(tab: activeTab, afterID: nil, draggingID: $draggingID)
                        ForEach(Array(store.roots(for: activeTab).enumerated()), id: \.element.id) { _, child in
                            SidebarChildView(
                                child: child, tab: activeTab, depth: 0,
                                selectedFile: $selectedFile, selectedTab: $selectedTab,
                                sidebarOpen: $sidebarOpen, draggingID: $draggingID
                            )
                            RootDropZone(tab: activeTab, afterID: child.id, draggingID: $draggingID)
                        }
                    } else {
                        // Flat search results
                        let results = store.search(query: searchQuery, in: activeTab)
                        if results.isEmpty {
                            Text("no results")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        } else {
                            ForEach(results) { file in
                                SearchResultRow(file: file, query: searchQuery,
                                               selectedFile: $selectedFile, selectedTab: $selectedTab,
                                               activeTab: activeTab, sidebarOpen: $sidebarOpen)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 120)
            }

            Spacer(minLength: 0)
            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .onAppear { activeTab = selectedTab }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                guard !newFolderName.isEmpty else { return }
                store.createFolder(name: newFolderName, in: activeTab)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("search", text: $searchQuery)
                .font(.system(.footnote, design: .monospaced))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button { searchQuery = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { withAnimation { activeTab = tab; searchQuery = "" } } label: {
                    Text(tab.rawValue)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(activeTab == tab ? .semibold : .regular)
                        .foregroundStyle(activeTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(activeTab == tab ? Color(.systemFill) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                let file = store.createFile(kind: activeTab == .notes ? .note : .list, in: activeTab)
                selectedFile = file
                selectedTab = activeTab
                withAnimation { sidebarOpen = false }
            } label: {
                Label(activeTab == .notes ? "note" : "list", systemImage: "square.and.pencil")
                    .font(.system(.footnote, design: .monospaced))
            }
            Spacer()
            Button { showNewFolderAlert = true } label: {
                Label("folder", systemImage: "folder.badge.plus")
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    @EnvironmentObject var store: AppStore
    let file: FileItem
    let query: String
    @Binding var selectedFile: FileItem?
    @Binding var selectedTab: AppTab
    let activeTab: AppTab
    @Binding var sidebarOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.displayTitle)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(selectedFile?.id == file.id ? .primary : .secondary)
                .lineLimit(1)
            highlightedPreview
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedFile?.id == file.id ? Color(.systemFill) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFile = file
            selectedTab = activeTab
            store.setLastOpened(id: file.id, tab: activeTab)
            withAnimation { sidebarOpen = false }
        }
    }

    @ViewBuilder
    private var highlightedPreview: some View {
        // Find first matching snippet
        let text = file.kind == .note ? file.body : file.listItems.map(\.text).joined(separator: " ")
        let lower = text.lowercased()
        let q = query.lowercased()
        if let range = lower.range(of: q) {
            let start = text.index(range.lowerBound, offsetBy: -min(20, text.distance(from: text.startIndex, to: range.lowerBound)))
            let snippet = String(text[start...].prefix(60))
            Text(snippet)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Root drop zone

struct RootDropZone: View {
    @EnvironmentObject var store: AppStore
    let tab: AppTab
    let afterID: UUID?
    @Binding var draggingID: UUID?
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.clear)
            .frame(height: isTargeted ? 4 : 2)
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .dropDestination(for: DragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.move(id: payload.id, toFolder: nil, afterID: afterID, tab: tab)
                }
                draggingID = nil
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Recursive child view

struct SidebarChildView: View {
    @EnvironmentObject var store: AppStore
    let child: FolderChild
    let tab: AppTab
    let depth: Int
    @Binding var selectedFile: FileItem?
    @Binding var selectedTab: AppTab
    @Binding var sidebarOpen: Bool
    @Binding var draggingID: UUID?

    @State private var showDeleteFolderAlert = false
    @State private var showRenameAlert = false
    @State private var localRename = ""
    @State private var autoExpandTimer: Timer? = nil
    @State private var isFolderDropTarget = false

    var body: some View {
        switch child {
        case .folder(let folder): folderRow(folder)
        case .file(let file): fileRow(file)
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .font(.system(.footnote))
                    .foregroundStyle(isFolderDropTarget ? .accentColor : .secondary)
                Text(folder.name)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFolderDropTarget ? Color.accentColor.opacity(0.12) : .clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
            .onTapGesture { store.toggleFolder(id: folder.id, tab: tab) }
            .onLongPressGesture { localRename = folder.name; showRenameAlert = true }
            .dropDestination(for: DragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                autoExpandTimer?.invalidate()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.move(id: payload.id, toFolder: folder.id, afterID: nil, tab: tab)
                    store.expandFolder(id: folder.id, tab: tab)
                }
                draggingID = nil; isFolderDropTarget = false
                return true
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.15)) { isFolderDropTarget = targeted }
                if targeted {
                    autoExpandTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                        store.expandFolder(id: folder.id, tab: tab)
                    }
                } else { autoExpandTimer?.invalidate() }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if folder.children.isEmpty { store.delete(id: folder.id, tab: tab) }
                    else { showDeleteFolderAlert = true }
                } label: { Label("Delete", systemImage: "trash") }
            }
            .draggable(DragPayload(id: folder.id, isFolder: true)) {
                dragPreview(label: folder.name, icon: "folder").onAppear { draggingID = folder.id }
            }

            if folder.isExpanded {
                FolderDropZone(tab: tab, folderID: folder.id, afterID: nil, draggingID: $draggingID)
                ForEach(folder.children) { child in
                    SidebarChildView(child: child, tab: tab, depth: depth + 1,
                                     selectedFile: $selectedFile, selectedTab: $selectedTab,
                                     sidebarOpen: $sidebarOpen, draggingID: $draggingID)
                    FolderDropZone(tab: tab, folderID: folder.id, afterID: child.id, draggingID: $draggingID)
                }
            }
        }
        .alert("Rename Folder", isPresented: $showRenameAlert) {
            TextField("Folder name", text: $localRename)
            Button("Save") { if !localRename.isEmpty { store.renameFolder(id: folder.id, name: localRename, tab: tab) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(folder.name)\"?", isPresented: $showDeleteFolderAlert) {
            Button("Delete", role: .destructive) { store.delete(id: folder.id, tab: tab) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will delete everything inside.") }
    }

    @ViewBuilder
    private func fileRow(_ file: FileItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: file.kind == .note ? "doc.text" : "list.bullet")
                .font(.system(.footnote))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayTitle)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(selectedFile?.id == file.id ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(file.dateLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.vertical, 9)
        .background(selectedFile?.id == file.id ? Color(.systemFill) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFile = file
            selectedTab = tab
            store.setLastOpened(id: file.id, tab: tab)
            withAnimation { sidebarOpen = false }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(id: file.id, tab: tab)
                if selectedFile?.id == file.id { selectedFile = nil }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .draggable(DragPayload(id: file.id, isFolder: false)) {
            dragPreview(label: file.displayTitle, icon: file.kind == .note ? "doc.text" : "list.bullet")
                .onAppear { draggingID = file.id }
        }
        .opacity(draggingID == file.id ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: draggingID)
    }

    private func dragPreview(label: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(.footnote))
            Text(label).font(.system(.footnote, design: .monospaced)).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}

// MARK: - Folder drop zone

struct FolderDropZone: View {
    @EnvironmentObject var store: AppStore
    let tab: AppTab
    let folderID: UUID
    let afterID: UUID?
    @Binding var draggingID: UUID?
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor.opacity(0.3) : Color.clear)
            .frame(height: isTargeted ? 4 : 2)
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .dropDestination(for: DragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.move(id: payload.id, toFolder: folderID, afterID: afterID, tab: tab)
                }
                draggingID = nil
                return true
            } isTargeted: { isTargeted = $0 }
    }
}
