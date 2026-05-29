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

    // MARK: - Search

    func search(query: String, in tab: AppTab) -> [FileItem] {
        guard !query.isEmpty else { return [] }
        return roots(for: tab).allFiles().filter { $0.matches(query: query) }
    }

    // MARK: - Create

    @discardableResult
    func createFile(kind: ItemKind, in tab: AppTab, folderID: UUID? = nil) -> FileItem {
        let file = FileItem(kind: kind)
        let child = FolderChild.file(file)
        if let fid = folderID {
            var r = roots(for: tab)
            r.insertChild(child, intoFolderID: fid, afterID: nil)
            setRoots(r, for: tab)
        } else {
            if tab == .notes { data.noteRoots.append(child) }
            else { data.listRoots.append(child) }
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
            var r = roots(for: tab)
            r.insertChild(child, intoFolderID: pid, afterID: nil)
            setRoots(r, for: tab)
        } else {
            if tab == .notes { data.noteRoots.insert(child, at: 0) }
            else { data.listRoots.insert(child, at: 0) }
            saveImmediately()
        }
        return folder
    }

    // MARK: - Update (debounced)

    func updateFile(_ file: FileItem, tab: AppTab) {
        var r = roots(for: tab)
        r.updateFile(file)
        if tab == .notes { data.noteRoots = r } else { data.listRoots = r }
        saveDebounced()
    }

    // MARK: - Delete

    func delete(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        r.delete(id: id)
        setRoots(r, for: tab)
        if data.lastOpenedID == id { data.lastOpenedID = nil }
    }

    // MARK: - Rename folder

    func renameFolder(id: UUID, name: String, tab: AppTab) {
        var r = roots(for: tab)
        r.renameFolder(id: id, name: name)
        setRoots(r, for: tab)
    }

    // MARK: - Toggle / expand folder

    func toggleFolder(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        r.toggleFolder(id: id)
        setRoots(r, for: tab)
    }

    func expandFolder(id: UUID, tab: AppTab) {
        var r = roots(for: tab)
        r.setFolderExpanded(id: id, expanded: true)
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
        data.noteRoots.findFile(id: id) ?? data.listRoots.findFile(id: id)
    }

    func lastOpenedFile() -> (FileItem, AppTab)? {
        if let lid = data.lastOpenedID {
            if let f = data.noteRoots.findFile(id: lid) { return (f, .notes) }
            if let f = data.listRoots.findFile(id: lid) { return (f, .lists) }
        }
        let all = data.noteRoots.allFiles().map { ($0, AppTab.notes) }
                + data.listRoots.allFiles().map { ($0, AppTab.lists) }
        return all.sorted { $0.0.createdAt > $1.0.createdAt }.first
    }

    func hasAnyContent() -> Bool {
        !data.noteRoots.isEmpty || !data.listRoots.isEmpty
    }

    // MARK: - Move (drag & drop)

    func move(id draggedID: UUID, toFolder targetFolderID: UUID?, afterID: UUID?, tab: AppTab) {
        var roots = self.roots(for: tab)
        guard let dragged = roots.extract(id: draggedID) else { return }
        if let folderID = targetFolderID {
            roots.insertChild(dragged, intoFolderID: folderID, afterID: afterID)
        } else {
            roots.insertAtRoot(dragged, afterID: afterID)
        }
        setRoots(roots, for: tab)
    }

    // MARK: - Persistence

    func saveDebounced() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.writeToDisk() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    func saveImmediately() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeToDisk()
    }

    /// Legacy entry point kept for existing call-sites.
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
}
