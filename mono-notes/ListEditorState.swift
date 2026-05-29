import SwiftUI

// MARK: - ListEditorState

@Observable
final class ListEditorState {

    var file: FileItem = FileItem(kind: .list)
    var focusedItemID: UUID? = nil
    var onSave: () -> Void = {}

    // Snapshot of items that were expanded before drag started.
    // Key: item ID, Value: true if was expanded (i.e. !isCollapsed).
    private var dragExpandSnapshot: [UUID: Bool] = [:]

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

    // MARK: Collapse for drag
    //
    // Called the moment the user picks up a row.
    //
    // Strategy: hide ALL items that have depth > draggedDepth by collapsing
    // their nearest visible ancestor whose depth == draggedDepth.
    // This means that during the drag the only visible rows are those with
    // depth <= draggedDepth, so the user can only drop between peers or
    // shallower items — never inside a foreign subtree.
    //
    // Saves original expanded state in dragExpandSnapshot so
    // restoreAfterDrag() can undo everything.

    func collapseForDrag(sourceIndex: Int) {
        guard sourceIndex < file.listItems.count else { return }
        let draggedDepth = file.listItems[sourceIndex].depth

        dragExpandSnapshot = [:]

        // Record current expanded state for every non-separator item.
        for i in file.listItems.indices {
            let item = file.listItems[i]
            guard !item.isSeparator else { continue }
            dragExpandSnapshot[item.id] = !item.isCollapsed
        }

        // Collapse every non-separator item whose depth >= draggedDepth
        // (except the dragged item itself) that has any child with
        // depth > draggedDepth directly underneath it.
        // Simpler and more robust: just collapse ALL items with
        // depth >= draggedDepth that are not the dragged item and that
        // have at least one direct or indirect child deeper than draggedDepth.
        // This guarantees no row with depth > draggedDepth is visible.
        for i in file.listItems.indices {
            let item = file.listItems[i]
            guard !item.isSeparator, i != sourceIndex else { continue }

            if item.depth > draggedDepth {
                // Direct foreign child — collapse it too so it disappears.
                file.listItems[i].isCollapsed = true
            } else if item.depth == draggedDepth {
                // Peer: collapse it if it has deeper children, so those
                // children are hidden and cannot become accidental drop targets
                // between their own siblings.
                if file.hasChildren(after: item) {
                    file.listItems[i].isCollapsed = true
                }
            }
        }

        onSave()
    }

    // MARK: Restore after drag
    // Restores every item to its pre-drag collapse state.
    // Called at the end of moveWithChildren.

    private func restoreAfterDrag() {
        guard !dragExpandSnapshot.isEmpty else { return }
        for i in file.listItems.indices {
            let id = file.listItems[i].id
            if let wasExpanded = dragExpandSnapshot[id] {
                file.listItems[i].isCollapsed = !wasExpanded
            }
        }
        dragExpandSnapshot = [:]
    }

    // MARK: Move with children
    //
    // Moves the dragged item + its entire subtree to the destination.
    //
    // Key invariant enforced here: the depth of the moved block is clamped
    // so it can never land inside a foreign subtree.
    //
    // "Allowed depth at destination" = depth of the item immediately above
    // the insertion point (or 0 if there is nothing above).  The dragged
    // block may be inserted at any depth UP TO that value — but never deeper,
    // because that would make it a child of a row it was not originally
    // a child of.  We clamp block depth DOWN to allowedDepth when needed,
    // shifting all items in the block by the same delta.
    //
    // Restores all collapse states after the move.

    func moveWithChildren(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < file.listItems.count else { return }

        let draggedItem = file.listItems[sourceIndex]

        // Separators move as single rows with no depth logic.
        if draggedItem.isSeparator {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            restoreAfterDrag()
            onSave()
            return
        }

        // Collect the subtree: the dragged item + all consecutive deeper items.
        var blockEnd = sourceIndex + 1
        while blockEnd < file.listItems.count {
            let item = file.listItems[blockEnd]
            if item.isSeparator { break }
            if item.depth <= draggedItem.depth { break }
            blockEnd += 1
        }
        let blockSize = blockEnd - sourceIndex
        let block = Array(file.listItems[sourceIndex ..< blockEnd])

        // Remove the block from the list.
        file.listItems.removeSubrange(sourceIndex ..< blockEnd)

        // Compute the actual insertion index after removal.
        var insertAt: Int
        if destination > sourceIndex {
            insertAt = destination - blockSize
        } else {
            insertAt = destination
        }
        insertAt = max(0, min(insertAt, file.listItems.count))

        // --- Depth clamping ---
        // Look at the item immediately above the insertion point (if any).
        // That item's depth is the maximum allowed depth for the block root.
        // If the dragged item's original depth exceeds that, shift the whole
        // block down so the root sits exactly at allowedDepth.
        // This prevents a parent from landing between foreign children.
        let allowedDepth: Int
        if insertAt == 0 {
            allowedDepth = 0
        } else {
            let above = file.listItems[insertAt - 1]
            allowedDepth = above.isSeparator ? 0 : above.depth
        }

        let rootDepth = draggedItem.depth
        let depthDelta = min(0, allowedDepth - rootDepth)  // only clamp down, never push up
        // (If rootDepth <= allowedDepth the delta is 0 and nothing changes.)

        var adjustedBlock = block
        if depthDelta != 0 {
            for i in adjustedBlock.indices {
                adjustedBlock[i].depth = max(0, adjustedBlock[i].depth + depthDelta)
            }
        }

        // Insert the (possibly depth-adjusted) block at the target position.
        for (offset, item) in adjustedBlock.enumerated() {
            file.listItems.insert(item, at: insertAt + offset)
        }

        // Restore collapse states AFTER repositioning.
        restoreAfterDrag()
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
