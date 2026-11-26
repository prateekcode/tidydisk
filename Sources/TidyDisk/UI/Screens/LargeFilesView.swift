import SwiftUI

struct LargeFilesView: View {
    var body: some View {
        Page(icon: "sparkles", title: "LargeFiles", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "sparkles", title: "LargeFiles", message: "Coming up.")
        }
    }
}
