import Combine
import Foundation
import RowPlayCore

@MainActor
final class WorkoutLibrary: ObservableObject {
    @Published var details: [WorkoutDetail]
    @Published var selectedSport: Sport?
    @Published var searchText: String

    init(details: [WorkoutDetail], selectedSport: Sport? = nil, searchText: String = "") {
        self.details = details
        self.selectedSport = selectedSport
        self.searchText = searchText
    }

    static func demo() -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details)
    }

    var workouts: [Workout] {
        details.map(\.workout)
    }

    var filteredDetails: [WorkoutDetail] {
        details.filter { detail in
            let workout = detail.workout
            let sportMatches = selectedSport == nil || selectedSport == workout.sport
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return sportMatches
            }

            let haystack = [
                workout.workoutType,
                workout.sport.displayName,
                workout.comments ?? "",
                workout.source ?? ""
            ].joined(separator: " ").lowercased()

            return sportMatches && haystack.contains(query.lowercased())
        }
    }

    var summary: DashboardSummary {
        WorkoutAnalytics.dashboardSummary(for: workouts)
    }

    func detail(id: Int) -> WorkoutDetail? {
        details.first { $0.id == id }
    }

    func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        selectedSport = nil
        searchText = ""
    }
}

