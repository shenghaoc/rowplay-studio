import Foundation
import RowPlayCore

/// Bounded file-I/O boundary for the user-selected rival import workflow.
/// Security-scope acquisition remains with the presenting SwiftUI view.
enum ReplayRivalImportLoader {
    static func loadRival(from url: URL, fileName: String) throws -> ReplayRival {
        let data = try readData(from: url)
        let parsed = try ReplayRivalFileParser.parse(data: data, fileName: fileName)
        guard let rival = ReplayRivalFactory.makeImportedRival(
            strokes: parsed.strokes,
            fileName: parsed.fileName
        ) else {
            throw ReplayRivalFileParserError.tooFewSamples
        }
        return rival
    }

    /// Reads no more than `maximumBytes + 1`, allowing an oversized file to be
    /// rejected without first allocating its entire contents.
    static func readData(
        from url: URL,
        maximumBytes: Int = ReplayRivalFileParser.maximumFileSizeBytes
    ) throws -> Data {
        guard maximumBytes >= 0, maximumBytes < Int.max else {
            throw ReplayRivalFileParserError.fileTooLarge
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ReplayRivalFileParserError.unreadable
        }
        defer { try? handle.close() }

        let readLimit = maximumBytes + 1
        var data = Data()
        data.reserveCapacity(min(readLimit, 1_048_576))

        do {
            while data.count < readLimit {
                let remaining = readLimit - data.count
                let requestSize = min(remaining, 1_048_576)
                guard let chunk = try handle.read(upToCount: requestSize), !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
            }
        } catch {
            throw ReplayRivalFileParserError.unreadable
        }

        guard data.count <= maximumBytes else {
            throw ReplayRivalFileParserError.fileTooLarge
        }
        return data
    }
}
