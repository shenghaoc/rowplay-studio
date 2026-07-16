import SwiftUI

/// Focused native macOS finish surface for replay race actions.
struct ReplayFinishVerdictView: View {
    let verdict: String
    let shareItem: ReplayRaceCardTransferItem?
    let saveReport: () -> Void
    let saveCard: () -> Void
    let retrySharePreparation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.small) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xxSmall) {
                Text("Race Finished")
                    .font(AppDesign.Typography.compactLabel.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verdict)
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Race finished")
            .accessibilityValue(verdict)

            HStack(spacing: AppDesign.Spacing.medium) {
                Button("Save Race Report…", action: saveReport)
                    .accessibilityLabel("Save Race Report")
                Button("Save Race Card…", action: saveCard)
                    .accessibilityLabel("Save Race Card")

                if let shareItem {
                    ShareLink(
                        item: shareItem,
                        preview: SharePreview("Race Card", image: Image(systemName: "flag.checkered"))
                    ) {
                        Label("Share Race Card", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Race Card")
                } else {
                    Button("Retry Share Card", action: retrySharePreparation)
                        .accessibilityLabel("Retry Share Card Preparation")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, AppDesign.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}
