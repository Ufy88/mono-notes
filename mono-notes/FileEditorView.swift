import SwiftUI

// MARK: - FileEditorView

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @FocusState private var textFocused: Bool
    @State private var focusedItemID: UUID? = nil

    init(file: FileItem, tab: AppTab) {
        self.initialFile = file
        self.tab = tab
        _file = State(initialValue: file)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if file.kind == .note {
                noteEditor
            } else {
                listEditor
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            file = store.findFile(id: initialFile.id) ?? initialFile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if file.kind == .note {
                    textFocused = true
                } else {
                    if file.listItems.isEmpty {
                        let item = addNewItem(after: nil)
                        focusedItemID = item.id
                    } else {
                        focusedItemID = file.listItems.first?.id
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text(file.dateLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            if file.kind == .note {
                Text(wordCountLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
            } else {
                Text(checkCountLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Note editor

    private var noteEditor: some View {
        TextEditor(text: Binding(
            get: { file.body },
            set: { newVal in
                file.body = newVal
                file.updatedAt = Date()
                store.updateFile(file, tab: tab)
            }
        ))
        .font(.system(.body, design: .monospaced))
        .focused($textFocused)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
    }

    // MARK: - List editor

    private var listEditor: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(file.listItems.indices, id: \.self) { idx in
                    OutlineItemRow(
                        item: $file.listItems[idx],
                        isActive: focusedItemID == file.listItems[idx].id,
                        onFocus: { focusedItemID = file.listItems[idx].id },
                        onEnter: {
                            let newItem = addNewItem(after: file.listItems[idx].id)
                            save()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusedItemID = newItem.id
                            }
                        },
                        onIndent: {
                            file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4)
                            save()
                        },
                        onUnindent: {
                            if file.listItems[idx].depth > 0 {
                                file.listItems[idx].depth -= 1
                                save()
                            } else if file.listItems[idx].text.isEmpty {
                                let prevID = idx > 0 ? file.listItems[idx - 1].id : nil
                                file.listItems.remove(at: idx)
                                save()
                                if let pid = prevID {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        focusedItemID = pid
                                    }
                                }
                            }
                        },
                        onCheck: {
                            file.listItems[idx].checked.toggle()
                            save()
                        },
                        onChange: { save() }
                    )
                }
            }
            .padding(.bottom, 120)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func addNewItem(after id: UUID?) -> ListItem {
        var depth = 0
        var insertIndex = file.listItems.endIndex
        if let id = id, let idx = file.listItems.firstIndex(where: { $0.id == id }) {
            depth = file.listItems[idx].depth
            insertIndex = idx + 1
        }
        var item = ListItem()
        item.depth = depth
        file.listItems.insert(item, at: insertIndex)
        return item
    }

    private func save() {
        file.updatedAt = Date()
        store.updateFile(file, tab: tab)
    }

    private var wordCountLabel: String {
        let words = file.body.split { $0.isWhitespace }.count
        let chars = file.body.count
        return "\(words)w \(chars)c"
    }

    private var checkCountLabel: String {
        let done = file.listItems.filter(\.checked).count
        let total = file.listItems.count
        return "\(done)/\(total)"
    }
}

// MARK: - OutlineItemRow

struct OutlineItemRow: View {
    @Binding var item: ListItem
    let isActive: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onCheck: () -> Void
    let onChange: () -> Void

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 20)
            }

            Text("\u{00B7}")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 20, alignment: .center)
                .onTapGesture { onCheck() }

            TextField("", text: $text, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .strikethrough(item.checked, color: Color(.tertiaryLabel))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit { onEnter() }
                .onChange(of: text) { _, newValue in
                    item.text = newValue
                    onChange()
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused { onFocus() }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if focused {
                            Button { onUnindent() } label: {
                                Image(systemName: "arrow.left.to.line")
                            }
                            Button { onIndent() } label: {
                                Image(systemName: "arrow.right.to.line")
                            }
                            Spacer()
                        }
                    }
                }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onAppear {
            text = item.text
            if isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
        .onChange(of: item.text) { _, newValue in
            if text != newValue { text = newValue }
        }
    }
}
