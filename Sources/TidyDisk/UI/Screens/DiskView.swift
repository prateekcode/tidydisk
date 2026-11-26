import SwiftUI

struct DiskView: View {
    var body: some View {
        Page(icon: "sparkles", title: "Disk", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "sparkles", title: "Disk", message: "Coming up.")
        }
    }
}
