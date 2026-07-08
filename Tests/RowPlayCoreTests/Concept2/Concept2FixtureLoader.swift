import Foundation
@testable import RowPlayCore

// MARK: - Fixture wrapper

/// Top-level shape of a golden Concept2 fixture JSON file.
///
/// Each fixture captures a sanitized API response plus hand-verified expected
/// domain values. See `REDACTION.md` in the fixture directory for the
/// redaction policy.
struct Concept2GoldenFixture: Decodable {
    let description: String
    let rawResult: Concept2RawResult
    let rawStrokes: [Concept2RawStroke]
    let expected: Concept2GoldenExpected

    /// Index of the first stroke in rep 2 (interval fixtures only).
    let rep2FirstIndex: Int?
    /// Final cumulative t for rep 1 (interval fixtures only).
    let rep1FinalT: Double?
    /// Final cumulative d for rep 1 (interval fixtures only).
    let rep1FinalD: Double?

    enum CodingKeys: String, CodingKey {
        case description, rawResult, rawStrokes, expected
        case rep2FirstIndex = "_rep2FirstIndex"
        case rep1FinalT = "_rep1FinalT"
        case rep1FinalD = "_rep1FinalD"
    }
}

// MARK: - Expected values

struct Concept2GoldenExpected: Decodable {
    let result: Concept2GoldenExpectedResult
    let strokes: [Concept2GoldenExpectedStroke]
    let splits: [Concept2GoldenExpectedSplit]
}

struct Concept2GoldenExpectedResult: Decodable {
    let sport: String
    let time: Double?
    let distance: Double?
    let pace: Double?
}

struct Concept2GoldenExpectedStroke: Decodable {
    let index: Int
    let t: Double?
    let d: Double?
    let pace: Double?

    enum CodingKeys: String, CodingKey {
        case index = "_index"
        case t, d, pace
    }
}

struct Concept2GoldenExpectedSplit: Decodable {
    let index: Int
    let time: Double?
    let distance: Double?
    let pace: Double?

    enum CodingKeys: String, CodingKey {
        case index = "_index"
        case time, distance, pace
    }
}

// MARK: - Loader

/// Loads Concept2 golden fixture JSON files from the test bundle.
enum Concept2FixtureLoader {
    /// Load and decode a golden fixture by filename (without `.fixture.json`).
    static func loadFixture(named name: String) throws -> Concept2GoldenFixture {
        let filename = "\(name).fixture"
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            throw ParityFixtureError.fileNotFound(filename)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Concept2GoldenFixture.self, from: data)
    }

    /// Load raw fixture Data for secret-scanning tests.
    static func loadRawData(named name: String) throws -> Data {
        let filename = "\(name).fixture"
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            throw ParityFixtureError.fileNotFound(filename)
        }
        return try Data(contentsOf: url)
    }
}
