import Foundation
import RowPlayCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutFileActionsView: View {
    var detail: WorkoutDetail

    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var exportData: Data?
    @State private var exportFilename: String = ""
    @State private var exportContentType: UTType = .json
    @State private var showExporter = false

    var body: some View {
        WorkoutToolSection("Export and Share") {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                HStack(spacing: AppDesign.Spacing.medium) {
                    Button(action: { prepareExport(.csv) }) {
                        Label("Export CSV", systemImage: "tablecells")
                    }

                    Button(action: { prepareExport(.json) }) {
                        Label("Export JSON", systemImage: "curlybraces")
                    }

                    Button(action: { prepareExport(.tcx) }) {
                        Label("Export TCX", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    }

                    Button(action: { prepareExport(.sharePackage) }) {
                        Label("Share Package", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!detail.workout.hasStrokeData && detail.splits.isEmpty)
                }
                .buttonStyle(.bordered)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileExporter(
            isPresented: $showExporter,
            item: exportData,
            contentTypes: [exportContentType],
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                statusMessage = "Saved \(url.lastPathComponent)"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            exportData = nil
        }
        .alert("Export Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

    private enum ExportFormat {
        case csv, json, tcx, sharePackage

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            case .tcx: return "tcx"
            case .sharePackage: return "rowplay-share.json"
            }
        }
    }

    private func prepareExport(_ format: ExportFormat) {
        let filename = WorkoutExport.workoutExportFilename(id: detail.id, ext: format.fileExtension)
        let data: Data

        switch format {
        case .csv:
            data = Data(WorkoutExport.csv([detail.workout]).utf8)
            exportContentType = .commaSeparatedText
        case .json:
            data = Data(WorkoutExport.json([detail.workout]).utf8)
            exportContentType = .json
        case .tcx:
            data = Data(WorkoutExport.tcx(detail).utf8)
            exportContentType = UTType(tag: "tcx", tagClass: .filenameExtension, conformingTo: .xml) ?? .xml
        case .sharePackage:
            do {
                let package = SharePackageBuilder.build(from: detail)
                data = try SharePackageCodec.encode(package)
                exportContentType = .json
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        exportData = data
        exportFilename = filename
        showExporter = true
    }
}
