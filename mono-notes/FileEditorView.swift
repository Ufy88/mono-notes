import SwiftUI

// MARK: - Focus ID

struct ListFocusID: Hashable {
    let id: UUID
}

// MARK: - FileEditorView

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @FocusState private var textFocused: Bool
    @FocusState private var focusedItem: ListFocusID?

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
                } else if let first = file.listItems.first {
                    focusedItem = ListFocusID(id: first.id)
                } else {
                    let item = addNewItem(after: nil)
                    focusedItem = ListFocusID(id: item.id)
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
                        onEnter: {
                            let newItem = addNewItem(after: file.listItems[idx].id)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusedItem = ListFocusID(id: newItem.id)
                            }
                            save()
                        },
                        onIndent: {
                            // Arrow right → increase depth (max 4)
                            file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4)
                            save()
                        },
                        onUnindent: {
                            // Arrow left or backspace at start of empty line → decrease depth
                            if file.listItems[idx].depth > 0 {
                                file.listItems[idx].depth -= 1
                                save()
                            } else {
                                // depth==0 and text empty → delete row, focus previous
                                let prevID = idx > 0 ? file.listItems[idx - 1].id : nil
                                file.listItems.remove(at: idx)
                                save()
                                if let pid = prevID {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        focusedItem = ListFocusID(id: pid)
                                    }
                                }
                            }
                        },
                        onDeleteEmpty: {
                            // backspace on empty item at depth 0 → delete, go to previous
                            let prevID = idx > 0 ? file.listItems[idx - 1].id : nil
                            file.listItems.remove(at: idx)
                            save()
                            if let pid = prevID {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    focusedItem = ListFocusID(id: pid)
                                }
                            }
                        },
                        onCheck: {
                            file.listItems[idx].checked.toggle()
                            save()
                        },
                        onChange: { save() },
                        isFocused: Binding(
                            get: { focusedItem == ListFocusID(id: file.listItems[idx].id) },
                            set: { if $0 { focusedItem = ListFocusID(id: file.listItems[idx].id) } }
                        )
                    )
                }
            }
            .padding(.bottom, 120)
        }
        .onTapGesture {
            // Tap on empty space below items → append new item
            let item = addNewItem(after: file.listItems.last?.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedItem = ListFocusID(id: item.id)
            }
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
        let item = ListItem(depth: depth)
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
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onDeleteEmpty: () -> Void
    let onCheck: () -> Void
    let onChange: () -> Void
    @Binding var isFocused: Bool

    // Track cursor position via a local string to detect "at start"
    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Indent spacer
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 20)
            }

            // Bullet dot
            Text("·")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)
                .onTapGesture { onCheck() }

            // Text field
            TextField("", text: $text, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .strikethrough(item.checked, color: Color(.tertiaryLabel))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused(Binding(
                    get: { isFocused },
                    set: { isFocused = $0 }
                ))
                .onChange(of: text) { _, newValue in
                    item.text = newValue
                    onChange()
                }
                .onSubmit { onEnter() }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        // Only show when this row is focused
                        if isFocused {
                            Button {
                                onUnindent()
                            } label: {
                                Image(systemName: "arrow.left.to.line")
                            }
                            Button {
                                onIndent()
                            } label: {
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
        .onAppear { text = item.text }
        .onChange(of: item.text) { _, newValue in
            if text != newValue { text = newValue }
        }
        // Backspace at empty → unindent or delete
        .background(
            KeyboardResponder(text: $text, onBackspaceAtStart: {
                if item.depth > 0 {
                    onUnindent()
                } else if text.isEmpty {
                    onDeleteEmpty()
                }
            })
        )
    }
}

// MARK: - UIKit keyboard hook for backspace detection

struct KeyboardResponder: UIViewRepresentable {
    @Binding var text: String
    let onBackspaceAtStart: () -> Void

    func makeUIView(context: Context) -> BackspaceTextField {
        let field = BackspaceTextField()
        field.delegate = context.coordinator
        field.onBackspaceAtStart = onBackspaceAtStart
        field.isHidden = true
        return field
    }

    func updateUIView(_ uiView: BackspaceTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, UITextFieldDelegate {}
}

class BackspaceTextField: UITextField {
    var onBackspaceAtStart: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty == true || selectedTextRange?.isEmpty == true && offset(from: beginningOfDocument, to: selectedTextRange!.start) == 0 {
            onBackspaceAtStart?()
        }
        super.deleteBackward()
    }
}
