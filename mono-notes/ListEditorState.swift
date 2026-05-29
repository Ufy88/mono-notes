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

    @discardableResult
    func insertSeparator(after idx: Int) -> UUID {
        var sep = ListItem(); sep.isSeparator = true
        file.listItems.insert(sep, at: idx + 1)
        let blank = ListItem()
        file.listItems.insert(blank, at: idx + 2)
        onSave()
        return blank.id
    }

    // MARK: collapseForDrag (no-op — no collapsing during drag)
    //
    // Previously this function hid deeper items to restrict drop targets.
    // The new behaviour keeps the list fully expanded during drag; depth
    // correction happens entirely inside moveWithChildren on drop.

    func collapseForDrag(sourceIndex: Int) {
        // Intentionally empty — nothing is collapsed while dragging.
    }

    // MARK: Move with children
    //
    // Moves the dragged item + its entire subtree to the destination and
    // adjusts the block's depth so it fits cleanly into its new position.
    //
    // Depth rules at the insertion point (after the block is removed):
    //
    //   maxAllowed  = depth of the item directly ABOVE the insertion point
    //                 (or 0 when inserting at the very top / after a separator).
    //                 The block root cannot be deeper than this, because that
    //                 would make it an orphan child with no matching parent.
    //
    //   minRequired = depth of the item directly BELOW the insertion point
    //                 (or 0 when appending at the end / before a separator).
    //                 The block root cannot be shallower than this, because
    //                 the item below would become an unintended child of
    //                 whatever comes before the block.
    //
    // The block root depth is clamped to [minRequired, maxAllowed].
    // Preference: keep the original depth when it falls within the range;
    // otherwise snap to the nearest bound.
    // All other items in the block are shifted by the same delta so
    // relative structure is preserved.

    func moveWithChildren(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < file.listItems.count else { return }

        let draggedItem = file.listItems[sourceIndex]

        // Separators: plain move, no depth logic.
        if draggedItem.isSeparator {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            onSave()
            return
        }

        // Collect the block: dragged item + consecutive deeper items.
        var blockEnd = sourceIndex + 1
        while blockEnd < file.listItems.count {
            let item = file.listItems[blockEnd]
            if item.isSeparator { break }
            if item.depth <= draggedItem.depth { break }
            blockEnd += 1
        }
        let blockSize = blockEnd - sourceIndex
        let block = Array(file.listItems[sourceIndex ..< blockEnd])

        // Remove block from list.
        file.listItems.removeSubrange(sourceIndex ..< blockEnd)

        // Adjust raw destination index after removal.
        var insertAt: Int
        if destination > sourceIndex {
            insertAt = destination - blockSize
        } else {
            insertAt = destination
        }
        insertAt = max(0, min(insertAt, file.listItems.count))

        // --- Compute allowed depth range at insertAt ---

        // Item above the insertion point.
        let aboveDepth: Int
        if insertAt == 0 {
            aboveDepth = 0
        } else {
            let above = file.listItems[insertAt - 1]
            aboveDepth = above.isSeparator ? 0 : above.depth
        }

        // Item below the insertion point.
        let belowDepth: Int
        if insertAt >= file.listItems.count {
            belowDepth = 0
        } else {
            let below = file.listItems[insertAt]
            belowDepth = below.isSeparator ? 0 : below.depth
        }

        // maxAllowed: block root cannot exceed the depth of the item above
        // (cannot jump into a subtree that doesn't belong to it).
        let maxAllowed = aboveDepth

        // minRequired: block root must be at least as deep as the item below
        // (otherwise the item below would become an accidental child of the
        // block root's predecessor).
        // Special case: if belowDepth > maxAllowed the constraints conflict
        // (this can happen when the flat list is already malformed or during
        // edge cases with separators). In that case maxAllowed wins and the
        // item below will naturally re-attach to its correct ancestor.
        let minRequired = min(belowDepth, maxAllowed)

        // Clamp original depth into [minRequired, maxAllowed].
        let originalDepth = draggedItem.depth
        let clampedDepth = max(minRequired, min(maxAllowed, originalDepth))
        let depthDelta = clampedDepth - originalDepth

        // Apply delta to every item in the block.
        var adjustedBlock = block
        if depthDelta != 0 {
            for i in adjustedBlock.indices {
                adjustedBlock[i].depth = max(0, adjustedBlock[i].depth + depthDelta)
            }
        }

        // Insert adjusted block.
        for (offset, item) in adjustedBlock.enumerated() {
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
