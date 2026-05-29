import Foundation
import Combine

final class AppStore: ObservableObject {
    @Published var data: AppData = AppData()

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("appdata.json")
    }()

    // Debounce: content edits wait 400ms before hitting disk.
    // Structural ops (create/delete/move/rename) call saveImmediately().
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.4

    init() {
        load()
        if !data.didOnboard { onboard() }
    }

    // MARK: - Onboarding

    private func onboard() {
        var sample = FileItem(kind: .note)
        sample.body = "mono-notes\n\nthis is your first note.\nmonospaced. minimal. local.\n\nswipe left to delete.\ndrag to reorder.\ntap folder icon to group."
        sample.updatedAt = Date()
        data.noteRoots.append(.file(sample))
        data.lastOpenedID = sample.id
        data.lastOpenedTab = AppTab.notes.rawValue
        data.didOnboard = true
        saveImmediately()
    }

    // MARK: - Convenience

    var currentTab: AppTab {
        get { AppTab(rawValue: data.lastOpenedTab) ?? .notes }
        set { data.lastOpenedTab = newValue.rawValue; saveImmediately() }
    }

    func roots(for tab: AppTab) -> [FolderChild] {
        tab == .notes ? data.noteRoots : data.listRoots
    }

    func setRoots(_ roots: [FolderChild], for tab: AppTab) {
        if tab == .notes { data.noteRoots = roots } else { data.listRoots = roots }
        saveImmediately()
    }

    // MARK: - Search (flat, across all items in tab)

    func search(query: String, in tab: AppTab) -> [FileItem] {
        guard !query.isEmpty else { return [] }
        return allFiles(in: roots(for: tab)).filter { $0.matches(query: query) }
    }

    // MARK: - Create

    @discardableResult
    func createFile(kind: ItemKind, in tab: AppTab, folderID: UUID? = nil) -> FileItem {
        let file = FileItem(kind: kind)
        let child = FolderChild.file(file)
        if let fid = folderID {
            insertChild(child, intoFolderID: fid, tab: tab)
        } else {
            appendToRoots(child, tab: tab)
        }
        data.lastOpenedID = file.id
        data.lastOpenedTab = tab.rawValue
        saveImmediately()
        return file
    }

    @discardableResult
    func createFolder(name: String, in tab: AppTab, parentID: UUID? = nil) -> Folder {
        let folder = Folder(name: name)
        let child = FolderChild.folder(folder)
        if let pid = parentID {
            insertChild(child, intoFolderID: pid, tab: tab)
        } else {
            prependFolderToRoots(child, tab: tab)
        }
        saveImmediately()
        return folder
    }

    // MARK: - Update (debounced — called on every keystroke)

    func updateFile(_ file: FileItem, tab: AppTab) {
        var r = roots(for: tab)
        updateFileInRoots(&r, file: file)
        if tab == .notes { data.noteRoots = r } else { data.listRoots = r }
        saveDebounced()
    }

    // MARK: - Delete

    func delete(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        deleteFromRoots(&r, id: id)
        setRoots(r, for: tab)
        if data.lastOpenedID == id { data.lastOpenedID = nil }
        saveImmediately()
    }

    // MARK: - Rename folder

    func renameFolder(id: UUID, name: String, tab: AppTab) {
        var r = roots(for: tab)
        renameFolderInRoots(&r, id: id, name: name)
        setRoots(r, for: tab)
    }

    // MARK: - Toggle / expand folder

    func toggleFolder(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        toggleFolderInRoots(&r, id: id)
        setRoots(r, for: tab)
    }

    func expandFolder(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        setFolderExpanded(&r, id: id, expanded: true)
        setRoots(r, for: tab)
    }

    // MARK: - Set last opened

    func setLastOpened(id: UUID, tab: AppTab) {
        data.lastOpenedID = id
        data.lastOpenedTab = tab.rawValue
        saveImmediately()
    }

    // MARK: - Find

    func findFile(id: UUID) -> FileItem? {
        findFileInRoots(data.noteRoots, id: id) ?? findFileInRoots(data.listRoots, id: id)
    }

    func lastOpenedFile() -> (FileItem, AppTab)? {
        if let lid = data.lastOpenedID {
            if let f = findFileInRoots(data.noteRoots, id: lid) { return (f, .notes) }
            if let f = findFileInRoots(data.listRoots, id: lid) { return (f, .lists) }
        }
        let all = allFiles(in: data.noteRoots).map { ($0, AppTab.notes) }
                + allFiles(in: data.listRoots).map { ($0, AppTab.lists) }
        return all.sorted { $0.0.createdAt > $1.0.createdAt }.first
    }

    func hasAnyContent() -> Bool {
        !data.noteRoots.isEmpty || !data.listRoots.isEmpty
    }

    // MARK: - Move (drag & drop)

    func move(id draggedID: UUID, toFolder targetFolderID: UUID?, afterID: UUID?, tab: AppTab) {
        var roots = self.roots(for: tab)
        guard let dragged = extract(id: draggedID, from: &roots) else { return }
        if let folderID = targetFolderID {
            insertChildInRoots(&roots, child: dragged, folderID: folderID, afterID: afterID)
        } else {
            insertAtRoot(&roots, child: dragged, afterID: afterID)
        }
        setRoots(roots, for: tab)
    }

    // MARK: - Persistence

    /// Debounced write — used for content edits (keystrokes).
    func saveDebounced() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeToDisk()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    /// Immediate write — used for structural changes (create/delete/move/rename).
    func saveImmediately() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeToDisk()
    }

    /// Legacy entry point kept for call-sites that need instant persistence.
    func save() { saveImmediately() }

    private func writeToDisk() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path),
              let raw = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(AppData.self, from: raw)
        else { return }
        data = decoded
    }

    // MARK: - Private helpers

    private func appendToRoots(_ child: FolderChild, tab: AppTab) {
        if tab == .notes { data.noteRoots.append(child) }
        else { data.listRoots.append(child) }
    }

    private func prependFolderToRoots(_ child: FolderChild, tab: AppTab) {
        if tab == .notes { data.noteRoots.insert(child, at: 0) }
        else { data.listRoots.insert(child, at: 0) }
    }

    private func insertChild(_ child: FolderChild, intoFolderID id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        insertChildInRoots(&r, child: child, folderID: id, afterID: nil)
        setRoots(r, for: tab)
    }

    private func insertChildInRoots(_ roots: inout [FolderChild], child: FolderChild, folderID: UUID, afterID: UUID?) {
        for i in roots.indices {
            if case .folder(var f) = roots[i], f.id == folderID {
                if let aid = afterID, let idx = f.children.firstIndex(where: { $0.id == aid }) {
                    f.children.insert(child, at: idx + 1)
                } else {
                    f.children.append(child)
                }
                roots[i] = .folder(f)
                return
            }
            if case .folder(var f) = roots[i] {
                insertChildInRoots(&f.children, child: child, folderID: folderID, afterID: afterID)
                roots[i] = .folder(f)
            }
        }
    }

    private func insertAtRoot(_ roots: inout [FolderChild], child: FolderChild, afterID: UUID?) {
        if let aid = afterID, let idx = roots.firstIndex(where: { $0.id == aid }) {
            roots.insert(child, at: idx + 1)
        } else {
            roots.insert(child, at: 0)
        }
    }

    @discardableResult
    private func extract(id: UUID, from roots: inout [FolderChild]) -> FolderChild? {
        for i in roots.indices {
            if roots[i].id == id { let c = roots[i]; roots.remove(at: i); return c }
            if case .folder(var f) = roots[i] {
                if let found = extract(id: id, from: &f.children) {
                    roots[i] = .folder(f); return found
                }
            }
        }
        return nil
    }

    private func deleteFromRoots(_ roots: inout [FolderChild], id: UUID) {
        roots.removeAll { $0.id == id }
        for i in roots.indices {
            if case .folder(var f) = roots[i] {
                deleteFromRoots(&f.children, id: id)
                roots[i] = .folder(f)
            }
        }
    }

    private func updateFileInRoots(_ roots: inout [FolderChild], file: FileItem) {
        for i in roots.indices {
            if case .file(let fi) = roots[i], fi.id == file.id {
                roots[i] = .file(file); return
            }
            if case .folder(var f) = roots[i] {
                updateFileInRoots(&f.children, file: file)
                roots[i] = .folder(f)
            }
        }
    }

    private func renameFolderInRoots(_ roots: inout [FolderChild], id: UUID, name: String) {
        for i in roots.indices {
            if case .folder(var f) = roots[i], f.id == id {
                f.name = name; roots[i] = .folder(f); return
            }
            if case .folder(var f) = roots[i] {
                renameFolderInRoots(&f.children, id: id, name: name)
                roots[i] = .folder(f)
            }
        }
    }

    private func toggleFolderInRoots(_ roots: inout [FolderChild], id: UUID) {
        for i in roots.indices {
            if case .folder(var f) = roots[i], f.id == id {
                f.isExpanded.toggle(); roots[i] = .folder(f); return
            }
            if case .folder(var f) = roots[i] {
                toggleFolderInRoots(&f.children, id: id)
                roots[i] = .folder(f)
            }
        }
    }

    private func setFolderExpanded(_ roots: inout [FolderChild], id: UUID, expanded: Bool) {
        for i in roots.indices {
            if case .folder(var f) = roots[i], f.id == id {
                f.isExpanded = expanded; roots[i] = .folder(f); return
            }
            if case .folder(var f) = roots[i] {
                setFolderExpanded(&f.children, id: id, expanded: expanded)
                roots[i] = .folder(f)
            }
        }
    }

    private func findFileInRoots(_ roots: [FolderChild], id: UUID) -> FileItem? {
        for child in roots {
            switch child {
            case .file(let fi): if fi.id == id { return fi }
            case .folder(let f): if let found = findFileInRoots(f.children, id: id) { return found }
            }
        }
        return nil
    }

    private func allFiles(in roots: [FolderChild]) -> [FileItem] {
        var result: [FileItem] = []
        for child in roots {
            switch child {
            case .file(let fi): result.append(fi)
            case .folder(let f): result += allFiles(in: f.children)
            }
        }
        return result
    }
}
