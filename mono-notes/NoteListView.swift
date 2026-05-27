import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var store: NoteStore
    @State private var selectedNote: Note?
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if store.notes.isEmpty {
                    VStack(spacing: 12) {
                        Text("no notes")
                            .font(.system(.title3, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("tap \u{2197} to start")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.notes) { note in
                            Button {
                                selectedNote = note
                                showEditor = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !note.preview.isEmpty {
                                        Text(note.preview)
                                            .font(.system(.footnote, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let note = store.create()
                        selectedNote = note
                        showEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { selectedNote = nil }) {
                if let note = selectedNote {
                    NoteEditorView(note: note)
                        .environmentObject(store)
                }
            }
        }
    }
}
