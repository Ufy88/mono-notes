import Foundation

// MARK: - Tabs

enum AppTab: String, CaseIterable, Codable {
    case notes, lists
}

// MARK: - Item kinds

enum ItemKind: String, Codable {
    case note, list
}

// MARK: - List item (for checklist)

struct ListItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var checked: Bool = false
}

// MARK: - File

struct FileItem: Identifiable, Codable {
    var id: UUID = UUID()
    var kind: ItemKind
    var body: String = ""
    var listItems: [ListItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayTitle: String {
        if kind == .list {
            let first = listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
            return first?.text ?? "Empty list"
        }
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first
        guard let line = first else { return "Empty note" }
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

    // Full-text search
    func matches(query: String) -> Bool {
        let q = query.lowercased()
        if kind == .note {
            return body.lowercased().contains(q)
        } else {
            return listItems.contains { $0.text.lowercased().contains(q) }
        }
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
