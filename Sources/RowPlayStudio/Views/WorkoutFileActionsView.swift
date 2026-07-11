import AppKit
import Foundation
import RowPlayCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutFileActionsView: View {
    var detail: WorkoutDetail

    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        GroupBox("Export and Share") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: saveCSV) {
                        Label("Export CSV", systemImage: "tablecells")
                    }

                    Button(action: saveJSON) {
                        Label("Export JSON", systemImage: "curlybraces")
                    }

                    Button(action: saveTCX) {
                        Label("Export TCX", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    }

                    Button(action: saveSharePackage) {
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

    private func saveCSV() {
        let filename = WorkoutExport.workoutExportFilename(id: detail.id, ext: "csv")
        let data = Data(WorkoutExport.csv([detail.workout]).utf8)
        save(data: data, suggestedFilename: filename, contentTypes: [.commaSeparatedText])
    }

    private func saveJSON() {
        let filename = WorkoutExport.workoutExportFilename(id: detail.id, ext: "json")
        let data = Data(WorkoutExport.json([detail.workout]).utf8)
        save(data: data, suggestedFilename: filename, contentTypes: [.json])
    }

    private func saveTCX() {
        let filename = WorkoutExport.workoutExportFilename(id: detail.id, ext: "tcx")
        let data = Data(WorkoutExport.tcx(detail).utf8)
        let tcxType = UTType(filenameExtension: "tcx") ?? .xml
        save(data: data, suggestedFilename: filename, contentTypes: [tcxType])
    }

    private func saveSharePackage() {
        do {
            let package = SharePackageBuilder.build(from: detail)
            let data = try SharePackageCodec.encode(package)
            let filename = WorkoutExport.workoutExportFilename(id: detail.id, ext: "rowplay-share.json")
            save(data: data, suggestedFilename: filename, contentTypes: [.json])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(data: Data, suggestedFilename: String, contentTypes: [UTType]) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = contentTypes
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
