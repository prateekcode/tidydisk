import SwiftUI

struct AppsView: View {
    var body: some View {
        Page(icon: "macwindow", title: "Apps", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "macwindow", title: "Apps", message: "Coming up.")
        }
    }
}
