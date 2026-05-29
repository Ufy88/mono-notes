import SwiftUI
import UniformTypeIdentifiers

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
        let text = file.kind == .note ? file.body : file.listItems.map(\.text).joined(separator: " ")
        let lower = text.lowercased()
        let q = query.lowercased()
        if let range = lower.range(of: q) {
            let start = text.index(
                range.lowerBound,
                offsetBy: -min(20, text.distance(from: text.startIndex, to: range.lowerBound))
            )
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
    @State private var showDeleteFileAlert = false
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

    // MARK: Folder row
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
                    .foregroundStyle(isFolderDropTarget ? Color.accentColor : Color.secondary)
                Text(folder.name)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button {
                        localRename = folder.name
                        showRenameAlert = true
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        if folder.children.isEmpty { store.delete(id: folder.id, tab: tab) }
                        else { showDeleteFolderAlert = true }
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 16 + 12)
            .padding(.trailing, 6)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFolderDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
            .onTapGesture { store.toggleFolder(id: folder.id, tab: tab) }
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
            .draggable(DragPayload(id: folder.id, isFolder: true)) {
                dragPreview(label: folder.name, icon: "folder").onAppear { draggingID = folder.id }
            }

            if folder.isExpanded {
                FolderDropZone(tab: tab, folderID: folder.id, afterID: nil, draggingID: $draggingID)
                ForEach(folder.children) { child in
                    SidebarChildView(
                        child: child, tab: tab, depth: depth + 1,
                        selectedFile: $selectedFile, selectedTab: $selectedTab,
                        sidebarOpen: $sidebarOpen, draggingID: $draggingID
                    )
                    FolderDropZone(tab: tab, folderID: folder.id, afterID: child.id, draggingID: $draggingID)
                }
            }
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $localRename)
            Button("Save") {
                guard !localRename.isEmpty else { return }
                if case .folder = child {
                    store.renameFolder(id: child.id, name: localRename, tab: tab)
                } else if case .file(var f) = child {
                    f.title = localRename
                    f.updatedAt = Date()
                    store.updateFile(f, tab: tab)
                    store.saveImmediately()
                    if selectedFile?.id == f.id { selectedFile = f }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(folder.name)\"?", isPresented: $showDeleteFolderAlert) {
            Button("Delete", role: .destructive) { store.delete(id: folder.id, tab: tab) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will delete everything inside.") }
    }

    // MARK: File row
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
            // 4.3: rename + delete in ellipsis menu
            Menu {
                Button {
                    localRename = file.title.isEmpty ? file.displayTitle : file.title
                    showRenameAlert = true
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    showDeleteFileAlert = true
                } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
        .background(selectedFile?.id == file.id ? Color(.systemFill) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFile = file
            selectedTab = tab
            store.setLastOpened(id: file.id, tab: tab)
            withAnimation { sidebarOpen = false }
        }
        // 4.4: swipe shows confirmation alert, no instant delete
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteFileAlert = true
            } label: { Label("Delete", systemImage: "trash") }
        }
        .draggable(DragPayload(id: file.id, isFolder: false)) {
            dragPreview(label: file.displayTitle, icon: file.kind == .note ? "doc.text" : "list.bullet")
                .onAppear { draggingID = file.id }
        }
        .opacity(draggingID == file.id ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: draggingID)
        // Shared alert for both ellipsis and swipe
        .alert("Delete \"\(file.displayTitle)\"?", isPresented: $showDeleteFileAlert) {
            Button("Delete", role: .destructive) {
                store.delete(id: file.id, tab: tab)
                if selectedFile?.id == file.id { selectedFile = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
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
