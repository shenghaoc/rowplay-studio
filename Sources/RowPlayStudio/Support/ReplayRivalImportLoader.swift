import Foundation
import RowPlayCore

/// View-owned token used to discard import completions after a newer rival
/// selection. Keeping the comparison separate makes the race rule explicit
/// and independently testable.
struct ReplayRivalImportGeneration: Equatable, Sendable {
    private(set) var current: UInt64 = 0

    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func accepts(_ token: UInt64) -> Bool {
        token == current
    }
}

/// Bounded file-I/O boundary for the user-selected rival import workflow.
enum ReplayRivalImportLoader {
    /// Keeps the balanced security-scope lifetime in the same synchronous
    /// operation as the file read. Call this from the detached import task so
    /// security-scope acquisition, I/O, parsing, and release cannot drift apart.
    static func loadSecurityScopedRival(from url: URL, fileName: String) throws -> ReplayRival {
        try Task.checkCancellation()
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try loadRival(from: url, fileName: fileName)
    }

    static func loadRival(from url: URL, fileName: String) throws -> ReplayRival {
        try Task.checkCancellation()
        let data = try readData(from: url)
        try Task.checkCancellation()
        let parsed = try ReplayRivalFileParser.parse(data: data, fileName: fileName)
        try Task.checkCancellation()
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
                try Task.checkCancellation()
                let remaining = readLimit - data.count
                let requestSize = min(remaining, 1_048_576)
                guard let chunk = try handle.read(upToCount: requestSize), !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
            }
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw ReplayRivalFileParserError.unreadable
        }

        guard data.count <= maximumBytes else {
            throw ReplayRivalFileParserError.fileTooLarge
        }
        return data
    }
}
