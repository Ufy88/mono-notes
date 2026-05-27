import Foundation
import Combine

final class AppStore: ObservableObject {
    @Published var data: AppData = AppData()

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("appdata.json")
    }()

    init() { load() }

    // MARK: - Convenience

    var currentTab: AppTab {
        get { AppTab(rawValue: data.lastOpenedTab) ?? .notes }
        set { data.lastOpenedTab = newValue.rawValue; save() }
    }

    func roots(for tab: AppTab) -> [FolderChild] {
        tab == .notes ? data.noteRoots : data.listRoots
    }

    // MARK: - Create

    @discardableResult
    func createFile(kind: ItemKind, in tab: AppTab, folderID: UUID? = nil) -> FileItem {
        let file = FileItem(kind: kind)
        let child = FolderChild.file(file)
        if let fid = folderID {
            insertChild(child, intoFolderID: fid, tab: tab)
        } else {
            if tab == .notes {
                data.noteRoots.append(child)
            } else {
                data.listRoots.append(child)
            }
        }
        data.lastOpenedID = file.id
        data.lastOpenedTab = tab.rawValue
        save()
        return file
    }

    @discardableResult
    func createFolder(name: String, in tab: AppTab, parentID: UUID? = nil) -> Folder {
        let folder = Folder(name: name)
        let child = FolderChild.folder(folder)
        if let pid = parentID {
            insertChild(child, intoFolderID: pid, tab: tab)
        } else {
            if tab == .notes {
                data.noteRoots.insert(child, at: 0)
            } else {
                data.listRoots.insert(child, at: 0)
            }
        }
        save()
        return folder
    }

    // MARK: - Update file

    func updateFile(_ file: FileItem, tab: AppTab) {
        updateFileInRoots(&(tab == .notes ? data.noteRoots : data.listRoots), file: file)
        save()
    }

    // MARK: - Delete

    func delete(id: UUID, tab: AppTab) {
        deleteFromRoots(&(tab == .notes ? data.noteRoots : data.listRoots), id: id)
        if data.lastOpenedID == id { data.lastOpenedID = nil }
        save()
    }

    // MARK: - Rename folder

    func renameFolder(id: UUID, name: String, tab: AppTab) {
        renameFolderInRoots(&(tab == .notes ? data.noteRoots : data.listRoots), id: id, name: name)
        save()
    }

    // MARK: - Toggle folder expand

    func toggleFolder(id: UUID, tab: AppTab) {
        toggleFolderInRoots(&(tab == .notes ? data.noteRoots : data.listRoots), id: id)
        save()
    }

    // MARK: - Set last opened

    func setLastOpened(id: UUID, tab: AppTab) {
        data.lastOpenedID = id
        data.lastOpenedTab = tab.rawValue
        save()
    }

    // MARK: - Find file

    func findFile(id: UUID) -> FileItem? {
        findFileInRoots(data.noteRoots, id: id) ?? findFileInRoots(data.listRoots, id: id)
    }

    func lastOpenedFile() -> (FileItem, AppTab)? {
        if let lid = data.lastOpenedID {
            if let f = findFileInRoots(data.noteRoots, id: lid) { return (f, .notes) }
            if let f = findFileInRoots(data.listRoots, id: lid) { return (f, .lists) }
        }
        // fallback: last created in either tab
        let allFiles = allFiles(in: data.noteRoots).map { ($0, AppTab.notes) }
                     + allFiles(in: data.listRoots).map { ($0, AppTab.lists) }
        return allFiles.sorted { $0.0.createdAt > $1.0.createdAt }.first
    }

    func hasAnyContent() -> Bool {
        !data.noteRoots.isEmpty || !data.listRoots.isEmpty
    }

    // MARK: - Persistence

    func save() {
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

    // MARK: - Recursive helpers

    private func insertChild(_ child: FolderChild, intoFolderID id: UUID, tab: AppTab) {
        insertChildInRoots(&(tab == .notes ? data.noteRoots : data.listRoots), child: child, folderID: id)
    }

    private func insertChildInRoots(_ roots: inout [FolderChild], child: FolderChild, folderID: UUID) {
        for i in roots.indices {
            if case .folder(var f) = roots[i], f.id == folderID {
                f.children.append(child)
                roots[i] = .folder(f)
                return
            }
            if case .folder(var f) = roots[i] {
                insertChildInRoots(&f.children, child: child, folderID: folderID)
                roots[i] = .folder(f)
            }
        }
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
                roots[i] = .file(file)
                return
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
                f.name = name
                roots[i] = .folder(f)
                return
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
                f.isExpanded.toggle()
                roots[i] = .folder(f)
                return
            }
            if case .folder(var f) = roots[i] {
                toggleFolderInRoots(&f.children, id: id)
                roots[i] = .folder(f)
            }
        }
    }

    private func findFileInRoots(_ roots: [FolderChild], id: UUID) -> FileItem? {
        for child in roots {
            switch child {
            case .file(let fi): if fi.id == id { return fi }
            case .folder(let f):
                if let found = findFileInRoots(f.children, id: id) { return found }
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
