import SwiftUI

/// Shown when there is content but nothing is selected
struct PlaceholderView: View {
    @Binding var sidebarOpen: Bool

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Button { withAnimation { sidebarOpen.toggle() } } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
            }

            Text("select a note")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}
