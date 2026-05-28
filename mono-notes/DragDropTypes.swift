import Foundation
import UniformTypeIdentifiers
import SwiftUI

// MARK: - UTTypes

extension UTType {
    /// Used when dragging sidebar items (files/folders)
    static let sidebarItem = UTType(exportedAs: "com.mononotes.sidebaritem")
    /// Used when dragging list bullet items within a FileEditorView
    static let listItem    = UTType(exportedAs: "com.mononotes.listitem")
}

// MARK: - Sidebar drag payload

struct DragPayload: Codable, Transferable {
    let id: UUID
    let isFolder: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sidebarItem)
    }
}

// MARK: - List item drag payload

/// Carries the minimum information needed to identify which ListItem is being dragged.
/// Only `id` is required for the reorder logic; `text` is used for the drag preview label.
struct ListItemPayload: Codable, Transferable {
    let id: UUID
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .listItem)
    }
}
