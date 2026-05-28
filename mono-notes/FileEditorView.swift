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
    @State private var titleFocused: Bool = false

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
        .font(.system(.footnote, design: .monospaced).weight(.medium))
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

                // ── Title field ──
                TitleTextField(
                    text: Binding(
                        get: { file.title },
                        set: { file.title = $0; save() }
                    ),
                    placeholder: file.autoTitle,
                    requestFocus: $titleFocused,
                    onReturn: {
                        titleFocused = false
                        focusedItemID = file.listItems.isEmpty
                            ? addNewItem(after: nil).id
                            : file.listItems.first?.id
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().padding(.horizontal, 16).padding(.bottom, 4)

                // ── Rows ──
                let visible = file.visibleItemIDs()
                ForEach(file.listItems.indices, id: \.self) { idx in
                    let item = file.listItems[idx]
                    if visible.contains(item.id) {
                        OutlineItemRow(
                            item: $file.listItems[idx],
                            hasChildren: file.hasChildren(after: item),
                            isActive: focusedItemID == item.id,
                            onFocus: { focusedItemID = item.id },
                            onEnter: {
                                let current = file.listItems[idx]
                                if current.text.isEmpty {
                                    if current.depth > 0 {
                                        file.listItems[idx].depth -= 1
                                        save()
                                    }
                                } else {
                                    let newItem = addNewItem(after: current.id)
                                    save()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        focusedItemID = newItem.id
                                    }
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
                                    let prevVisible = prevVisibleID(before: idx, visible: visible)
                                    file.listItems.remove(at: idx)
                                    save()
                                    if let pid = prevVisible {
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
                            onToggleCollapse: {
                                file.listItems[idx].isCollapsed.toggle()
                                save()
                            },
                            onChange: { save() }
                        )
                    }
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

    private func prevVisibleID(before idx: Int, visible: Set<UUID>) -> UUID? {
        guard idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if visible.contains(file.listItems[i].id) { return file.listItems[i].id }
        }
        return nil
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

// MARK: - TitleTextField
// requestFocus is a one-shot signal: setting it true causes becomeFirstResponder.
// Focus is NEVER resigned from updateUIView — only from onReturn or user tap elsewhere.

struct TitleTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var requestFocus: Bool
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
        field.returnKeyType = .next
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self

        // Only sync text when it differs AND field is not being actively edited
        // (avoids clobbering cursor position mid-typing)
        if field.text != text && !field.isFirstResponder {
            field.text = text
        }

        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.tertiaryLabel,
                .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
            ]
        )

        // requestFocus = true → grab focus, then reset the flag
        if requestFocus && !field.isFirstResponder {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
                self.requestFocus = false
            }
        }
        // Never call resignFirstResponder here
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TitleTextField
        weak var field: UITextField?

        init(parent: TitleTextField) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            if let r = Range(range, in: current) {
                parent.text = current.replacingCharacters(in: r, with: string)
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onReturn()
            return false
        }
    }
}

// MARK: - FileItem auto-title helper

extension FileItem {
    var autoTitle: String {
        let first = listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        return first?.text ?? "Untitled"
    }
}

// MARK: - OutlineItemRow

struct OutlineItemRow: View {
    @Binding var item: ListItem
    let hasChildren: Bool
    let isActive: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onCheck: () -> Void
    let onToggleCollapse: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 20)
            }

            Text("\u{2022}")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 22, alignment: .center)
                .onTapGesture { onCheck() }

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
            .frame(minHeight: 32)

            if hasChildren {
                Button(action: onToggleCollapse) {
                    Image(systemName: item.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
        field.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
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

        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 52))
        bar.barTintColor = UIColor.secondarySystemBackground
        bar.isTranslucent = false
        let unindentBtn = UIBarButtonItem(image: UIImage(systemName: "arrow.left.to.line"),
                                          style: .plain, target: context.coordinator,
                                          action: #selector(Coordinator.tappedUnindent))
        let indentBtn = UIBarButtonItem(image: UIImage(systemName: "arrow.right.to.line"),
                                        style: .plain, target: context.coordinator,
                                        action: #selector(Coordinator.tappedIndent))
        let gap = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        gap.width = 20
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        bar.items = [unindentBtn, gap, indentBtn, flex]
        field.inputAccessoryView = bar
        return field
    }

    func updateUIView(_ field: BackspaceAwareTextField, context: Context) {
        context.coordinator.parent = self
        field.onBackspaceAtStart = { context.coordinator.parent.onUnindent() }

        if field.text != text { field.text = text }

        if isChecked {
            field.defaultTextAttributes = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: UIColor.tertiaryLabel,
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
            ]
        } else {
            field.defaultTextAttributes = [
                .foregroundColor: UIColor.label,
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
            ]
        }

        if isActive && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OutlineTextField
        init(parent: OutlineTextField) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            if let r = Range(range, in: current) {
                parent.text = current.replacingCharacters(in: r, with: string)
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
        let cursorAtStart: Bool = {
            guard let range = selectedTextRange else { return false }
            return range.isEmpty && offset(from: beginningOfDocument, to: range.start) == 0
        }()
        let isEmpty = (text ?? "").isEmpty

        if cursorAtStart || isEmpty {
            onBackspaceAtStart?()
            if isEmpty { return }
        }
        super.deleteBackward()
    }
}
