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

// MARK: - Accessory bar (flat, like system keyboard bar)

final class AccessoryBar: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground

        // top separator line
        let line = UIView()
        line.backgroundColor = UIColor.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(isList: Bool, target: AnyObject,
                   indentSel: Selector, unindentSel: Selector,
                   separatorSel: Selector, dismissSel: Selector) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if isList {
            stack.addArrangedSubview(barButton(
                icon: "arrow.left.to.line", size: 13, target: target, action: unindentSel))
            stack.addArrangedSubview(spacer(8))
            stack.addArrangedSubview(barButton(
                icon: "arrow.right.to.line", size: 13, target: target, action: indentSel))
            stack.addArrangedSubview(spacer(16))
            stack.addArrangedSubview(barButton(
                icon: "minus", size: 13, target: target, action: separatorSel))
        }

        stack.addArrangedSubview(flexSpacer())

        stack.addArrangedSubview(barButton(
            icon: "keyboard.chevron.compact.down", size: 15, target: target, action: dismissSel))
    }

    private func barButton(icon: String, size: CGFloat, target: AnyObject, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        btn.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.secondaryLabel
        btn.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.addTarget(target, action: action, for: .touchUpInside)
        return btn
    }

    private func spacer(_ w: CGFloat) -> UIView {
        let v = UIView()
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    private func flexSpacer() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
}

// MARK: - FileEditorView

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var keyboard = KeyboardObserver()

    let initialFile: FileItem
    let tab: AppTab

    @State private var file: FileItem
    @State private var focusedItemID: UUID? = nil
    @State private var titleFocused: Bool = false
    // When true, OutlineTextField will NOT auto-focus even if focusedItemID matches
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
                if file.kind == .note {
                    noteEditor
                } else {
                    listEditor
                }
            }
            .background(Color(.systemBackground))

            // Show-keyboard FAB
            if !keyboard.isVisible {
                Button {
                    keyboardDismissed = false
                    if file.kind == .note {
                        // Note editor re-focus handled via NoteFocusTrigger
                        NotificationCenter.default.post(name: .focusNoteEditor, object: nil)
                    } else {
                        if focusedItemID == nil {
                            focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                        } else {
                            // retrigger
                            let tmp = focusedItemID
                            focusedItemID = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusedItemID = tmp
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
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: keyboard.isVisible)
        .onAppear {
            file = store.findFile(id: initialFile.id) ?? initialFile
            // No auto-focus: user taps to start editing
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text(file.dateLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(file.kind == .note ? wordCountLabel : checkCountLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Note editor

    private var noteEditor: some View {
        NoteEditorWrapper(
            text: Binding(
                get: { file.body },
                set: { file.body = $0; file.updatedAt = Date(); store.updateFile(file, tab: tab) }
            ),
            onDismiss: {
                keyboardDismissed = true
                KeyboardObserver.dismiss()
            }
        )
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
                        // move focus to first list item
                        keyboardDismissed = false
                        focusedItemID = file.listItems.first(where: { !$0.isSeparator })?.id
                            ?? addNewItem(after: nil).id
                    },
                    onDismiss: {
                        keyboardDismissed = true
                        KeyboardObserver.dismiss()
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
                                isActive: focusedItemID == item.id && !keyboardDismissed,
                                onFocus: {
                                    keyboardDismissed = false
                                    focusedItemID = item.id
                                },
                                onEnter: {
                                    let current = file.listItems[idx]
                                    if current.text.isEmpty, current.depth > 0 {
                                        file.listItems[idx].depth -= 1; save()
                                    } else {
                                        let newItem = addNewItem(after: current.id); save()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            focusedItemID = newItem.id
                                        }
                                    }
                                },
                                onIndent: {
                                    file.listItems[idx].depth = min(file.listItems[idx].depth + 1, 4); save()
                                },
                                onUnindent: {
                                    if file.listItems[idx].depth > 0 {
                                        file.listItems[idx].depth -= 1; save()
                                    } else if file.listItems[idx].text.isEmpty {
                                        let prev = prevVisibleID(before: idx, visible: visible)
                                        file.listItems.remove(at: idx); save()
                                        if let pid = prev {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                focusedItemID = pid
                                            }
                                        }
                                    }
                                },
                                onCheck: { file.listItems[idx].checked.toggle(); save() },
                                onToggleCollapse: { file.listItems[idx].isCollapsed.toggle(); save() },
                                onInsertSeparator: { insertSeparator(after: idx) },
                                onDismissKeyboard: {
                                    keyboardDismissed = true
                                    KeyboardObserver.dismiss()
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
        if let id, let idx = file.listItems.firstIndex(where: { $0.id == id }) {
            depth = file.listItems[idx].depth
            insertIndex = idx + 1
        }
        var item = ListItem(); item.depth = depth
        file.listItems.insert(item, at: insertIndex)
        return item
    }

    private func insertSeparator(after idx: Int) {
        var sep = ListItem(); sep.isSeparator = true; sep.depth = 0
        file.listItems.insert(sep, at: idx + 1)
        var blank = ListItem(); blank.depth = 0
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

    private func save() { file.updatedAt = Date(); store.updateFile(file, tab: tab) }

    private var wordCountLabel: String {
        "\(file.body.split { $0.isWhitespace }.count)w \(file.body.count)c"
    }
    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }
}

// MARK: - Notification for note re-focus

extension Notification.Name {
    static let focusNoteEditor = Notification.Name("focusNoteEditor")
}

// MARK: - NoteEditorWrapper (UITextView via UIViewRepresentable)
// Gives us full control over inputAccessoryView without SwiftUI TextEditor limitations.

struct NoteEditorWrapper: UIViewRepresentable {
    @Binding var text: String
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.backgroundColor = .systemBackground
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        tv.delegate = context.coordinator

        let bar = AccessoryBar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.configure(
            isList: false,
            target: context.coordinator,
            indentSel: #selector(Coordinator.noop),
            unindentSel: #selector(Coordinator.noop),
            separatorSel: #selector(Coordinator.noop),
            dismissSel: #selector(Coordinator.tappedDismiss)
        )
        tv.inputAccessoryView = bar

        context.coordinator.textView = tv

        // Listen for show-keyboard notification from FAB
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusFromFAB),
            name: .focusNoteEditor,
            object: nil
        )

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditorWrapper
        weak var textView: UITextView?
        init(parent: NoteEditorWrapper) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }

        @objc func tappedDismiss() { parent.onDismiss() }
        @objc func focusFromFAB() { textView?.becomeFirstResponder() }
        @objc func noop() {}
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
                Rectangle().fill(Color(.separator)).frame(height: 0.5)
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
    let onDismiss: () -> Void

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

        let bar = AccessoryBar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.configure(
            isList: false,
            target: context.coordinator,
            indentSel: #selector(Coordinator.noop),
            unindentSel: #selector(Coordinator.noop),
            separatorSel: #selector(Coordinator.noop),
            dismissSel: #selector(Coordinator.tappedDismiss)
        )
        field.inputAccessoryView = bar
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // Only sync text when NOT actively editing to avoid cursor-jump bug
        if field.text != text && !field.isFirstResponder { field.text = text }
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.tertiaryLabel,
                         .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)])
        if requestFocus && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder(); self.requestFocus = false }
        }
        // Never resignFirstResponder from here
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
        @objc func tappedDismiss() { field?.resignFirstResponder(); parent.onDismiss() }
        @objc func noop() {}
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
    let onInsertSeparator: () -> Void
    let onDismissKeyboard: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if item.depth > 0 { Spacer().frame(width: CGFloat(item.depth) * 20) }
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

        let bar = AccessoryBar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.configure(
            isList: true,
            target: context.coordinator,
            indentSel: #selector(Coordinator.tappedIndent),
            unindentSel: #selector(Coordinator.tappedUnindent),
            separatorSel: #selector(Coordinator.tappedSeparator),
            dismissSel: #selector(Coordinator.tappedDismiss)
        )
        field.inputAccessoryView = bar
        return field
    }

    func updateUIView(_ field: BackspaceAwareTextField, context: Context) {
        context.coordinator.parent = self
        field.onBackspaceAtStart = { context.coordinator.parent.onUnindent() }
        if field.text != text { field.text = text }

        field.defaultTextAttributes = isChecked
            ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
               .foregroundColor: UIColor.tertiaryLabel,
               .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)]
            : [.foregroundColor: UIColor.label,
               .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)]

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
            if let range = Range(r, in: cur) { parent.text = cur.replacingCharacters(in: range, with: s); parent.onChange() }
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

// MARK: - BackspaceAwareTextField

class BackspaceAwareTextField: UITextField {
    var onBackspaceAtStart: (() -> Void)?
    override func deleteBackward() {
        let atStart: Bool = {
            guard let r = selectedTextRange else { return false }
            return r.isEmpty && offset(from: beginningOfDocument, to: r.start) == 0
        }()
        let empty = (text ?? "").isEmpty
        if atStart || empty { onBackspaceAtStart?(); if empty { return } }
        super.deleteBackward()
    }
}

// MARK: - FileItem extensions

extension FileItem {
    var autoTitle: String {
        listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isSeparator })?.text ?? "Untitled"
    }
}
