import SwiftUI

/// An accessible visual section for workout tools.
///
/// SwiftUI `GroupBox` produces an accessibility representation that currently
/// causes `SkyComputerUseService` to trap while traversing RowPlay Studio.
/// This explicit section keeps the heading, visual grouping, and all child
/// controls available to VoiceOver and Computer Use without that framework
/// representation.
struct WorkoutToolSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
