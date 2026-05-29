import SwiftUI
import UIKit

// MARK: - AccessoryBar

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

// MARK: - HideReorderHandlesProxy
// Hides the three-line drag handle image inside UITableViewCellReorderControl
// while keeping the control itself alive so long-press drag still works.

struct HideReorderHandlesProxy: UIViewRepresentable {
    func makeUIView(context: Context) -> HideHandlesView { HideHandlesView() }
    func updateUIView(_ uiView: HideHandlesView, context: Context) {
        DispatchQueue.main.async {
            guard let tableView = uiView.nearestAncestor(ofType: UITableView.self) else { return }
            uiView.attach(to: tableView)
        }
    }
}

final class HideHandlesView: UIView {
    private weak var tableView: UITableView?
    private var displayLink: CADisplayLink?

    func attach(to tableView: UITableView) {
        guard self.tableView !== tableView else { return }
        self.tableView = tableView
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60)
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    @objc private func tick() {
        tableView?.visibleCells.forEach { hideHandleImage(in: $0) }
    }

    // Walk the view hierarchy. When we find UITableViewCellReorderControl,
    // hide only its UIImageView children (the three-line icon) — NOT the
    // control itself, so the long-press drag gesture remains functional.
    private func hideHandleImage(in view: UIView) {
        let className = NSStringFromClass(type(of: view))
        if className == "UITableViewCellReorderControl" {
            for sub in view.subviews where sub is UIImageView {
                if !sub.isHidden { sub.isHidden = true }
            }
            return
        }
        view.subviews.forEach { hideHandleImage(in: $0) }
    }

    override func removeFromSuperview() {
        displayLink?.invalidate()
        displayLink = nil
        super.removeFromSuperview()
    }
}

// MARK: - UIView hierarchy helper

extension UIView {
    func nearestAncestor<T: UIView>(ofType type: T.Type) -> T? {
        var v: UIView? = superview
        while let current = v {
            if let match = current as? T { return match }
            v = current.superview
        }
        return nil
    }
}

// MARK: - NoteEditorWrapper

struct NoteEditorWrapper: UIViewRepresentable {
    @Binding var text: String
    @Binding var focusRequest: Bool
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
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        if focusRequest && !tv.isFirstResponder {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
                self.focusRequest = false
            }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditorWrapper
        weak var textView: UITextView?
        init(parent: NoteEditorWrapper) { self.parent = parent }
        func textViewDidChange(_ tv: UITextView) { parent.text = tv.text }
        @objc func tappedDismiss() { parent.onDismiss() }
        @objc func noop() {}
    }
}

// MARK: - SeparatorRow

struct SeparatorRow: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
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
    let onDeleteSeparatorAbove: () -> Bool
    let onCheck: () -> Void
    let onToggleCollapse: () -> Void
    let onInsertSeparator: () -> Void
    let onDismissKeyboard: () -> Void
    let onChange: () -> Void
    let onDragBegan: () -> Void

    @State private var textHeight: CGFloat = 22

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
                .padding(.top, 2)
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
                onDeleteSeparatorAbove: onDeleteSeparatorAbove,
                onInsertSeparator: onInsertSeparator,
                onDismissKeyboard: onDismissKeyboard,
                onChange: onChange,
                onHeightChange: { h in
                    if abs(h - textHeight) > 0.5 { textHeight = h }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: textHeight)
            if hasChildren {
                Button(action: onToggleCollapse) {
                    Image(systemName: item.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                        .frame(width: chevronWidth, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 1)
            } else {
                Color.clear.frame(width: chevronWidth, height: 1)
            }
        }
        .padding(.horizontal, 16)
        // Reduced from 1 to 0 — spacing between rows comes only from
        // textContainerInset in GrowingTextView (top:2, bottom:2).
        .padding(.vertical, 0)
        .contentShape(Rectangle())
        .onDrag {
            onDragBegan()
            return NSItemProvider()
        }
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
    let onDeleteSeparatorAbove: () -> Bool
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
        // Reduced vertical inset from 3 to 2 for tighter row spacing.
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFocusItem(_:)),
            name: EditorNotification.focusItem(.init()).name,
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
        coordinator?.textView = self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportHeight()
    }

    private func reportHeight() {
        guard bounds.width > 0 else { return }
        let fittingSize = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let h = max(fittingSize.height, 22)
        coordinator?.parent.onHeightChange(h)
    }

    override func deleteBackward() {
        let atStart: Bool = {
            guard let r = selectedTextRange else { return false }
            return r.isEmpty && offset(from: beginningOfDocument, to: r.start) == 0
        }()
        if atStart && text.isEmpty {
            let separatorDeleted = coordinator?.parent.onDeleteSeparatorAbove() ?? false
            if !separatorDeleted { coordinator?.parent.onUnindent() }
            return
        }
        if atStart && !text.isEmpty { coordinator?.parent.onUnindent() }
        if !text.isEmpty { super.deleteBackward() }
    }
}

// MARK: - FileItem local extension

extension FileItem {
    var autoTitle: String { displayTitle }
}
