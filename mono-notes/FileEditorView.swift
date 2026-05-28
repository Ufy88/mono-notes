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
    // Payload: userInfo["id"] = UUID  — tells the matching GrowingTextView to becomeFirstResponder
    // without going through SwiftUI state (avoids keyboard flicker).
    static let focusItem        = Notification.Name("focusItem")
}

// MARK: - Flat accessory bar

final class AccessoryBar: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground
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
            stack.addArrangedSubview(barBtn("arrow.left.to.line", 13, target, unindentSel))
            stack.addArrangedSubview(gap(8))
            stack.addArrangedSubview(barBtn("arrow.right.to.line", 13, target, indentSel))
            stack.addArrangedSubview(gap(16))
            stack.addArrangedSubview(barBtn("minus", 13, target, separatorSel))
        }
        stack.addArrangedSubview(flex())
        stack.addArrangedSubview(barBtn("keyboard.chevron.compact.down", 15, target, dismissSel))
    }

    private func barBtn(_ icon: String, _ size: CGFloat, _ target: AnyObject, _ sel: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)), for: .normal)
        btn.tintColor = UIColor.secondaryLabel
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.addTarget(target, action: sel, for: .touchUpInside)
        return btn
    }
    private func gap(_ w: CGFloat) -> UIView {
        let v = UIView(); v.widthAnchor.constraint(equalToConstant: w).isActive = true; return v
    }
    private func flex() -> UIView {
        let v = UIView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v
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
    private var listEditor: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                Divider().padding(.horizontal, 16).padding(.bottom, 4)

                let visible = file.visibleItemIDs()

                ForEach($file.listItems, id: \.id) { $item in
                    if visible.contains(item.id) {
                        if item.isSeparator {
                            let idx = file.listItems.firstIndex(where: { $0.id == item.id }) ?? 0
                            SeparatorRow(
                                blockCollapsed: item.blockCollapsed,
                                preview: file.blockPreview(before: item.id),
                                onToggle: { file.listItems[idx].blockCollapsed.toggle(); save() }
                            )
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
                                onCheck: { file.listItems[idx].checked.toggle(); save() },
                                onToggleCollapse: { file.listItems[idx].isCollapsed.toggle(); save() },
                                onInsertSeparator: { insertSeparator(after: idx) },
                                onDismissKeyboard: { keyboardDismissed = true; KeyboardObserver.dismiss() },
                                onChange: { save() }
                            )
                        }
                    }
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
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Enter handling
    private func handleEnter(at idx: Int) {
        let current = file.listItems[idx]
        let isEmpty = current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            if current.depth > 0 { file.listItems[idx].depth -= 1; save() }
            return
        }
        let newItem = addNewItem(after: current.id)
        save()
        // New row — it doesn't exist yet in the view hierarchy, so we must go through focusedItemID.
        focusedItemID = newItem.id
    }

    private func handleUnindent(at idx: Int, visible: Set<UUID>) {
        if file.listItems[idx].depth > 0 {
            file.listItems[idx].depth -= 1; save()
            return
        }
        guard file.listItems[idx].text.isEmpty else { return }

        // Find the previous visible non-separator item BEFORE removing from the array,
        // so the index is still valid.
        let prevID = prevVisibleID(before: idx, visible: visible)
        file.listItems.remove(at: idx)
        save()

        if let pid = prevID {
            // Stay on the same focusedItemID if it's already that row — the UITextView
            // for that row is still alive and first-responder status hasn't changed.
            // Post a direct notification so GrowingTextView can grab focus without
            // SwiftUI tearing down and rebuilding anything (no keyboard flicker).
            focusedItemID = pid
            NotificationCenter.default.post(
                name: .focusItem,
                object: nil,
                userInfo: ["id": pid]
            )
        }
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

    private func save() { file.updatedAt = Date(); store.updateFile(file, tab: tab) }

    private var wordCountLabel: String {
        "\(file.body.split { $0.isWhitespace }.count)w \(file.body.count)c"
    }
    private var checkCountLabel: String {
        let items = file.listItems.filter { !$0.isSeparator }
        return "\(items.filter(\.checked).count)/\(items.count)"
    }
}

// MARK: - NoteEditorWrapper
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
        bar.configure(isList: false, target: context.coordinator,
                      indentSel: #selector(Coordinator.noop), unindentSel: #selector(Coordinator.noop),
                      separatorSel: #selector(Coordinator.noop), dismissSel: #selector(Coordinator.tappedDismiss))
        tv.inputAccessoryView = bar
        context.coordinator.textView = tv
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.focusFromFAB),
                                               name: .focusNoteEditor, object: nil)
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
        func textViewDidChange(_ tv: UITextView) { parent.text = tv.text }
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
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onToggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                Rectangle().fill(Color(.separator)).frame(height: 0.5)
                Button(action: onToggle) {
                    Image(systemName: blockCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                        .frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 4)
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
        bar.configure(isList: false, target: context.coordinator,
                      indentSel: #selector(Coordinator.noop), unindentSel: #selector(Coordinator.noop),
                      separatorSel: #selector(Coordinator.noop), dismissSel: #selector(Coordinator.tappedDismiss))
        field.inputAccessoryView = bar
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text && !field.isFirstResponder { field.text = text }
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: UIColor.tertiaryLabel,
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
        func textFieldShouldReturn(_ tf: UITextField) -> Bool { tf.resignFirstResponder(); parent.onReturn(); return false }
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

    @State private var textHeight: CGFloat = 32

    private var indentWidth: CGFloat { CGFloat(item.depth) * 20 }
    private let bulletWidth: CGFloat = 22
    private let chevronWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if item.depth > 0 {
                Color.clear.frame(width: indentWidth, height: 1)
            }

            Text("\u{2022}")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(item.checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: bulletWidth, alignment: .center)
                .padding(.top, 3)
                .onTapGesture { onCheck() }

            OutlineTextView(
                text: $item.text,
                itemID: item.id,
                isActive: isActive,
                isChecked: item.checked,
                onFocus: onFocus,
                onEnter: onEnter,
                onIndent: onIndent,
                onUnindent: onUnindent,
                onInsertSeparator: onInsertSeparator,
                onDismissKeyboard: onDismissKeyboard,
                onChange: onChange,
                onHeightChange: { h in
                    if abs(h - textHeight) > 0.5 { textHeight = h }
                }
            )
            .frame(maxWidth: .infinity, minHeight: textHeight, maxHeight: textHeight)

            if hasChildren {
                Button(action: onToggleCollapse) {
                    Image(systemName: item.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                        .frame(width: chevronWidth, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 1)
            } else {
                Color.clear.frame(width: chevronWidth, height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - OutlineTextView

struct OutlineTextView: UIViewRepresentable {
    @Binding var text: String
    let itemID: UUID
    let isActive: Bool
    let isChecked: Bool
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onIndent: () -> Void
    let onUnindent: () -> Void
    let onInsertSeparator: () -> Void
    let onDismissKeyboard: () -> Void
    let onChange: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> GrowingTextView {
        let tv = GrowingTextView()
        tv.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.returnKeyType = .next
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bar = AccessoryBar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.configure(isList: true, target: context.coordinator,
                      indentSel: #selector(Coordinator.tappedIndent),
                      unindentSel: #selector(Coordinator.tappedUnindent),
                      separatorSel: #selector(Coordinator.tappedSeparator),
                      dismissSel: #selector(Coordinator.tappedDismiss))
        tv.inputAccessoryView = bar

        // Register for direct-focus notification (used when deleting a bullet row).
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFocusItem(_:)),
            name: .focusItem,
            object: nil
        )

        return tv
    }

    func updateUIView(_ tv: GrowingTextView, context: Context) {
        context.coordinator.parent = self
        tv.coordinator = context.coordinator

        if tv.text != text { tv.text = text }

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 1
        let attrs: [NSAttributedString.Key: Any] = isChecked
            ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
               .foregroundColor: UIColor.tertiaryLabel,
               .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium),
               .paragraphStyle: paraStyle]
            : [.foregroundColor: UIColor.label,
               .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium),
               .paragraphStyle: paraStyle]

        let newAttr = NSAttributedString(string: tv.text, attributes: attrs)
        if tv.attributedText != newAttr { tv.attributedText = newAttr }

        // Only call becomeFirstResponder when SwiftUI explicitly marks this row active.
        // Do NOT resign here — that's what causes the flicker. Resigning is only done
        // via explicit user action (dismiss button, sidebar open).
        if isActive && !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: OutlineTextView
        weak var textView: GrowingTextView?
        init(parent: OutlineTextView) { self.parent = parent }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" { parent.onEnter(); return false }
            return true
        }
        func textViewDidChange(_ tv: UITextView) {
            if parent.text != tv.text { parent.text = tv.text; parent.onChange() }
        }
        func textViewDidBeginEditing(_ tv: UITextView) { parent.onFocus() }

        // Called by .focusItem notification. Grabs focus directly on the UITextView
        // that matches our itemID — no SwiftUI state change, no keyboard dismiss.
        @objc func handleFocusItem(_ note: Notification) {
            guard let id = note.userInfo?["id"] as? UUID,
                  id == parent.itemID,
                  let tv = textView,
                  !tv.isFirstResponder
            else { return }
            tv.becomeFirstResponder()
        }

        @objc func tappedIndent() { parent.onIndent() }
        @objc func tappedUnindent() { parent.onUnindent() }
        @objc func tappedDismiss() { parent.onDismissKeyboard() }
        @objc func tappedSeparator() { parent.onInsertSeparator() }
    }
}

// MARK: - GrowingTextView

class GrowingTextView: UITextView {
    weak var coordinator: OutlineTextView.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Store weak ref so Coordinator.handleFocusItem can reach us.
        coordinator?.textView = self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportHeight()
    }

    private func reportHeight() {
        guard bounds.width > 0 else { return }
        let fittingSize = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let h = max(fittingSize.height, 32)
        coordinator?.parent.onHeightChange(h)
    }

    override func deleteBackward() {
        let atStart: Bool = {
            guard let r = selectedTextRange else { return false }
            return r.isEmpty && offset(from: beginningOfDocument, to: r.start) == 0
        }()
        if atStart { coordinator?.parent.onUnindent() }
        if !text.isEmpty { super.deleteBackward() }
    }
}

// MARK: - FileItem extensions
extension FileItem {
    var autoTitle: String {
        listItems.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isSeparator })?.text ?? "Untitled"
    }
}
