import Foundation
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Sidebar drag payload

struct DragPayload: Codable, Transferable {
    let id: UUID
    let isFolder: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - List item drag payload

/// Carries id + text for drag preview.
/// Uses .data so no UTType export declaration in Info.plist is required.
struct ListItemPayload: Codable, Transferable {
    let id: UUID
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
