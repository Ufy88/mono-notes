import SwiftUI
import UIKit
import Combine

// MARK: - Keyboard visibility observer

final class KeyboardObserver: ObservableObject {
    @Published var isVisible: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isVisible = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isVisible = false }
            .store(in: &cancellables)
    }

    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let focusNoteEditor  = Notification.Name("focusNoteEditor")
    static let sidebarWillOpen  = Notification.Name("sidebarWillOpen")
    static let focusItem        = Notification.Name("focusItem")
}

// MARK: - FileEditorView
// Coordinator: picks note vs list editor, owns toolbar and FAB.
// All UIKit wrappers and list row components live in ListEditorComponents.swift.

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var keyboard = KeyboardObserver()

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @State private var focusedItemID: UUID? = nil
    @State private var titleFocused: Bool = false
    @State private var keyboardDismissed: Bool = false

    init(file: FileItem, tab: AppTab) {
        self.initialFile = file
        self.tab = tab
        _file = State(initialValue: file)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if file.kind == .note { noteEditor } else { listEditor }
            }
            .background(Color(.systemBackground))

            if !keyboard.isVisible {
                Button {
                    keyboardDismissed = false
                    if file.kind == .note {
                        NotificationCenter.default.post(name: .focusNoteEditor, object: nil)
                    } else {
                        let id = focusedItemID ?? file.listItems.first(where: { !$0.isSeparator })?.id
                        if let id {
                            focusedItemID = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedItemID = id }
                        }
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: keyboard.isVisible)
        .onAppear { file = store.findFile(id: initialFile.id) ?? initialFile }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarWillOpen)) { _ in
            keyboardDismissed = true
            focusedItemID = nil
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text(file.dateLabel)
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            Spacer()
            Text(file.kind == .note ? wordCountLabel : checkCountLabel)
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Note editor

    private var noteEditor: some View {
        NoteEditorWrapper(
            text: Binding(
                get: { file.body },
                set: { file.body = $0; file.updatedAt = Date(); store.updateFile(file, tab: tab) }
            ),
            onDismiss: { keyboardDismissed = true; KeyboardObserver.dismiss() }
        )
    }

    // MARK: - List editor
    // editMode stays .active so SwiftUI enables .onMove drag.
    // The grey handles are hidden by HideReorderHandlesProxy (ListEditorComponents.swift).

    private var listEditor: some View {
        List {
            Section {
                TitleTextField(
                    text: Binding(get: { file.title }, set: { file.title = $0; save() }),
                    placeholder: file.autoTitle,
                    requestFocus: $titleFocused,
                    onReturn: {
                        titleFocused = false; keyboardDismissed = false
                        focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                            ?? addNewItem(after: nil).id
                    },
                    onDismiss: { keyboardDismissed = true; KeyboardObserver.dismiss() }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            }

            let visible = file.visibleItemIDs()
            ForEach($file.listItems, id: \.id) { $item in
                if visible.contains(item.id) {
                    if item.isSeparator {
                        SeparatorRow()
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                    } else {
                        let idx = file.listItems.firstIndex(where: { $0.id == item.id }) ?? 0
                        OutlineItemRow(
                            item: $item,
                            hasChildren: file.hasChildren(after: item),
                            isActive: focusedItemID == item.id && !keyboardDismissed,
                            onFocus: { keyboardDismissed = false; focusedItemID = item.id },
                            onEnter: { handleEnter(at: idx) },
                            onIndent: { file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4); save() },
                            onUnindent: { handleUnindent(at: idx, visible: visible) },
                            onDeleteSeparatorAbove: { handleDeleteSeparatorAbove(at: idx) },
                            onCheck: { file.listItems[idx].checked.toggle(); save() },
                            onToggleCollapse: { file.listItems[idx].isCollapsed.toggle(); save() },
                            onInsertSeparator: { insertSeparator(after: idx) },
                            onDismissKeyboard: { keyboardDismissed = true; KeyboardObserver.dismiss() },
                            onChange: { save() }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .onMove { from, to in
                file.listItems.move(fromOffsets: from, toOffset: to)
                save()
            }

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .contentShape(Rectangle())
                .onTapGesture {
                    keyboardDismissed = false
                    let lastID = file.listItems.last(where: { !$0.isSeparator })?.id
                    if let id = lastID {
                        focusedItemID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedItemID = id }
                    } else {
                        let item = addNewItem(after: nil); save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedItemID = item.id }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .moveDisabled(true)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .background(HideReorderHandlesProxy())
    }

    // MARK: - List input logic

    private func handleEnter(at idx: Int) {
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

    private func handleUnindent(at idx: Int, visible: Set<UUID>) {
        guard idx < file.listItems.count else { return }
        if file.listItems[idx].depth > 0 {
            file.listItems[idx].depth -= 1; save()
            return
        }
        guard file.listItems[idx].text.isEmpty else { return }
        let prevID = prevVisibleID(before: idx, visible: visible)
        file.listItems.remove(at: idx)
        save()
        if let pid = prevID {
            focusedItemID = pid
            NotificationCenter.default.post(name: .focusItem, object: nil, userInfo: ["id": pid])
        }
    }

    @discardableResult
    private func handleDeleteSeparatorAbove(at idx: Int) -> Bool {
        guard idx > 0, idx < file.listItems.count else { return false }
        guard file.listItems[idx - 1].isSeparator else { return false }
        let itemID = file.listItems[idx].id
        file.listItems.remove(at: idx - 1)
        save()
        focusedItemID = itemID
        NotificationCenter.default.post(name: .focusItem, object: nil, userInfo: ["id": itemID])
        return true
    }

    @discardableResult
    private func addNewItem(after id: UUID?) -> ListItem {
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

    private func insertSeparator(after idx: Int) {
        var sep = ListItem(); sep.isSeparator = true
        file.listItems.insert(sep, at: idx + 1)
        let blank = ListItem()
        file.listItems.insert(blank, at: idx + 2)
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedItemID = blank.id }
    }

    private func prevVisibleID(before idx: Int, visible: Set<UUID>) -> UUID? {
        guard idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if visible.contains(file.listItems[i].id) && !file.listItems[i].isSeparator {
                return file.listItems[i].id
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func save() { file.updatedAt = Date(); store.updateFile(file, tab: tab) }

    private var wordCountLabel: String {
        "\(file.body.split { $0.isWhitespace }.count)w \(file.body.count)c"
    }
    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }
}
