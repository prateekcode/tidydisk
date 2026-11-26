import SwiftUI

struct LogView: View {
    @EnvironmentObject var log: ActivityLog

    var body: some View {
        Page(icon: AppTab.log.icon, title: "Activity log",
             subtitle: "Everything TidyDisk scanned, cleaned or moved in this session") {
            EmptyView()
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if log.lines.isEmpty {
                            Text("Nothing yet. Run a scan.").foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("—") ? Theme.accent : Theme.textSecondary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
                .panel()
                .onChange(of: log.lines.count) {
                    proxy.scrollTo(log.lines.count - 1, anchor: .bottom)
                }
            }
        }
    }
}
