import SwiftUI

/// Editing an existing note — opened via NavigationLink
struct NoteEditorView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    let note: Note
    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .onAppear {
                text = note.body
                // No auto-keyboard on open
            }
            .onChange(of: text) { _, newValue in
                var updated = note
                updated.body = newValue
                store.update(updated)
            }
            .onDisappear {
                // Delete note if empty on back navigation
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store.delete(note: note)
                }
            }
    }
}

/// Creating a new note — dedicated push screen
struct NewNoteView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var note: Note? = nil
    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .onAppear {
                let created = store.create()
                note = created
            }
            .onChange(of: text) { _, newValue in
                guard let n = note else { return }
                var updated = n
                updated.body = newValue
                store.update(updated)
                // Keep local ref updated so next change diff works
                if let idx = store.notes.firstIndex(where: { $0.id == n.id }) {
                    note = store.notes[idx]
                }
            }
            .onDisappear {
                // Delete if nothing was written
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let n = note {
                    store.delete(note: n)
                }
            }
    }
}
