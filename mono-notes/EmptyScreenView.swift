import SwiftUI

struct EmptyScreenView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedFile: FileItem?
    @Binding var selectedTab: AppTab
    @Binding var sidebarOpen: Bool

    var body: some View {
        ZStack {
            // Menu button top-left
            VStack {
                HStack {
                    menuButton
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
            }

            // Center buttons
            HStack(spacing: 32) {
                createButton(label: "note", icon: "doc.text") {
                    let file = store.createFile(kind: .note, in: .notes)
                    selectedFile = file
                    selectedTab = .notes
                }
                createButton(label: "list", icon: "list.bullet") {
                    let file = store.createFile(kind: .list, in: .lists)
                    selectedFile = file
                    selectedTab = .lists
                }
            }
        }
    }

    private var menuButton: some View {
        Button { withAnimation { sidebarOpen.toggle() } } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18))
                .foregroundStyle(.primary)
        }
    }

    private func createButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                Text(label)
                    .font(.system(.footnote, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .frame(width: 90, height: 90)
            .background(Color(.systemFill))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
