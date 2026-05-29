import SwiftUI
import UIKit
import Combine

// MARK: - EditorNotification

enum EditorNotification {
    case focusItem(UUID)

    var name: Notification.Name {
        switch self {
        case .focusItem: return Notification.Name("mn.focusItem")
        }
    }

    func post() {
        switch self {
        case .focusItem(let id):
            NotificationCenter.default.post(name: name, object: nil, userInfo: ["id": id])
        }
    }
}

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

// MARK: - FileEditorView

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var keyboard = KeyboardObserver()
    @State private var listState = ListEditorState()

    let initialFile: FileItem
    let tab: AppTab
    @Binding var sidebarIsOpen: Bool

    @State private var file: FileItem
    @State private var titleFocused: Bool = false
    @State private var keyboardDismissed: Bool = false
    @State private var noteEditorFocusRequest: Bool = false
    @State private var noteTitleFocused: Bool = false

    private var focusedItemID: UUID? {
        get { listState.focusedItemID }
        nonmutating set { listState.focusedItemID = newValue }
    }

    init(file: FileItem, tab: AppTab, sidebarIsOpen: Binding<Bool>) {
        self.initialFile = file
        self.tab = tab
        self._sidebarIsOpen = sidebarIsOpen
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

            // 3.3: smooth .easeInOut(0.15) — removes the lag on appear/disappear
            if !keyboard.isVisible {
                Button {
                    keyboardDismissed = false
                    if file.kind == .note {
                        noteEditorFocusRequest = true
                    } else {
                        let id = listState.focusedItemID ?? file.listItems.first(where: { !$0.isSeparator })?.id
                        if let id {
                            listState.focusedItemID = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                listState.focusedItemID = id
                            }
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
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: keyboard.isVisible)
        .onAppear {
            file = store.findFile(id: initialFile.id) ?? initialFile
            syncState()
        }
        .onChange(of: sidebarIsOpen) { _, isOpen in
            if isOpen {
                keyboardDismissed = true
                listState.focusedItemID = nil
                KeyboardObserver.dismiss()
            }
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
    // 3.2: title field above body. Optional — placeholder shows displayTitle fallback.
    private var noteEditor: some View {
        VStack(spacing: 0) {
            TitleTextField(
                text: Binding(get: { file.title }, set: { file.title = $0; save() }),
                placeholder: file.displayTitle,
                requestFocus: $noteTitleFocused,
                onReturn: {
                    noteTitleFocused = false
                    keyboardDismissed = false
                    noteEditorFocusRequest = true
                },
                onDismiss: { keyboardDismissed = true; KeyboardObserver.dismiss() }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            NoteEditorWrapper(
                text: Binding(
                    get: { file.body },
                    set: { file.body = $0; file.updatedAt = Date(); store.updateFile(file, tab: tab) }
                ),
                focusRequest: $noteEditorFocusRequest,
                onDismiss: { keyboardDismissed = true; KeyboardObserver.dismiss() }
            )
        }
    }

    // MARK: - List editor
    private var listEditor: some View {
        List {
            Section {
                TitleTextField(
                    text: Binding(get: { file.title }, set: { file.title = $0; save() }),
                    placeholder: file.autoTitle,
                    requestFocus: $titleFocused,
                    onReturn: {
                        titleFocused = false; keyboardDismissed = false
                        listState.focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                            ?? listState.addNewItem(after: nil).id
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
                            isActive: listState.focusedItemID == item.id && !keyboardDismissed,
                            onFocus: { keyboardDismissed = false; listState.focusedItemID = item.id },
                            onEnter: { listState.handleEnter(at: idx) },
                            onIndent: { file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4); save() },
                            onUnindent: { listState.handleUnindent(at: idx, visible: visible) },
                            onDeleteSeparatorAbove: { listState.handleDeleteSeparatorAbove(at: idx) },
                            onCheck: { file.listItems[idx].checked.toggle(); save() },
                            onToggleCollapse: { file.listItems[idx].isCollapsed.toggle(); save() },
                            onInsertSeparator: { listState.insertSeparator(after: idx) },
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
                .frame(maxWidth: .infinity).frame(height: 300)
                .contentShape(Rectangle())
                .onTapGesture {
                    keyboardDismissed = false
                    let lastID = file.listItems.last(where: { !$0.isSeparator })?.id
                    if let id = lastID {
                        listState.focusedItemID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            listState.focusedItemID = id
                        }
                    } else {
                        let item = listState.addNewItem(after: nil); save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            listState.focusedItemID = item.id
                        }
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

    // MARK: - Helpers

    private func save() {
        file.updatedAt = Date()
        store.updateFile(file, tab: tab)
        listState.file = file
    }

    private func syncState() {
        listState.file = file
        listState.onSave = {
            self.file = self.listState.file
            self.file.updatedAt = Date()
            self.store.updateFile(self.file, tab: self.tab)
        }
    }

    private var wordCountLabel: String {
        "\(file.body.split { $0.isWhitespace }.count)w \(file.body.count)c"
    }
    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }
}
