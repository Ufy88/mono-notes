import Foundation

// MARK: - Tabs

enum AppTab: String, CaseIterable, Codable {
    case notes, lists
}

// MARK: - Item kinds

enum ItemKind: String, Codable {
    case note, list
}

// MARK: - List item

struct ListItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var checked: Bool = false
    var depth: Int = 0          // 0 = root, 1 = child, 2 = grandchild, …
    var isCollapsed: Bool = false  // true = children hidden
}

// MARK: - File

struct FileItem: Identifiable, Codable {
    var id: UUID = UUID()
    var kind: ItemKind
    var title: String = ""      // explicit title; empty = auto from first row / first line
    var body: String = ""
    var listItems: [ListItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Resolved display title (sidebar, drag preview)
    var displayTitle: String {
        if kind == .list {
            if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
            let first = listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
            return first?.text ?? "Untitled"
        }
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first
        guard let line = first else { return "Untitled" }
        let s = String(line)
        return s.count > 60 ? String(s.prefix(60)) + "…" : s
    }

    var dateLabel: String {
        let df = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(updatedAt) {
            df.dateFormat = "HH:mm"
        } else if cal.isDateInThisYear(updatedAt) {
            df.dateFormat = "d MMM"
        } else {
            df.dateFormat = "d MMM yy"
        }
        return df.string(from: updatedAt)
    }

    func matches(query: String) -> Bool {
        let q = query.lowercased()
        if kind == .note {
            return body.lowercased().contains(q)
        } else {
            return title.lowercased().contains(q) ||
                   listItems.contains { $0.text.lowercased().contains(q) }
        }
    }

    // MARK: - Collapse helpers

    /// Returns the set of item IDs that should be visible given current collapsed states.
    func visibleItemIDs() -> Set<UUID> {
        var hidden = Set<UUID>()
        var collapsedAncestorDepth: Int? = nil

        for item in listItems {
            if let cap = collapsedAncestorDepth {
                if item.depth > cap {
                    hidden.insert(item.id)
                    continue
                } else {
                    collapsedAncestorDepth = nil
                }
            }
            if item.isCollapsed && hasChildren(after: item) {
                collapsedAncestorDepth = item.depth
            }
        }
        return Set(listItems.map(\.id)).subtracting(hidden)
    }

    /// True if at least one item after `item` has depth > item.depth (before a same-or-lower depth item)
    func hasChildren(after item: ListItem) -> Bool {
        guard let idx = listItems.firstIndex(where: { $0.id == item.id }) else { return false }
        for i in (idx + 1) ..< listItems.count {
            if listItems[i].depth > item.depth { return true }
            if listItems[i].depth <= item.depth { break }
        }
        return false
    }
}

// MARK: - Folder

struct Folder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var children: [FolderChild] = []
    var isExpanded: Bool = true
}

// MARK: - Tree node

indirect enum FolderChild: Identifiable, Codable {
    case file(FileItem)
    case folder(Folder)

    var id: UUID {
        switch self {
        case .file(let f): return f.id
        case .folder(let f): return f.id
        }
    }
}

// MARK: - Root data

struct AppData: Codable {
    var noteRoots: [FolderChild] = []
    var listRoots: [FolderChild] = []
    var lastOpenedID: UUID? = nil
    var lastOpenedTab: String = AppTab.notes.rawValue
    var didOnboard: Bool = false
}

// MARK: - Calendar helper

extension Calendar {
    func isDateInThisYear(_ date: Date) -> Bool {
        component(.year, from: date) == component(.year, from: Date())
    }
}
