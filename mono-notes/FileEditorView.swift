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
// Only cross-component notifications that have no common SwiftUI ancestor.

extension Notification.Name {
    static let sidebarWillOpen = Notification.Name("sidebarWillOpen")
}

// MARK: - FileEditorView
// Coordinator: toolbar + FAB + note/list branch.
// List mutations delegate to ListEditorState (ListEditorState.swift).
// UIKit wrappers live in ListEditorComponents.swift.

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var keyboard = KeyboardObserver()

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @StateObject private var listState: ListEditorState

    init(file: FileItem, tab: AppTab) {
        self.initialFile = file
        self.tab = tab
        _file = State(initialValue: file)
        _listState = StateObject(wrappedValue: ListEditorState(
            file: file, tab: tab, store: AppStore.shared
        ))
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
                fabButton
            }
        }
        .animation(.easeInOut(duration: 0.18), value: keyboard.isVisible)
        .onAppear {
            let fresh = store.findFile(id: initialFile.id) ?? initialFile
            file = fresh
            listState.file = fresh
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarWillOpen)) { _ in
            listState.sidebarWillOpen()
        }
        .onReceive(listState.objectWillChange) { _ in
            file = listState.file
        }
    }

    // MARK: - FAB
    // For notes: set noteFocused = true — NoteEditorWrapper observes the binding.
    // For lists: refocus the last known item.

    private var fabButton: some View {
        Button {
            if file.kind == .note {
                listState.noteFocused = true
            } else {
                let id = listState.focusedItemID ?? file.listItems.first(where: { !$0.isSeparator })?.id
                if let id { listState.refocus(id: id) }
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
    // isFocused binding replaces the old .focusNoteEditor notification.

    private var noteEditor: some View {
        NoteEditorWrapper(
            text: Binding(
                get: { file.body },
                set: { file.body = $0; file.updatedAt = Date(); store.updateFile(file, tab: tab) }
            ),
            isFocused: $listState.noteFocused,
            onDismiss: { listState.dismissKeyboard() }
        )
    }

    // MARK: - List editor

    private var listEditor: some View {
        List {
            Section {
                TitleTextField(
                    text: Binding(
                        get: { file.title },
                        set: { file.title = $0; listState.file.title = $0; listState.save() }
                    ),
                    placeholder: file.autoTitle,
                    requestFocus: $listState.titleFocused,
                    onReturn: {
                        listState.titleFocused = false
                        listState.keyboardDismissed = false
                        let firstID = file.listItems.first(where: { !$0.isSeparator })?.id
                        if let id = firstID {
                            listState.refocus(id: id)
                        } else {
                            let item = listState.addNewItem(after: nil)
                            listState.save()
                            listState.focusedItemID = item.id
                        }
                    },
                    onDismiss: { listState.dismissKeyboard() }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            }

            let visible = file.visibleItemIDs()
            ForEach($listState.file.listItems, id: \.id) { $item in
                if visible.contains(item.id) {
                    if item.isSeparator {
                        SeparatorRow()
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                    } else {
                        let idx = listState.file.listItems.firstIndex(where: { $0.id == item.id }) ?? 0
                        OutlineItemRow(
                            item: $item,
                            hasChildren: file.hasChildren(after: item),
                            isActive: listState.focusedItemID == item.id && !listState.keyboardDismissed,
                            onFocus: { listState.keyboardDismissed = false; listState.focusedItemID = item.id },
                            onEnter: { listState.handleEnter(at: idx) },
                            onIndent: { listState.indent(at: idx) },
                            onUnindent: { listState.handleUnindent(at: idx) },
                            onDeleteSeparatorAbove: { listState.handleDeleteSeparatorAbove(at: idx) },
                            onCheck: { listState.toggleCheck(at: idx) },
                            onToggleCollapse: { listState.toggleCollapse(at: idx) },
                            onInsertSeparator: { listState.insertSeparator(after: idx) },
                            onDismissKeyboard: { listState.dismissKeyboard() },
                            onChange: { listState.save() }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .onMove { from, to in listState.moveItems(from: from, to: to) }

            Color.clear
                .frame(maxWidth: .infinity).frame(height: 300)
                .contentShape(Rectangle())
                .onTapGesture { listState.refocusLast() }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .moveDisabled(true)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .background(HideReorderHandlesProxy())
    }

    // MARK: - Helpers

    private var wordCountLabel: String {
        "\(file.body.split { $0.isWhitespace }.count)w \(file.body.count)c"
    }
    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }
}
