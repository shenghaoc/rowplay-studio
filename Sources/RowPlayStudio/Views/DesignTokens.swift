import SwiftUI

/// Central design tokens for RowPlay Studio.
///
/// All views reference these tokens instead of hardcoding colors, spacing,
/// or typography values. This keeps the visual language cohesive and makes
/// future theme adjustments trivial.
enum AppDesign {

    // MARK: - Color Palette

    /// Primary brand blue — used for primary actions, distance, key emphasis.
    static let primaryBlue = Color(lightHex: 0x0066CC, darkHex: 0x0A84FF)

    /// Warm comparison orange — used for watts, splits, secondary emphasis.
    static let comparisonOrange = Color(lightHex: 0x9A5700, darkHex: 0xFF9F0A)

    /// Energetic green — used for positive deltas, success states, cadence highlights.
    static let energeticGreen = Color(lightHex: 0x137333, darkHex: 0x30D158)

    /// Alert red — used for negative deltas, heart rate, finish markers.
    static let alertRed = Color(lightHex: 0xB3261E, darkHex: 0xFF453A)

    /// Soft purple — used for elevation, descent, cadence accents.
    static let softPurple = Color(lightHex: 0x7B2CBF, darkHex: 0xBF5AF2)

    /// Warm yellow — used for caution states, active indicators.
    static let warmYellow = Color(lightHex: 0x7A5A00, darkHex: 0xFFD60A)

    // MARK: - Semantic Metric Colors

    enum MetricColor {
        static let distance = primaryBlue
        static let duration = Color(lightHex: 0x007A99, darkHex: 0x64D2FF)
        /// Slightly lighter blue than distance, so pace/distance are distinguishable.
        static let pace = Color(lightHex: 0x0066CC, darkHex: 0x409CFF)
        static let speed = comparisonOrange
        static let watts = comparisonOrange
        static let heartRate = alertRed
        static let cadence = softPurple
        static let split = comparisonOrange
    }

    // MARK: - Semantic Helpers

    /// Returns a green/red color for positive/negative deltas, with a dead-zone threshold.
    /// - Parameters:
    ///   - delta: The numeric delta to evaluate
    ///   - threshold: Minimum absolute value before signaling (default 0.5)
    ///   - higherIsBetter: When `true`, positive deltas are green (e.g. watts, distance).
    ///                      Default `false` (e.g. pace, where lower is better).
    static func deltaColor(
        _ delta: Double?,
        threshold: Double = 0.5,
        higherIsBetter: Bool = false
    ) -> Color {
        guard let d = delta, d.isFinite, abs(d) >= threshold else { return .secondary }
        let positive = higherIsBetter ? d > 0 : d < 0
        return positive ? energeticGreen : alertRed
    }

    // MARK: - Spacing Scale

    enum Spacing {
        /// 2pt — hairline gaps
        static let xxSmall: CGFloat = 2
        /// 4pt — tight gaps within components
        static let xSmall: CGFloat = 4
        /// 6pt — compact gaps
        static let small: CGFloat = 6
        /// 8pt — default inner padding
        static let medium: CGFloat = 8
        /// 12pt — standard component spacing
        static let large: CGFloat = 12
        /// 16pt — section-level spacing
        static let xLarge: CGFloat = 16
        /// 20pt — generous section gaps
        static let xxLarge: CGFloat = 20
        /// 24pt — major section separation
        static let xxxLarge: CGFloat = 24
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 6pt — small badges, tags
        static let small: CGFloat = 6
        /// 8pt — cards, panels
        static let medium: CGFloat = 8
        /// 12pt — large cards, overlays
        static let large: CGFloat = 12
        /// 16pt — hero cards
        static let xLarge: CGFloat = 16
    }

    // MARK: - Typography

    enum Typography {
        /// Large hero metric — used for primary values in summary cards.
        static let heroMetric = Font.system(.title, design: .rounded, weight: .bold)

        /// Section headline — used for panel titles.
        static let sectionHeadline = Font.system(.headline, design: .default, weight: .semibold)

        /// Metric value — used for data values in badges and cards.
        static let metricValue = Font.system(.callout, design: .default, weight: .semibold)

        /// Metric label — used for labels beneath values and compact data displays.
        static let metricLabel = Font.system(.caption2, design: .default, weight: .medium)

        /// Compact label — used for dense UI labels in sidebars, comparison grids, and live mode.
        static let compactLabel = Font.system(size: 10, weight: .medium, design: .default)

        /// Compact icon — used for inline SF Symbols in tight spaces like sidebar sort buttons.
        static let compactIcon = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Background Treatments

    /// Subtle grouped background for panels — lighter than window background.
    static let panelBackground = Color.primary.opacity(0.03)

    /// Card background with subtle warmth.
    static let cardBackground = Color.primary.opacity(0.04)

    /// Active/selected card background.
    static let activeCardBackground = Color.accentColor.opacity(0.08)

    /// Overlay backdrop for map controls.
    #if os(macOS)
    static let overlayBackground = Color(nsColor: .controlBackgroundColor).opacity(0.85)
    #else
    static let overlayBackground = Color(uiColor: .systemBackground).opacity(0.85)
    #endif
}

extension View {
    func panelStyle() -> some View {
        padding(AppDesign.Spacing.xLarge)
            .background(AppDesign.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(lightHex: UInt, darkHex: UInt, opacity: Double = 1.0) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex, opacity: opacity)
        })
        #else
        self.init(uiColor: UIColor { traitCollection in
            let isDark = traitCollection.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? darkHex : lightHex, opacity: opacity)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt, opacity: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt, opacity: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
#endif
