import SwiftUI
import UIKit

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

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 20)
            }

            // Bullet — bolder middle dot
            Text("\u{2022}")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 24, alignment: .center)
                .onTapGesture { onCheck() }

            // UIKit-backed text field to intercept backspace
            OutlineTextField(
                text: $item.text,
                isActive: isActive,
                isChecked: item.checked,
                onFocus: onFocus,
                onEnter: onEnter,
                onIndent: onIndent,
                onUnindent: onUnindent,
                onChange: onChange
            )
            .frame(minHeight: 36)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - OutlineTextField (UIViewRepresentable)

struct OutlineTextField: UIViewRepresentable {
    @Binding var text: String
    let isActive: Bool
    let isChecked: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> BackspaceAwareTextField {
        let field = BackspaceAwareTextField()
        field.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .next
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        field.onBackspaceAtStart = {
            context.coordinator.parent.onUnindent()
        }

        // Keyboard toolbar
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let unindentBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.left.to.line"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.tappedUnindent)
        )
        let indentBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.right.to.line"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.tappedIndent)
        )
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [unindentBtn, indentBtn, flex]
        field.inputAccessoryView = toolbar

        return field
    }

    func updateUIView(_ field: BackspaceAwareTextField, context: Context) {
        context.coordinator.parent = self
        field.onBackspaceAtStart = { context.coordinator.parent.onUnindent() }

        if field.text != text {
            field.text = text
        }

        // Strike-through for checked items
        if isChecked {
            let attrs: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: UIColor.tertiaryLabel,
                .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
            ]
            field.defaultTextAttributes = attrs
        } else {
            field.defaultTextAttributes = [
                .foregroundColor: UIColor.label,
                .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
            ]
        }

        // Focus management
        if isActive && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OutlineTextField

        init(parent: OutlineTextField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            if let r = Range(range, in: current) {
                let updated = current.replacingCharacters(in: r, with: string)
                parent.text = updated
                parent.onChange()
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onEnter()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocus()
        }

        @objc func tappedIndent() { parent.onIndent() }
        @objc func tappedUnindent() { parent.onUnindent() }
    }
}

// MARK: - UITextField subclass with backspace detection

class BackspaceAwareTextField: UITextField {
    var onBackspaceAtStart: (() -> Void)?

    override func deleteBackward() {
        // Fire BEFORE super so text is still empty/cursor at 0
        let cursorAtStart: Bool = {
            guard let range = selectedTextRange else { return false }
            return range.isEmpty && offset(from: beginningOfDocument, to: range.start) == 0
        }()
        let isEmpty = (text ?? "").isEmpty

        if cursorAtStart || isEmpty {
            onBackspaceAtStart?()
            // If text was empty, don't call super (nothing to delete)
            if isEmpty { return }
        }
        super.deleteBackward()
    }
}
