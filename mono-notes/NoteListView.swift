import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var store: NoteStore

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if store.notes.isEmpty {
                        VStack(spacing: 12) {
                            Text("no notes")
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("tap + to start")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(store.notes) { note in
                                    NavigationLink(destination: NoteEditorView(note: note).environmentObject(store)) {
                                        NoteCardView(note: note)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.delete(note: note)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 80)
                        }
                    }
                }

                // New note button — bottom left
                NavigationLink(
                    destination: NewNoteView().environmentObject(store)
                ) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(Color(.systemFill))
                        .clipShape(Circle())
                        .padding(.leading, 20)
                        .padding(.bottom, 24)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("notes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NoteCardView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(note.title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(note.dateLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }

            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemBackground))
                )
        )
    }
}
