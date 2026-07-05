import XCTest
@testable import RowPlayCore

final class SportTests: XCTestCase {

    // MARK: - fromConcept2Type

    func testFromConcept2TypeRower() {
        XCTAssertEqual(Sport.fromConcept2Type("rower"), .rower)
    }

    func testFromConcept2TypeSkiCaseInsensitive() {
        XCTAssertEqual(Sport.fromConcept2Type("SKI"), .skierg)
    }

    func testFromConcept2TypeSki() {
        XCTAssertEqual(Sport.fromConcept2Type("ski"), .skierg)
    }

    func testFromConcept2TypeSkiErg() {
        XCTAssertEqual(Sport.fromConcept2Type("skierg"), .skierg)
    }

    func testFromConcept2TypeBike() {
        XCTAssertEqual(Sport.fromConcept2Type("bike"), .bike)
    }

    func testFromConcept2TypeBikeErg() {
        XCTAssertEqual(Sport.fromConcept2Type("bikeerg"), .bike)
    }

    func testFromConcept2TypeNil() {
        XCTAssertEqual(Sport.fromConcept2Type(nil), .rower)
    }

    func testFromConcept2TypeUnknown() {
        XCTAssertEqual(Sport.fromConcept2Type("unknown"), .rower)
    }

    func testFromConcept2TypeEmpty() {
        XCTAssertEqual(Sport.fromConcept2Type(""), .rower)
    }

    // MARK: - displayName

    func testDisplayNameRower() {
        XCTAssertEqual(Sport.rower.displayName, "RowErg")
    }

    func testDisplayNameSkiErg() {
        XCTAssertEqual(Sport.skierg.displayName, "SkiErg")
    }

    func testDisplayNameBike() {
        XCTAssertEqual(Sport.bike.displayName, "BikeErg")
    }

    // MARK: - shortName

    func testShortNameRower() {
        XCTAssertEqual(Sport.rower.shortName, "Row")
    }

    func testShortNameSkiErg() {
        XCTAssertEqual(Sport.skierg.shortName, "Ski")
    }

    func testShortNameBike() {
        XCTAssertEqual(Sport.bike.shortName, "Bike")
    }

    // MARK: - cadenceUnit

    func testCadenceUnitRower() {
        XCTAssertEqual(Sport.rower.cadenceUnit, "spm")
    }

    func testCadenceUnitSkiErg() {
        XCTAssertEqual(Sport.skierg.cadenceUnit, "spm")
    }

    func testCadenceUnitBike() {
        XCTAssertEqual(Sport.bike.cadenceUnit, "rpm")
    }

    // MARK: - CaseIterable

    func testAllCases() {
        XCTAssertEqual(Sport.allCases.count, 3)
    }

    // MARK: - Identifiable

    func testIdMatchesRawValue() {
        XCTAssertEqual(Sport.rower.id, "rower")
        XCTAssertEqual(Sport.skierg.id, "skierg")
        XCTAssertEqual(Sport.bike.id, "bike")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for sport in Sport.allCases {
            let data = try encoder.encode(sport)
            let decoded = try decoder.decode(Sport.self, from: data)
            XCTAssertEqual(sport, decoded)
        }
    }
}
