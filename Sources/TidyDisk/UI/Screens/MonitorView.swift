import SwiftUI

struct MonitorView: View {
    var body: some View {
        Page(icon: "waveform.path.ecg", title: "Monitor", subtitle: "") { EmptyView() } content: {
            EmptyState(icon: "waveform.path.ecg", title: "Monitor", message: "Coming up.")
        }
    }
}
