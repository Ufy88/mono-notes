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
                        let results = store.search(query: searchQuery, in: activeTab)
                        if results.isEmpty {
                            Text("no results")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        } else {
                            ForEach(results) { file in
                                SearchResultRow(
                                    file: file, query: searchQuery,
                                    selectedFile: $selectedFile, selectedTab: $selectedTab,
                                    activeTab: activeTab, sidebarOpen: $sidebarOpen
                                )
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

    // MARK: - Search field

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

    // MARK: - Tab bar

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

    // MARK: - Bottom bar

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
