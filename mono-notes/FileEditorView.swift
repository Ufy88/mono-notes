import SwiftUI

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @FocusState private var textFocused: Bool
    @FocusState private var newItemFocused: Bool
    @State private var newItemText = ""

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
                if file.kind == .note { textFocused = true }
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
                    .animation(.none, value: wordCountLabel)
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
                ForEach($file.listItems) { $item in
                    ListItemRow(item: $item, onDelete: {
                        file.listItems.removeAll { $0.id == item.id }
                        file.updatedAt = Date()
                        store.updateFile(file, tab: tab)
                    }, onChange: {
                        file.updatedAt = Date()
                        store.updateFile(file, tab: tab)
                    })
                }

                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20)
                    TextField("new item", text: $newItemText)
                        .font(.system(.body, design: .monospaced))
                        .focused($newItemFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { commitNewItem() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .padding(.bottom, 80)
        }
    }

    // MARK: - Helpers

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

    private func commitNewItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { newItemFocused = false; return }
        let item = ListItem(text: text)
        file.listItems.append(item)
        file.updatedAt = Date()
        store.updateFile(file, tab: tab)
        newItemText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { newItemFocused = true }
    }
}

// MARK: - List item row

struct ListItemRow: View {
    @Binding var item: ListItem
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                item.checked.toggle()
                onChange()
            } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            .frame(width: 20)

            TextField("", text: Binding(
                get: { item.text },
                set: { item.text = $0; onChange() }
            ))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(item.checked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .strikethrough(item.checked, color: Color(.tertiaryLabel))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
