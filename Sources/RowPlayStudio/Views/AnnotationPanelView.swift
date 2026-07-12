import Foundation
import RowPlayCore
import SwiftUI

struct AnnotationPanelView: View {
    var workoutID: Int
    var workoutDuration: TimeInterval
    var store: any AnnotationStore

    @State private var annotations: [Annotation] = []
    @State private var draftText = ""
    @State private var draftTimestamp: TimeInterval = 0
    @State private var errorMessage: String?

    var body: some View {
        WorkoutToolSection("Annotations") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        LabeledContent("Timestamp", value: RowPlayFormatting.time(draftTimestamp, tenths: true))
                            .monospacedDigit()

                        Slider(value: $draftTimestamp, in: 0...maxTimestamp)
                            .frame(maxWidth: 320)
                    }

                    TextField("Add annotation", text: $draftText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button(action: saveDraft) {
                        Label("Save Annotation", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                if annotations.isEmpty {
                    ContentUnavailableView("No Annotations", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(annotations) { annotation in
                            AnnotationRowView(annotation: annotation) {
                                delete(annotation)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: workoutID) {
            await loadAnnotations()
        }
        .onChange(of: workoutDuration) { _, _ in
            draftTimestamp = min(max(draftTimestamp, 0), maxTimestamp)
        }
        .alert("Annotation Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var maxTimestamp: TimeInterval {
        guard workoutDuration.isFinite, workoutDuration > 0 else { return 1 }
        return workoutDuration
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

    private func saveDraft() {
        let timestamp = min(max(draftTimestamp, 0), maxTimestamp)
        let annotation = Annotation(
            id: 0,
            timestamp: timestamp,
            text: draftText,
            createdAt: Int64(Date().timeIntervalSince1970 * 1_000)
        )

        Task {
            do {
                _ = try await store.saveAnnotation(workoutId: workoutID, annotation)
                await MainActor.run {
                    draftText = ""
                }
                await loadAnnotations()
            } catch {
                await MainActor.run {
                    errorMessage = annotationErrorText(error)
                }
            }
        }
    }

    private func delete(_ annotation: Annotation) {
        Task {
            do {
                try await store.deleteAnnotation(workoutId: workoutID, id: annotation.id)
                await loadAnnotations()
            } catch {
                await MainActor.run {
                    errorMessage = annotationErrorText(error)
                }
            }
        }
    }

    private func loadAnnotations() async {
        do {
            let loaded = try await store.loadAnnotations(workoutId: workoutID)
            await MainActor.run {
                annotations = loaded
                draftTimestamp = min(max(draftTimestamp, 0), maxTimestamp)
            }
        } catch {
            await MainActor.run {
                errorMessage = annotationErrorText(error)
            }
        }
    }

    private func annotationErrorText(_ error: Error) -> String {
        if let annotationError = error as? AnnotationError {
            switch annotationError {
            case .validationFailed(let message):
                return message
            case .storageUnavailable, .storageFailed:
                return "Annotation storage is unavailable."
            case .notFound:
                return "Annotation could not be updated."
            }
        }
        return "Annotation storage is unavailable."
    }
}

private struct AnnotationRowView: View {
    var annotation: Annotation
    var onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(RowPlayFormatting.time(annotation.timestamp, tenths: true))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(annotation.text)
                    .font(.callout)
                    .textSelection(.enabled)

                Text(createdAtText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete annotation")
            .accessibilityValue("at \(RowPlayFormatting.time(annotation.timestamp, tenths: true))")
            .help("Delete annotation")
            .confirmationDialog("Delete Annotation?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this annotation? This action cannot be undone.")
            }
        }
        .padding(.vertical, 4)
    }

    private var createdAtText: String {
        Date(timeIntervalSince1970: Double(annotation.createdAt) / 1_000)
            .formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
