import Foundation

// MARK: - Tree mutation helpers
// Extracted from AppStore to keep it focused on public API + persistence.
// All operations mutate [FolderChild] arrays in-place via inout.

extension Array where Element == FolderChild {

    // MARK: Insert

    mutating func insertChild(_ child: FolderChild, intoFolderID id: UUID, afterID: UUID?) {
        for i in self.indices {
            if case .folder(var f) = self[i], f.id == id {
                if let aid = afterID, let idx = f.children.firstIndex(where: { $0.id == aid }) {
                    f.children.insert(child, at: idx + 1)
                } else {
                    f.children.append(child)
                }
                self[i] = .folder(f)
                return
            }
            if case .folder(var f) = self[i] {
                f.children.insertChild(child, intoFolderID: id, afterID: afterID)
                self[i] = .folder(f)
            }
        }
    }

    mutating func insertAtRoot(_ child: FolderChild, afterID: UUID?) {
        if let aid = afterID, let idx = self.firstIndex(where: { $0.id == aid }) {
            self.insert(child, at: idx + 1)
        } else {
            self.insert(child, at: 0)
        }
    }

    // MARK: Extract (remove + return)

    @discardableResult
    mutating func extract(id: UUID) -> FolderChild? {
        for i in self.indices {
            if self[i].id == id { let c = self[i]; self.remove(at: i); return c }
            if case .folder(var f) = self[i] {
                if let found = f.children.extract(id: id) {
                    self[i] = .folder(f); return found
                }
            }
        }
        return nil
    }

    // MARK: Delete

    mutating func delete(id: UUID) {
        self.removeAll { $0.id == id }
        for i in self.indices {
            if case .folder(var f) = self[i] {
                f.children.delete(id: id)
                self[i] = .folder(f)
            }
        }
    }

    // MARK: Update file

    mutating func updateFile(_ file: FileItem) {
        for i in self.indices {
            if case .file(let fi) = self[i], fi.id == file.id {
                self[i] = .file(file); return
            }
            if case .folder(var f) = self[i] {
                f.children.updateFile(file)
                self[i] = .folder(f)
            }
        }
    }

    // MARK: Rename folder

    mutating func renameFolder(id: UUID, name: String) {
        for i in self.indices {
            if case .folder(var f) = self[i], f.id == id {
                f.name = name; self[i] = .folder(f); return
            }
            if case .folder(var f) = self[i] {
                f.children.renameFolder(id: id, name: name)
                self[i] = .folder(f)
            }
        }
    }

    // MARK: Toggle / expand folder

    mutating func toggleFolder(id: UUID) {
        for i in self.indices {
            if case .folder(var f) = self[i], f.id == id {
                f.isExpanded.toggle(); self[i] = .folder(f); return
            }
            if case .folder(var f) = self[i] {
                f.children.toggleFolder(id: id)
                self[i] = .folder(f)
            }
        }
    }

    mutating func setFolderExpanded(id: UUID, expanded: Bool) {
        for i in self.indices {
            if case .folder(var f) = self[i], f.id == id {
                f.isExpanded = expanded; self[i] = .folder(f); return
            }
            if case .folder(var f) = self[i] {
                f.children.setFolderExpanded(id: id, expanded: expanded)
                self[i] = .folder(f)
            }
        }
    }

    // MARK: Find

    func findFile(id: UUID) -> FileItem? {
        for child in self {
            switch child {
            case .file(let fi): if fi.id == id { return fi }
            case .folder(let f): if let found = f.children.findFile(id: id) { return found }
            }
        }
        return nil
    }

    func allFiles() -> [FileItem] {
        var result: [FileItem] = []
        for child in self {
            switch child {
            case .file(let fi): result.append(fi)
            case .folder(let f): result += f.children.allFiles()
            }
        }
        return result
    }
}
