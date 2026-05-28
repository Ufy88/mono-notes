import SwiftUI
import UIKit
import Combine

// MARK: - Keyboard visibility helper

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

    func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - FileEditorView

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var keyboard = KeyboardObserver()

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
        ZStack(alignment: .bottomTrailing) {
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

            // Show-keyboard FAB — only when keyboard hidden
            if !keyboard.isVisible {
                Button {
                    // re-focus last active field
                    if file.kind == .note {
                        textFocused = true
                    } else if let id = focusedItemID {
                        // trigger re-focus by toggling
                        let tmp = focusedItemID
                        focusedItemID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedItemID = tmp }
                        _ = id
                    } else {
                        focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .medium))
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
                        focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
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
        // inject dismiss-only accessory for notes
        .onAppear { injectNoteAccessory() }
    }

    // MARK: - List editor

    private var listEditor: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                TitleTextField(
                    text: Binding(
                        get: { file.title },
                        set: { file.title = $0; save() }
                    ),
                    placeholder: file.autoTitle,
                    requestFocus: $titleFocused,
                    onReturn: {
                        titleFocused = false
                        focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                            ?? addNewItem(after: nil).id
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().padding(.horizontal, 16).padding(.bottom, 4)

                let visible = file.visibleItemIDs()
                ForEach(file.listItems.indices, id: \.self) { idx in
                    let item = file.listItems[idx]
                    if visible.contains(item.id) {
                        if item.isSeparator {
                            SeparatorRow(
                                blockCollapsed: item.blockCollapsed,
                                preview: file.blockPreview(before: item.id),
                                onToggle: {
                                    file.listItems[idx].blockCollapsed.toggle()
                                    save()
                                }
                            )
                        } else {
                            OutlineItemRow(
                                item: $file.listItems[idx],
                                hasChildren: file.hasChildren(after: item),
                                isActive: focusedItemID == item.id,
                                isList: true,
                                keyboardVisible: keyboard.isVisible,
                                onFocus: { focusedItemID = item.id },
                                onEnter: {
                                    let current = file.listItems[idx]
                                    if current.text.isEmpty, current.depth > 0 {
                                        file.listItems[idx].depth -= 1
                                        save()
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
                                onInsertSeparator: {
                                    insertSeparator(after: idx)
                                },
                                onDismissKeyboard: {
                                    keyboard.dismiss()
                                },
                                onChange: { save() }
                            )
                        }
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

    private func insertSeparator(after idx: Int) {
        // Insert separator after current row, then a blank row after the separator
        var sep = ListItem()
        sep.isSeparator = true
        sep.depth = 0
        file.listItems.insert(sep, at: idx + 1)
        var blank = ListItem()
        blank.depth = 0
        file.listItems.insert(blank, at: idx + 2)
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedItemID = blank.id
        }
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

    private func save() {
        file.updatedAt = Date()
        store.updateFile(file, tab: tab)
    }

    private var wordCountLabel: String {
        let words = file.body.split { $0.isWhitespace }.count
        return "\(words)w \(file.body.count)c"
    }

    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }

    // Inject a minimal accessory bar (dismiss only) for the note TextEditor
    private func injectNoteAccessory() {
        // We can't easily attach UIToolbar to SwiftUI TextEditor without UIViewRepresentable.
        // Instead we rely on the FAB button for keyboard dismiss in notes.
        // Nothing to inject here — kept as extension point.
    }
}

// MARK: - SeparatorRow

struct SeparatorRow: View {
    let blockCollapsed: Bool
    let preview: String
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if blockCollapsed {
                // show preview of collapsed block
                HStack(spacing: 6) {
                    Text(preview)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onToggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                Button(action: onToggle) {
                    Image(systemName: blockCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - TitleTextField

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
        // Accessory: dismiss only (no indent buttons for title)
        field.inputAccessoryView = makeDismissBar(target: context.coordinator,
                                                  action: #selector(Coordinator.tappedDismiss),
                                                  isList: false,
                                                  separatorTarget: nil,
                                                  separatorAction: nil)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text && !field.isFirstResponder { field.text = text }
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.tertiaryLabel,
                         .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)])
        if requestFocus && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder(); self.requestFocus = false }
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TitleTextField
        weak var field: UITextField?
        init(parent: TitleTextField) { self.parent = parent }

        func textField(_ tf: UITextField, shouldChangeCharactersIn r: NSRange, replacementString s: String) -> Bool {
            let cur = tf.text ?? ""
            if let range = Range(r, in: cur) { parent.text = cur.replacingCharacters(in: range, with: s) }
            return true
        }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            tf.resignFirstResponder(); parent.onReturn(); return false
        }
        @objc func tappedDismiss() { field?.resignFirstResponder() }
    }
}

// MARK: - Shared accessory bar factory

func makeDismissBar(
    target: AnyObject,
    action: Selector,
    isList: Bool,
    separatorTarget: AnyObject?,
    separatorAction: Selector?
) -> UIToolbar {
    let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
    bar.barTintColor = UIColor.secondarySystemBackground
    bar.isTranslucent = false

    var items: [UIBarButtonItem] = []

    if isList {
        let unindent = UIBarButtonItem(
            image: UIImage(systemName: "arrow.left.to.line")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            style: .plain, target: target,
            action: NSSelectorFromString("tappedUnindent"))
        let gap = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        gap.width = 4
        let indent = UIBarButtonItem(
            image: UIImage(systemName: "arrow.right.to.line")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            style: .plain, target: target,
            action: NSSelectorFromString("tappedIndent"))

        let gap2 = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        gap2.width = 12

        let sepBtn = UIBarButtonItem(
            image: UIImage(systemName: "minus")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            style: .plain, target: separatorTarget,
            action: separatorAction)

        items += [unindent, gap, indent, gap2, sepBtn]
    }

    let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    let dismiss = UIBarButtonItem(
        image: UIImage(systemName: "keyboard.chevron.compact.down")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
        style: .plain, target: target, action: action)

    items += [flex, dismiss]
    bar.items = items
    return bar
}

// MARK: - FileItem auto-title helper

extension FileItem {
    var autoTitle: String {
        let first = listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isSeparator })
        return first?.text ?? "Untitled"
    }
}

// MARK: - OutlineItemRow

struct OutlineItemRow: View {
    @Binding var item: ListItem
    let hasChildren: Bool
    let isActive: Bool
    let isList: Bool
    let keyboardVisible: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onCheck: () -> Void
    let onToggleCollapse: () -> Void
    let onInsertSeparator: () -> Void
    let onDismissKeyboard: () -> Void
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
                isList: isList,
                onFocus: onFocus,
                onEnter: onEnter,
                onIndent: onIndent,
                onUnindent: onUnindent,
                onInsertSeparator: onInsertSeparator,
                onDismissKeyboard: onDismissKeyboard,
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

// MARK: - OutlineTextField

struct OutlineTextField: UIViewRepresentable {
    @Binding var text: String
    let isActive: Bool
    let isChecked: Bool
    let isList: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onInsertSeparator: () -> Void
    let onDismissKeyboard: () -> Void
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

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
        field.onBackspaceAtStart = { context.coordinator.parent.onUnindent() }

        field.inputAccessoryView = makeDismissBar(
            target: context.coordinator,
            action: #selector(Coordinator.tappedDismiss),
            isList: isList,
            separatorTarget: context.coordinator,
            separatorAction: #selector(Coordinator.tappedSeparator)
        )
        return field
    }

    func updateUIView(_ field: BackspaceAwareTextField, context: Context) {
        context.coordinator.parent = self
        field.onBackspaceAtStart = { context.coordinator.parent.onUnindent() }
        if field.text != text { field.text = text }

        let attrs: [NSAttributedString.Key: Any] = isChecked
            ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
               .foregroundColor: UIColor.tertiaryLabel,
               .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)]
            : [.foregroundColor: UIColor.label,
               .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)]
        field.defaultTextAttributes = attrs

        if isActive && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OutlineTextField
        init(parent: OutlineTextField) { self.parent = parent }

        func textField(_ tf: UITextField, shouldChangeCharactersIn r: NSRange, replacementString s: String) -> Bool {
            let cur = tf.text ?? ""
            if let range = Range(r, in: cur) {
                parent.text = cur.replacingCharacters(in: range, with: s)
                parent.onChange()
            }
            return true
        }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool { parent.onEnter(); return false }
        func textFieldDidBeginEditing(_ tf: UITextField) { parent.onFocus() }

        @objc func tappedIndent() { parent.onIndent() }
        @objc func tappedUnindent() { parent.onUnindent() }
        @objc func tappedDismiss() { parent.onDismissKeyboard() }
        @objc func tappedSeparator() { parent.onInsertSeparator() }
    }
}

// MARK: - UITextField subclass with backspace detection

class BackspaceAwareTextField: UITextField {
    var onBackspaceAtStart: (() -> Void)?

    override func deleteBackward() {
        let atStart: Bool = {
            guard let r = selectedTextRange else { return false }
            return r.isEmpty && offset(from: beginningOfDocument, to: r.start) == 0
        }()
        let empty = (text ?? "").isEmpty
        if atStart || empty {
            onBackspaceAtStart?()
            if empty { return }
        }
        super.deleteBackward()
    }
}
