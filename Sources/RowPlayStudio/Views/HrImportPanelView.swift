import Foundation
import RowPlayCore
import SwiftUI
import UniformTypeIdentifiers

struct HrImportPanelView: View {
    var detail: WorkoutDetail
    var onUpdateDetail: (WorkoutDetail) -> Void

    @State private var offsetSec: TimeInterval = 0
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showImporter = false

    var body: some View {
        WorkoutToolSection("Heart Rate Import") {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                HStack(spacing: AppDesign.Spacing.large) {
                    Stepper(value: $offsetSec, in: -600...600, step: 0.5) {
                        LabeledContent("Offset", value: "\(formatSigned(offsetSec)) s")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 260)

                    Button(action: { showImporter = true }) {
                        Label("Import HR Samples", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.bordered)
                    .disabled(detail.strokes.isEmpty)
                    .help("Import JSON or CSV samples with elapsed seconds and heart rate columns")
                    .accessibilityHint("Opens a file picker to select a heart rate data file")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("HR Import Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                importSamples(from: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                errorMessage = nil
            }
        }
    }

    private func importSamples(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let samples = try loadSamples(from: url)
            guard samples.count >= 2 else {
                throw HrImportPanelError.notEnoughSamples
            }
            let updatedDetail = HrImport.applyHrImport(detail, samples: samples, offsetSec: offsetSec)
            onUpdateDetail(updatedDetail)
            statusMessage = "Imported \(samples.count) HR samples"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSamples(from url: URL) throws -> [HrSample] {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "json" {
            return try decodeJSONSamples(data)
        }

        if let jsonSamples = try? decodeJSONSamples(data) {
            return jsonSamples
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw HrImportPanelError.unreadableFile
        }
        return parseCSVSampleText(text)
    }

    private func decodeJSONSamples(_ data: Data) throws -> [HrSample] {
        let decoded = try JSONDecoder().decode([HrSampleDTO].self, from: data)
        return decoded.compactMap { dto in
            guard dto.t.isFinite, dto.t >= 0, dto.hr > 0 else { return nil }
            return HrSample(t: dto.t, hr: dto.hr)
        }
        .sorted { $0.t < $1.t }
    }

    private func parseCSVSampleText(_ text: String) -> [HrSample] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> HrSample? in
                let cells = line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard cells.count >= 2,
                      let t = TimeInterval(cells[0]),
                      let hr = Int(cells[1]),
                      t.isFinite,
                      t >= 0,
                      hr > 0 else {
                    return nil
                }
                return HrSample(t: t, hr: hr)
            }
            .sorted { $0.t < $1.t }
    }

    private func formatSigned(_ value: TimeInterval) -> String {
        let formatted = String(format: "%.1f", abs(value))
        if value > 0 {
            return "+\(formatted)"
        }
        if value < 0 {
            return "-\(formatted)"
        }
        return formatted
    }
}

private struct HrSampleDTO: Decodable {
    var t: TimeInterval
    var hr: Int
}

private enum HrImportPanelError: LocalizedError {
    case unreadableFile
    case notEnoughSamples

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be read as UTF-8 text."
        case .notEnoughSamples:
            return "At least two valid HR samples are required."
        }
    }
}
