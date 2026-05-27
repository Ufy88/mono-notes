import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedFile: FileItem?
    @Binding var selectedTab: AppTab
    @Binding var sidebarOpen: Bool

    @State private var activeTab: AppTab = .notes
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renamingFolderID: UUID? = nil
    @State private var renameName = ""
    @State private var folderToDelete: Folder? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tab switcher
            tabBar
                .padding(.top, 60)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()

            // List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.roots(for: activeTab)) { child in
                        SidebarChildView(
                            child: child,
                            tab: activeTab,
                            depth: 0,
                            selectedFile: $selectedFile,
                            selectedTab: $selectedTab,
                            sidebarOpen: $sidebarOpen,
                            renamingFolderID: $renamingFolderID,
                            renameName: $renameName
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            Spacer(minLength: 0)

            // Bottom create buttons
            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .onAppear { activeTab = selectedTab }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if !newFolderName.isEmpty {
                    store.createFolder(name: newFolderName, in: activeTab)
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(activeTab == tab ? .semibold : .regular)
                        .foregroundStyle(activeTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            activeTab == tab
                                ? Color(.systemFill)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                let file = store.createFile(kind: activeTab == .notes ? .note : .list, in: activeTab)
                selectedFile = file
                selectedTab = activeTab
                withAnimation { sidebarOpen = false }
            } label: {
                Label(activeTab == .notes ? "New note" : "New list",
                      systemImage: "square.and.pencil")
                    .font(.system(.footnote, design: .monospaced))
            }

            Spacer()

            Button {
                showNewFolderAlert = true
            } label: {
                Label("New folder", systemImage: "folder.badge.plus")
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .foregroundStyle(.primary)
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
    @Binding var renamingFolderID: UUID?
    @Binding var renameName: String

    @State private var showDeleteFolderAlert = false
    @State private var showRenameAlert = false
    @State private var localRename = ""

    var body: some View {
        switch child {
        case .folder(let folder):
            folderRow(folder)
        case .file(let file):
            fileRow(file)
        }
    }

    // MARK: - Folder row

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
                    .foregroundStyle(.secondary)

                Text(folder.name)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                store.toggleFolder(id: folder.id, tab: tab)
            }
            .onLongPressGesture {
                localRename = folder.name
                showRenameAlert = true
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if folder.children.isEmpty {
                        store.delete(id: folder.id, tab: tab)
                    } else {
                        showDeleteFolderAlert = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Children
            if folder.isExpanded {
                ForEach(folder.children) { child in
                    SidebarChildView(
                        child: child,
                        tab: tab,
                        depth: depth + 1,
                        selectedFile: $selectedFile,
                        selectedTab: $selectedTab,
                        sidebarOpen: $sidebarOpen,
                        renamingFolderID: $renamingFolderID,
                        renameName: $renameName
                    )
                }
            }
        }
        .alert("Rename Folder", isPresented: $showRenameAlert) {
            TextField("Folder name", text: $localRename)
            Button("Save") {
                if !localRename.isEmpty {
                    store.renameFolder(id: folder.id, name: localRename, tab: tab)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(folder.name)\"?", isPresented: $showDeleteFolderAlert) {
            Button("Delete", role: .destructive) {
                store.delete(id: folder.id, tab: tab)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete everything inside.")
        }
    }

    // MARK: - File row

    @ViewBuilder
    private func fileRow(_ file: FileItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: file.kind == .note ? "doc.text" : "list.bullet")
                .font(.system(.footnote))
                .foregroundStyle(.secondary)
                .frame(width: 12)

            Text(file.displayTitle)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(selectedFile?.id == file.id ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Text(file.dateLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.vertical, 9)
        .background(
            selectedFile?.id == file.id
                ? Color(.systemFill)
                : Color.clear
        )
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
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
