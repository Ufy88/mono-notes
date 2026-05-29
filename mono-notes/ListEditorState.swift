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

    // MARK: Move with children
    // Replaces the plain .onMove handler so that dragging a parent
    // also moves its entire subtree.
    //
    // Strategy:
    // 1. Identify the subtree block starting at `sourceIndex`:
    //    parent + all consecutive items with greater depth
    //    (stops at a separator or an item at <= parent depth).
    // 2. Remember which items in the block were expanded.
    // 3. Temporarily collapse the parent so List sees one row during drag.
    //    (SwiftUI's onMove already received the source/dest from the gesture,
    //    so we just move the whole block to the correct position here.)
    // 4. Remove the block from its current position, insert at destination,
    //    restore all previously-expanded states.
    //
    // `from` and `to` are the IndexSet / Int that SwiftUI's .onMove provides,
    // which refer to the VISIBLE flat list indices (all items, including
    // collapsed children that are hidden from view but still in the array).

    func moveWithChildren(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < file.listItems.count else { return }

        let parent = file.listItems[sourceIndex]

        // Separators move as single rows — plain move.
        if parent.isSeparator {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            onSave()
            return
        }

        // Collect the subtree: parent + deeper consecutive items.
        var blockEnd = sourceIndex + 1
        while blockEnd < file.listItems.count {
            let item = file.listItems[blockEnd]
            if item.isSeparator { break }
            if item.depth <= parent.depth { break }
            blockEnd += 1
        }
        let blockSize = blockEnd - sourceIndex

        // If it is just one item (no children), plain move.
        if blockSize == 1 {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            onSave()
            return
        }

        // Remember original collapse states of every item in the block.
        var wasExpanded: [UUID: Bool] = [:]
        for i in sourceIndex ..< blockEnd {
            wasExpanded[file.listItems[i].id] = !file.listItems[i].isCollapsed
        }

        // Extract the block.
        let block = Array(file.listItems[sourceIndex ..< blockEnd])

        // Remove block from array.
        file.listItems.removeSubrange(sourceIndex ..< blockEnd)

        // Adjust destination index after removal.
        // SwiftUI passes destination relative to the ORIGINAL array.
        // After removing `blockSize` items starting at `sourceIndex`,
        // items that were after the block shift left by `blockSize`.
        var insertAt: Int
        if destination > sourceIndex {
            insertAt = destination - blockSize
        } else {
            insertAt = destination
        }
        insertAt = max(0, min(insertAt, file.listItems.count))

        // Re-insert block, restoring each item's collapse state.
        for (offset, var item) in block.enumerated() {
            item.isCollapsed = !(wasExpanded[item.id] ?? true)
            file.listItems.insert(item, at: insertAt + offset)
        }

        onSave()
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
