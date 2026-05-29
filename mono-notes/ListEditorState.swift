import SwiftUI

// MARK: - ListEditorState

@Observable
final class ListEditorState {

    var file: FileItem = FileItem(kind: .list)
    var focusedItemID: UUID? = nil
    var onSave: () -> Void = {}

    // MARK: Enter key

    func handleEnter(at idx: Int) {
        guard idx < file.listItems.count else { return }
        let current = file.listItems[idx]
        let isEmpty = current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            if current.depth > 0 { file.listItems[idx].depth -= 1; onSave() }
            return
        }
        let newItem = addNewItem(after: current.id)
        onSave()
        focusedItemID = newItem.id
    }

    // MARK: Unindent / delete empty row

    func handleUnindent(at idx: Int, visible: Set<UUID>) {
        guard idx < file.listItems.count else { return }
        if file.listItems[idx].depth > 0 {
            file.listItems[idx].depth -= 1; onSave()
            return
        }
        guard file.listItems[idx].text.isEmpty else { return }
        let prevID = prevVisibleID(before: idx, visible: visible)
        file.listItems.remove(at: idx)
        onSave()
        if let pid = prevID {
            focusedItemID = pid
            EditorNotification.focusItem(pid).post()
        }
    }

    // MARK: Delete separator above

    @discardableResult
    func handleDeleteSeparatorAbove(at idx: Int) -> Bool {
        guard idx > 0, idx < file.listItems.count else { return false }
        guard file.listItems[idx - 1].isSeparator else { return false }
        let itemID = file.listItems[idx].id
        file.listItems.remove(at: idx - 1)
        onSave()
        focusedItemID = itemID
        EditorNotification.focusItem(itemID).post()
        return true
    }

    // MARK: Add new item

    @discardableResult
    func addNewItem(after id: UUID?) -> ListItem {
        var depth = 0
        var insertIndex = file.listItems.endIndex
        if let id, let idx = file.listItems.firstIndex(where: { $0.id == id }) {
            depth = file.listItems[idx].depth
            insertIndex = idx + 1
        }
        var item = ListItem(); item.depth = depth
        file.listItems.insert(item, at: insertIndex)
        return item
    }

    // MARK: Insert separator
    // Returns the ID of the blank item inserted after the separator so
    // the caller can issue a FocusRequest without any timing hacks.

    @discardableResult
    func insertSeparator(after idx: Int) -> UUID {
        var sep = ListItem(); sep.isSeparator = true
        file.listItems.insert(sep, at: idx + 1)
        let blank = ListItem()
        file.listItems.insert(blank, at: idx + 2)
        onSave()
        return blank.id
    }

    // MARK: Prev visible ID

    func prevVisibleID(before idx: Int, visible: Set<UUID>) -> UUID? {
        guard idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if visible.contains(file.listItems[i].id) && !file.listItems[i].isSeparator {
                return file.listItems[i].id
            }
        }
        return nil
    }
}
