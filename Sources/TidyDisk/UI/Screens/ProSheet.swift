import SwiftUI
import AppKit

/// Paywall + license management, shown from the sidebar badge or any Pro gate.
struct ProSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keyField = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: state.isPro ? "checkmark.seal.fill" : "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(state.isPro ? Theme.tierColor(.safe) : .yellow)
                .padding(.top, 26)

            Text(state.isPro ? "TidyDisk Pro is active" : "TidyDisk Pro")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            if state.isPro {
                Text("All features are unlocked on this Mac. Thanks for supporting TidyDisk!")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Deactivate on this Mac") {
                    state.deactivateLicense()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
            } else {
                Text("Pay once, yours forever. The core cleaner stays free.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    ProFeatureRow(icon: "calendar.badge.clock",
                                  text: "Weekly scheduled scans with notifications")
                    ProFeatureRow(icon: "doc.on.doc.fill",
                                  text: "One-click duplicate cleanup")
                    ProFeatureRow(icon: "folder.fill.badge.gearshape",
                                  text: "Project actions — clean artifacts, push to GitHub, archive to cloud")
                    ProFeatureRow(icon: "infinity",
                                  text: "Lifetime updates, no subscription")
                }
                .padding(16)
                .glassCard(cornerRadius: 14)

                GlowButton(title: "Buy TidyDisk Pro — \(ProConfig.price)") {
                    if let url = URL(string: ProConfig.checkoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                }

                VStack(spacing: 8) {
                    Text("Already have a license key?")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        TextField("XXXX-XXXX-XXXX-XXXX", text: $keyField)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                            .onSubmit { state.activateLicense(keyField) }
                        if state.licenseActivating {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            PillButton(title: "Activate") { state.activateLicense(keyField) }
                        }
                    }
                    if let error = state.licenseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.tierColor(.nuclear))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 4)
            }

            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, 34)
        .frame(width: 440)
        .background(Theme.background(for: .welcome).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct ProFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }
}
