import SwiftUI

struct OverviewView: View {
    var body: some View {
        Page(icon: "sparkles", title: "Overview", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "sparkles", title: "Overview", message: "Coming up.")
        }
    }
}
