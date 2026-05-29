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
    // Called the moment the user picks up a row (via .onDrag).
    // Collapses:
    //   a) Own subtree of the dragged item (its children).
    //   b) Every other item in the list that has depth > dragged.depth
    //      — these are children of OTHER parents and must not be
    //      accessible as drop targets while the drag is in flight,
    //      otherwise the dragged item can slip between them and
    //      silently steal their parent role.
    // Saves original expanded state in dragExpandSnapshot so
    // restoreAfterDrag() can undo everything.

    func collapseForDrag(sourceIndex: Int) {
        guard sourceIndex < file.listItems.count else { return }
        let draggedDepth = file.listItems[sourceIndex].depth

        dragExpandSnapshot = [:]

        for i in file.listItems.indices {
            let item = file.listItems[i]
            guard !item.isSeparator else { continue }

            // Record current state for every non-separator item.
            dragExpandSnapshot[item.id] = !item.isCollapsed

            // Collapse:
            // - dragged item's own children (depth > draggedDepth, consecutive after sourceIndex)
            // - any other item with depth > draggedDepth (foreign children)
            if i != sourceIndex && item.depth > draggedDepth {
                file.listItems[i].isCollapsed = true
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
    // Moves the dragged item + its entire subtree to the destination.
    // Restores all collapse states after the move.

    func moveWithChildren(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < file.listItems.count else { return }

        let parent = file.listItems[sourceIndex]

        // Separators move as single rows.
        if parent.isSeparator {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            restoreAfterDrag()
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

        // Single item — plain move.
        if blockSize == 1 {
            file.listItems.move(fromOffsets: source, toOffset: destination)
            restoreAfterDrag()
            onSave()
            return
        }

        // Extract the block.
        let block = Array(file.listItems[sourceIndex ..< blockEnd])
        file.listItems.removeSubrange(sourceIndex ..< blockEnd)

        // Adjust destination after removal.
        var insertAt: Int
        if destination > sourceIndex {
            insertAt = destination - blockSize
        } else {
            insertAt = destination
        }
        insertAt = max(0, min(insertAt, file.listItems.count))

        for (offset, item) in block.enumerated() {
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
