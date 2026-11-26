import SwiftUI

struct AIView: View {
    var body: some View {
        Page(icon: "brain", title: "AI", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "brain", title: "AI", message: "Coming up.")
        }
    }
}
