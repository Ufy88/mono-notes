import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    let note: Note
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .scrollContentBackground(.hidden)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("done") { saveAndDismiss() }
                            .font(.system(.body, design: .monospaced))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text(timestamp)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            text = note.body
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focused = true
            }
        }
        .onChange(of: text) { _, newValue in
            var updated = note
            updated.body = newValue
            store.update(updated)
        }
    }

    private var timestamp: String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yy HH:mm"
        return df.string(from: note.updatedAt)
    }

    private func saveAndDismiss() {
        var updated = note
        updated.body = text
        store.update(updated)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let idx = store.notes.firstIndex(where: { $0.id == note.id }) {
                store.delete(at: IndexSet([idx]))
            }
        }
        dismiss()
    }
}
