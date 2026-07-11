import SwiftUI

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color == .primary ? .secondary : color.opacity(0.7))
            Text(value)
                .font(AppDesign.Typography.heroMetric)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(AppDesign.Typography.metricLabel)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppDesign.Spacing.xLarge)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

