import Foundation

/// Loads `.json` fixture files from the test bundle.
enum ParityFixtureLoader {
    static func loadJSON<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            throw ParityFixtureError.fileNotFound(filename)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func loadJSONData(from filename: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            throw ParityFixtureError.fileNotFound(filename)
        }
        return try Data(contentsOf: url)
    }
}

enum ParityFixtureError: Error, CustomStringConvertible {
    case fileNotFound(String)

    var description: String {
        switch self {
        case .fileNotFound(let name):
            return "Fixture file not found: \(name).json"
        }
    }
}
