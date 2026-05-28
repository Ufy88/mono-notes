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
    var depth: Int = 0
    var isCollapsed: Bool = false
    /// true = this item is a horizontal separator line, not a text row
    var isSeparator: Bool = false
    /// when isSeparator=true: collapse all items in the block ABOVE this separator
    var blockCollapsed: Bool = false
}

// MARK: - File

struct FileItem: Identifiable, Codable {
    var id: UUID = UUID()
    var kind: ItemKind
    var title: String = ""
    var body: String = ""
    var listItems: [ListItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayTitle: String {
        if kind == .list {
            if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
            let first = listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isSeparator })
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
        if cal.isDateInToday(updatedAt) { df.dateFormat = "HH:mm" }
        else if cal.isDateInThisYear(updatedAt) { df.dateFormat = "d MMM" }
        else { df.dateFormat = "d MMM yy" }
        return df.string(from: updatedAt)
    }

    func matches(query: String) -> Bool {
        let q = query.lowercased()
        if kind == .note { return body.lowercased().contains(q) }
        return title.lowercased().contains(q) ||
               listItems.contains { $0.text.lowercased().contains(q) }
    }

    // MARK: - Visibility

    /// Returns set of IDs that should be rendered.
    /// Two collapse mechanisms:
    /// 1. Outline collapse (isCollapsed on parent row hides deeper children)
    /// 2. Block collapse (blockCollapsed on separator hides all items in block above it)
    func visibleItemIDs() -> Set<UUID> {
        // Step 1: find which items are block-collapsed.
        // A block is defined as all non-separator items between two separators (or start/separator).
        // The separator that ENDS a block owns the blockCollapsed flag.
        var blockHidden = Set<UUID>()
        var currentBlockItems: [UUID] = []

        for item in listItems {
            if item.isSeparator {
                if item.blockCollapsed {
                    for uid in currentBlockItems { blockHidden.insert(uid) }
                }
                currentBlockItems = []
            } else {
                currentBlockItems.append(item.id)
            }
        }
        // last block (after last separator or whole list if no separators) has no separator to collapse it

        // Step 2: outline collapse (existing logic), but skip separator items from depth logic
        var outlineHidden = Set<UUID>()
        var collapsedAncestorDepth: Int? = nil

        for item in listItems {
            if item.isSeparator {
                collapsedAncestorDepth = nil
                continue
            }
            if let cap = collapsedAncestorDepth {
                if item.depth > cap {
                    outlineHidden.insert(item.id)
                    continue
                } else {
                    collapsedAncestorDepth = nil
                }
            }
            if item.isCollapsed && hasChildren(after: item) {
                collapsedAncestorDepth = item.depth
            }
        }

        let allIDs = Set(listItems.map(\.id))
        return allIDs.subtracting(blockHidden).subtracting(outlineHidden)
    }

    func hasChildren(after item: ListItem) -> Bool {
        guard !item.isSeparator,
              let idx = listItems.firstIndex(where: { $0.id == item.id }) else { return false }
        for i in (idx + 1) ..< listItems.count {
            if listItems[i].isSeparator { break }
            if listItems[i].depth > item.depth { return true }
            if listItems[i].depth <= item.depth { break }
        }
        return false
    }

    /// Preview text for a collapsed block (first non-empty item's text)
    func blockPreview(before separatorID: UUID) -> String {
        guard let sepIdx = listItems.firstIndex(where: { $0.id == separatorID }) else { return "" }
        // find start of block (previous separator or 0)
        var blockStart = 0
        for i in stride(from: sepIdx - 1, through: 0, by: -1) {
            if listItems[i].isSeparator { blockStart = i + 1; break }
        }
        for i in blockStart ..< sepIdx {
            let t = listItems[i].text.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t.count > 60 ? String(t.prefix(60)) + "…" : t }
        }
        return "empty"
    }

    /// True if a separator exists anywhere before the given index
    func hasBlockAbove(separatorIndex: Int) -> Bool {
        // block above a separator is always there (even if empty)
        return separatorIndex >= 0
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
