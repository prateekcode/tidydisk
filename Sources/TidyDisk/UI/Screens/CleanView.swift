import SwiftUI

struct CleanView: View {
    var body: some View {
        Page(icon: "sparkles", title: "Clean", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "sparkles", title: "Clean", message: "Coming up.")
        }
    }
}
