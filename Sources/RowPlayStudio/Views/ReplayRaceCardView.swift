import AppKit
import RowPlayCore
import SwiftUI

/// Native race-card layout for local PNG export (light and dark).
struct ReplayRaceCardView: View {
    let report: ReplayRaceReport
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var bg: Color { isDark ? Color(hex: 0x18140D) : Color(hex: 0xFBF7EE) }
    private var ink: Color { isDark ? Color(hex: 0xE7DFCE) : Color(hex: 0x18140D) }
    private var ink2: Color { isDark ? Color(hex: 0xB5AA96) : Color(hex: 0x6A6052) }
    private var live: Color { AppDesign.alertRed }
    private var accent: Color {
        ReplayView.machineColor(for: report.sport, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(live)
                .frame(height: 8)

            VStack(alignment: .leading, spacing: 20) {
                Text("RowPlay Studio")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(ink)
                Text("RACE BOARD")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ink2)

                Text(report.sport.displayName)
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(accent)

                Text(targetLine)
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink2)

                Text(outcomeLine)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.top, 8)

                Divider().opacity(0.3)

                metricBlock(title: "You", lines: playerLines)
                metricBlock(title: report.rival.label, lines: rivalLines)

                if let margins = marginLines, !margins.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(margins, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                                .foregroundStyle(live)
                        }
                    }
                    .padding(.top, 8)
                }

                Spacer(minLength: 12)

                Text("rowplay · local race card")
                    .font(.system(size: 14, weight: .medium).monospaced())
                    .foregroundStyle(ink2)
            }
            .padding(40)
        }
        .frame(width: 540, height: 720)
        .background(bg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var targetLine: String {
        if report.target.axis == ComparabilityAxis.time.rawValue,
           let duration = report.target.duration {
            return "Target \(RowPlayFormatting.time(duration, tenths: false))"
        }
        if let distance = report.target.distance {
            return "Target \(RowPlayFormatting.distance(distance))"
        }
        return "Target"
    }

    private var outcomeLine: String {
        if report.rivalDidNotFinish {
            return "You win — rival DNF"
        }
        switch report.outcome {
        case .playerWon: return "You win"
        case .rivalWon: return "Rival wins"
        case .tie: return "Tie"
        }
    }

    private var playerLines: [String] {
        [
            RowPlayFormatting.distance(report.primary.distance),
            RowPlayFormatting.time(report.primary.time, tenths: true),
            RowPlayFormatting.pace(report.primary.pace),
        ]
    }

    private var rivalLines: [String] {
        var lines: [String] = [report.rival.kind.displayName]
        if let pace = report.rival.targetPace {
            lines.append(RowPlayFormatting.pace(pace))
        }
        if report.rival.kind == .session, let id = report.rival.sessionWorkoutID {
            lines.append("Session #\(id)")
        }
        return lines
    }

    private var marginLines: [String]? {
        var lines: [String] = []
        if let time = report.timeMargin, time > 0.05 {
            lines.append("Time margin \(String(format: "%.1f", time)) s")
        }
        if let distance = report.distanceMargin, distance > 0.5 {
            lines.append("Distance margin \(RowPlayFormatting.distance(distance))")
        }
        if report.rivalDidNotFinish {
            lines.append("Rival did not finish")
        }
        return lines
    }

    private func metricBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink2)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(ink)
            }
        }
        .padding(.vertical, 8)
    }

    private var accessibilitySummary: String {
        "\(outcomeLine). \(report.sport.displayName). \(targetLine)."
    }
}

extension ReplayRivalKind {
    var displayName: String {
        switch self {
        case .session: return "Past session"
        case .constantPace: return "Constant pace"
        case .importedFile: return "Imported rival"
        }
    }
}

enum ReplayRaceCardRenderer {
    /// Render a privacy-safe race card to PNG data using SwiftUI ImageRenderer.
    @MainActor
    static func renderPNG(report: ReplayRaceReport, colorScheme: ColorScheme) -> Data? {
        let view = ReplayRaceCardView(report: report, colorScheme: colorScheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else { return nil }
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
