import Foundation
import Combine

final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("notes.json")
    }()

    init() { load() }

    // MARK: - CRUD

    func create() -> Note {
        let note = Note()
        notes.insert(note, at: 0)
        save()
        return note
    }

    /// Update note body and updatedAt only if content actually changed
    func update(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let existing = notes[idx]
        // Only bump updatedAt if body changed
        if existing.body != note.body {
            var updated = note
            updated.updatedAt = Date()
            notes[idx] = updated
            notes.sort { $0.updatedAt > $1.updatedAt }
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        save()
    }

    func delete(note: Note) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path),
              let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data)
        else { return }
        notes = decoded
    }
}
