import Foundation

// MARK: - Item kinds

enum ItemKind: String, Codable {
    case note
    case list
}

// MARK: - FileItem (note or list, lives inside a folder or at root)

struct FileItem: Identifiable, Codable {
    var id: UUID = UUID()
    var kind: ItemKind
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayTitle: String {
        if !title.isEmpty { return title }
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first
        guard let line = first else { return kind == .note ? "Empty note" : "Empty list" }
        let s = String(line).trimmingCharacters(in: .init(charactersIn: "•- "))
        return s.count > 60 ? String(s.prefix(60)) + "\u{2026}" : s
    }

    var dateLabel: String {
        let df = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            df.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(updatedAt) {
            return "yesterday"
        } else {
            df.dateFormat = "dd.MM.yy"
        }
        return df.string(from: updatedAt)
    }
}

// MARK: - Folder

struct Folder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var isExpanded: Bool = true
    var children: [FolderChild] = []
    var createdAt: Date = Date()
}

// MARK: - FolderChild (recursive: folder or file)

indirect enum FolderChild: Identifiable, Codable {
    case folder(Folder)
    case file(FileItem)

    var id: UUID {
        switch self {
        case .folder(let f): return f.id
        case .file(let fi): return fi.id
        }
    }
}

// MARK: - Tab

enum AppTab: String, CaseIterable {
    case notes = "notes"
    case lists = "lists"
}

// MARK: - Root data container

struct AppData: Codable {
    var noteRoots: [FolderChild] = []   // notes tab
    var listRoots: [FolderChild] = []   // lists tab
    var lastOpenedID: UUID? = nil
    var lastOpenedTab: AppTab.RawValue = AppTab.notes.rawValue
}

extension AppTab: Codable {}
