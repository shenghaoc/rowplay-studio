import XCTest
@testable import RowPlayStudio
import RowPlayCore

final class ReplayAcceptanceHarnessTests: XCTestCase {

    func testCatalogScenariosResolveValidDemoWorkouts() throws {
        let scenarios = try loadCatalogScenarios()
        XCTAssertGreaterThanOrEqual(scenarios.count, 30)
        XCTAssertLessThanOrEqual(scenarios.count, 40)

        for scenario in scenarios {
            let sport = try sport(from: scenario.sport)
            let detail = ReplayAcceptanceHarnessView.detail(for: sport)
            XCTAssertEqual(detail.workout.sport, sport, scenario.id)
            XCTAssertEqual(
                detail.id,
                ReplayAcceptanceConfiguration.demoWorkoutID(for: sport),
                scenario.id
            )
            XCTAssertTrue(detail.workout.hasStrokeData, scenario.id)

            let candidates = ReplayAcceptanceHarnessView.ghostCandidates(
                for: sport,
                excluding: detail.id
            )
            if scenario.rival == "session" {
                XCTAssertFalse(candidates.isEmpty, "session rival requires candidates for \(scenario.id)")
            }

            let mode = try rivalMode(from: scenario.rival)
            let rival = ReplayAcceptanceHarnessView.resolvedRival(
                mode: mode,
                detail: detail,
                candidates: candidates
            )
            switch mode {
            case .none:
                XCTAssertNil(rival, scenario.id)
            case .session, .pace:
                XCTAssertNotNil(rival, scenario.id)
            }

            let renderer = try renderer(from: scenario.renderer)
            let quality = try XCTUnwrap(ReplayRenderQuality(rawValue: scenario.quality))
            let camera = try XCTUnwrap(ReplayCameraPreset(rawValue: scenario.camera))
            XCTAssertTrue(ReplayRendererMode.allCases.contains(renderer), scenario.id)
            XCTAssertTrue(ReplayRenderQuality.allCases.contains(quality), scenario.id)
            XCTAssertTrue(ReplayCameraPreset.allCases.contains(camera), scenario.id)
            XCTAssertGreaterThanOrEqual(scenario.time, 0, scenario.id)
            XCTAssertTrue(scenario.time.isFinite, scenario.id)
        }
    }

    func testViewConfigurationResolvesExactly() throws {
        let acceptance = try XCTUnwrap(
            try ReplayAcceptanceConfiguration.parse(from: [
                "ROWPLAY_REPLAY_ACCEPTANCE": "1",
                "ROWPLAY_QA_SPORT": "bike",
                "ROWPLAY_QA_RENDERER": "2d",
                "ROWPLAY_QA_QUALITY": "high",
                "ROWPLAY_QA_CAMERA": "overhead",
                "ROWPLAY_QA_THEME": "light",
                "ROWPLAY_QA_RIVAL": "pace",
                "ROWPLAY_QA_TIME": "9",
                "ROWPLAY_QA_REDUCED_MOTION": "1",
                "ROWPLAY_QA_WIDTH": "1100",
                "ROWPLAY_QA_HEIGHT": "720"
            ])
        )
        let viewConfig = acceptance.makeViewConfiguration()
        XCTAssertEqual(viewConfig.rendererMode, .twoD)
        XCTAssertEqual(viewConfig.quality, .high)
        XCTAssertEqual(viewConfig.cameraPreset, .overhead)
        XCTAssertEqual(viewConfig.seekTime, 9)
        XCTAssertEqual(viewConfig.rivalMode, .pace)
        XCTAssertEqual(viewConfig.forceReducedMotion, true)
        XCTAssertFalse(viewConfig.persistsQualityPreference)
    }

    func testNormalReplayViewConstructionRemainsSourceCompatible() {
        let detail = DemoWorkoutLibrary.details[0]
        // Defaulted initial configuration keeps production call sites compiling.
        let view = ReplayView(detail: detail)
        XCTAssertEqual(view.detail.id, detail.id)
        XCTAssertEqual(view.ghostCandidates.count, 0)
    }

    func testAcceptanceModeExposesProductionSemantics() throws {
        let scenarios = try loadCatalogScenarios()
        let ids = Set(scenarios.map(\.id))
        for required in [
            "rower-3d-ultra-session-rival",
            "skierg-3d-ultra-session-rival",
            "bike-3d-ultra-session-rival",
            "rower-2d-light",
            "skierg-2d-dark",
            "bike-2d-rival"
        ] {
            XCTAssertTrue(ids.contains(required), "missing required scenario \(required)")
        }

        // Harness builds from the same demo library production ReplayView uses.
        let detail = ReplayAcceptanceHarnessView.detail(for: .rower)
        XCTAssertTrue(DemoWorkoutLibrary.details.contains(where: { $0.id == detail.id }))
    }

    func testNoScenarioWritesUserPreferences() throws {
        let acceptance = try XCTUnwrap(
            try ReplayAcceptanceConfiguration.parse(from: [
                "ROWPLAY_REPLAY_ACCEPTANCE": "1"
            ])
        )
        XCTAssertFalse(acceptance.makeViewConfiguration().persistsQualityPreference)
    }

    private struct CatalogScenario: Decodable {
        let id: String
        let sport: String
        let renderer: String
        let quality: String
        let camera: String
        let theme: String
        let rival: String
        let time: Double
        let reducedMotion: Bool
        let width: Double
        let height: Double
        let phase: String
    }

    private struct Catalog: Decodable {
        let scenarios: [CatalogScenario]
    }

    private func loadCatalogScenarios() throws -> [CatalogScenario] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/replay_acceptance_scenarios.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Catalog.self, from: data).scenarios
    }

    private func sport(from raw: String) throws -> Sport {
        switch raw {
        case "rower": return .rower
        case "skierg": return .skierg
        case "bike": return .bike
        default:
            XCTFail("unknown sport \(raw)")
            return .rower
        }
    }

    private func renderer(from raw: String) throws -> ReplayRendererMode {
        switch raw {
        case "2d": return .twoD
        case "3d": return .threeD
        default:
            XCTFail("unknown renderer \(raw)")
            return .threeD
        }
    }

    private func rivalMode(from raw: String) throws -> ReplayAcceptanceConfiguration.RivalMode {
        try XCTUnwrap(ReplayAcceptanceConfiguration.RivalMode(rawValue: raw))
    }
}
