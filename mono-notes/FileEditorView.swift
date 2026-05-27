import SwiftUI

struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @Binding var sidebarOpen: Bool
    let tab: AppTab

    // Local copy of file for editing
    @State private var file: FileItem

    init(file: FileItem, tab: AppTab, sidebarOpen: Binding<Bool>) {
        _file = State(initialValue: file)
        _sidebarOpen = sidebarOpen
        self.tab = tab
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { withAnimation { sidebarOpen.toggle() } } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(file.dateLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 12)

            Divider()

            // Editor
            if tab == .notes {
                NoteBodyEditor(file: $file, tab: tab)
            } else {
                NoteBodyEditor(file: $file, tab: tab)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Note body editor (plain text for now; list editor iteration 3)

struct NoteBodyEditor: View {
    @EnvironmentObject var store: AppStore
    @Binding var file: FileItem
    let tab: AppTab

    var body: some View {
        TextEditor(text: $file.body)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .scrollContentBackground(.hidden)
            .onChange(of: file.body) { _, newValue in
                var updated = file
                updated.body = newValue
                updated.updatedAt = Date()
                store.updateFile(updated, tab: tab)
                file = updated
            }
    }
}
