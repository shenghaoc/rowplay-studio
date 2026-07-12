import RowPlayCore
import SwiftUI

struct WorkoutToolsView: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var comparisonCandidates: [WorkoutDetail]
    var annotationStore: any AnnotationStore
    var onUpdateDetail: (WorkoutDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workout Tools")
                .font(.title3.weight(.semibold))

            WorkoutFileActionsView(detail: detail)

            HrImportPanelView(
                detail: detail,
                onUpdateDetail: onUpdateDetail
            )

            WorkoutComparisonPanel(
                detail: detail,
                detailsRevision: detailsRevision,
                candidates: comparisonCandidates
            )

            AnnotationPanelView(
                workoutID: detail.id,
                workoutDuration: detail.workout.time,
                store: annotationStore
            )
        }
    }
}
