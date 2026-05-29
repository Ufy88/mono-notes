import SwiftUI
import Combine

// MARK: - ListEditorState
// ObservableObject that owns all list-editing mutations:
// item insertion, deletion, indent/unindent, separator handling,
// focus routing, and persistence via AppStore.
//
// Focus is state-driven throughout:
//   - focusedItemID drives isActive on OutlineTextView via updateUIView
//   - noteFocused drives isFocused on NoteEditorWrapper
// No NotificationCenter posts for focus — only .sidebarWillOpen remains
// as a cross-component notification with no common SwiftUI ancestor.

final class ListEditorState: ObservableObject {

    @Published var focusedItemID: UUID? = nil
    @Published var titleFocused: Bool = false
    @Published var keyboardDismissed: Bool = false
    /// Drives NoteEditorWrapper.isFocused; replaces .focusNoteEditor notification.
    @Published var noteFocused: Bool = false

    var file: FileItem
    private let tab: AppTab
    private let store: AppStore

    init(file: FileItem, tab: AppTab, store: AppStore) {
        self.file = file
        self.tab = tab
        self.store = store
    }

    // MARK: - Enter

    func handleEnter(at idx: Int) {
        let current = file.listItems[idx]
        let isEmpty = current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            if current.depth > 0 { file.listItems[idx].depth -= 1; save() }
            return
        }
        let newItem = addNewItem(after: current.id)
        save()
        focusedItemID = newItem.id
    }

    // MARK: - Indent / Unindent

    func indent(at idx: Int) {
        file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4)
        save()
    }

    func handleUnindent(at idx: Int) {
        guard idx < file.listItems.count else { return }
        let visible = file.visibleItemIDs()
        if file.listItems[idx].depth > 0 {
            file.listItems[idx].depth -= 1; save()
            return
        }
        guard file.listItems[idx].text.isEmpty else { return }
        let prevID = prevVisibleID(before: idx, visible: visible)
        file.listItems.remove(at: idx)
        save()
        // Setting focusedItemID is sufficient — OutlineTextView.updateUIView
        // calls becomeFirstResponder when isActive flips to true.
        focusedItemID = prevID
    }

    // MARK: - Separator

    @discardableResult
    func handleDeleteSeparatorAbove(at idx: Int) -> Bool {
        guard idx > 0, idx < file.listItems.count else { return false }
        guard file.listItems[idx - 1].isSeparator else { return false }
        let itemID = file.listItems[idx].id
        file.listItems.remove(at: idx - 1)
        save()
        // State-driven focus — no notification needed.
        focusedItemID = itemID
        return true
    }

    func insertSeparator(after idx: Int) {
        var sep = ListItem(); sep.isSeparator = true
        file.listItems.insert(sep, at: idx + 1)
        let blank = ListItem()
        file.listItems.insert(blank, at: idx + 2)
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusedItemID = blank.id }
    }

    // MARK: - Check / Collapse

    func toggleCheck(at idx: Int) { file.listItems[idx].checked.toggle(); save() }
    func toggleCollapse(at idx: Int) { file.listItems[idx].isCollapsed.toggle(); save() }

    // MARK: - Move

    func moveItems(from: IndexSet, to: Int) {
        file.listItems.move(fromOffsets: from, toOffset: to)
        save()
    }

    // MARK: - Item creation

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

    // MARK: - Focus helpers

    func refocusLast() {
        keyboardDismissed = false
        let lastID = file.listItems.last(where: { !$0.isSeparator })?.id
        if let id = lastID {
            focusedItemID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusedItemID = id }
        } else {
            let item = addNewItem(after: nil); save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusedItemID = item.id }
        }
    }

    func refocus(id: UUID) {
        focusedItemID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusedItemID = id }
    }

    func dismissKeyboard() {
        keyboardDismissed = true
        KeyboardObserver.dismiss()
    }

    func sidebarWillOpen() {
        keyboardDismissed = true
        focusedItemID = nil
        noteFocused = false
    }

    // MARK: - Persistence

    func save() {
        file.updatedAt = Date()
        store.updateFile(file, tab: tab)
    }

    // MARK: - Private

    private func prevVisibleID(before idx: Int, visible: Set<UUID>) -> UUID? {
        guard idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if visible.contains(file.listItems[i].id) && !file.listItems[i].isSeparator {
                return file.listItems[i].id
            }
        }
        return nil
    }
}
