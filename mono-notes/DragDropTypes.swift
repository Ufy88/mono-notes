import Foundation
import UniformTypeIdentifiers
import SwiftUI

// UTType for dragging sidebar items
extension UTType {
    static let sidebarItem = UTType(exportedAs: "com.mononotes.sidebaritem")
}

// Payload transferred during drag
struct DragPayload: Codable, Transferable {
    let id: UUID
    let isFolder: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sidebarItem)
    }
}
