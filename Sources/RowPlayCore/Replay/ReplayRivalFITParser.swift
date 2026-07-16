import Foundation

/// Focused, bounded decoder for the FIT record-message subset used by rivals.
enum ReplayRivalFITParser {
    private static let recordGlobal: UInt16 = 20

    private struct FieldDefinition {
        var number: Int
        var size: Int
        var baseType: UInt8
    }

    private struct MessageDefinition {
        var global: UInt16
        var littleEndian: Bool
        var fields: [FieldDefinition]
    }

    private struct Record {
        var timestamp: UInt32?
        var distance: UInt32?
        var speed: UInt32?
        var power: UInt16?
        var cadence: UInt8?
        var heartRate: UInt8?
    }

    /// Content sniffing requires a structurally plausible FIT header, not merely
    /// the four `.FIT` bytes, which can occur at the same offset in ordinary CSV.
    static func hasPlausibleSignature(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let start = data.startIndex
        let headerSize = Int(data[start])
        guard headerSize >= 12, headerSize <= 64, headerSize <= data.count else {
            return false
        }
        let signatureStart = data.index(start, offsetBy: 8)
        let signatureEnd = data.index(signatureStart, offsetBy: 4)
        guard data[signatureStart..<signatureEnd].elementsEqual([0x2E, 0x46, 0x49, 0x54]) else {
            return false
        }

        // A valid signature alone is not enough for content sniffing: ordinary
        // text can contain `.FIT` at byte 8. The little-endian payload length
        // must also fit inside the supplied bytes.
        let sizeStart = data.index(start, offsetBy: 4)
        let dataSize = (0..<4).reduce(UInt32(0)) { value, offset in
            value | (UInt32(data[data.index(sizeStart, offsetBy: offset)]) << UInt32(offset * 8))
        }
        return Int(dataSize) <= data.count - headerSize
    }

    static func parse(_ data: Data, sampleLimit: Int) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        guard data.count >= 14 else { throw ReplayRivalFileParserError.malformed }
        return try data.withUnsafeBytes { rawBuffer -> [RawRivalSample] in
            guard let base = rawBuffer.baseAddress else {
                throw ReplayRivalFileParserError.unreadable
            }
            let byteCount = rawBuffer.count
            let headerSize = Int(base.load(as: UInt8.self))
            guard headerSize >= 12, headerSize <= byteCount else {
                throw ReplayRivalFileParserError.malformed
            }

            let dataSize = Int(readUInt32(base, offset: 4, littleEndian: true))
            guard hasPlausibleSignature(data) else {
                throw ReplayRivalFileParserError.malformed
            }
            guard dataSize <= byteCount - headerSize else {
                throw ReplayRivalFileParserError.malformed
            }
            let end = headerSize + dataSize

            var definitions: [Int: MessageDefinition] = [:]
            var records: [Record] = []
            var lastTimestamp: UInt32?
            var position = headerSize
            var parsedMessageCount = 0

            while position < end {
                if parsedMessageCount.isMultiple(of: 256) {
                    try checkReplayImportCancellation()
                }
                parsedMessageCount &+= 1
                let header = Int(readUInt8(base, offset: position))
                position += 1

                if header & 0x80 != 0 {
                    let local = (header >> 5) & 0x3
                    let timeOffset = UInt32(header & 0x1F)
                    guard let definition = definitions[local],
                          let previousTimestamp = lastTimestamp else {
                        throw ReplayRivalFileParserError.malformed
                    }

                    var record = Record()
                    var timestamp = (previousTimestamp & ~UInt32(0x1F)) | timeOffset
                    if timestamp < previousTimestamp {
                        timestamp &+= 0x20
                    }
                    record.timestamp = timestamp

                    for field in definition.fields where field.number != 253 {
                        guard field.size >= 0, position + field.size <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        if definition.global == recordGlobal,
                           field.number >= 0,
                           let value = readBase(
                               base,
                               offset: position,
                               baseType: field.baseType,
                               littleEndian: definition.littleEndian,
                               end: position + field.size
                           ) {
                            assignRecordField(&record, number: field.number, value: value)
                        }
                        position += field.size
                    }

                    lastTimestamp = timestamp
                    if definition.global == recordGlobal {
                        records.append(record)
                        if records.count > sampleLimit {
                            throw ReplayRivalFileParserError.tooManySamples
                        }
                    }
                    continue
                }

                let local = header & 0x0F
                if header & 0x40 != 0 {
                    guard position + 5 <= end else {
                        throw ReplayRivalFileParserError.malformed
                    }
                    let architecture = readUInt8(base, offset: position + 1)
                    guard architecture == 0 || architecture == 1 else {
                        throw ReplayRivalFileParserError.malformed
                    }
                    let littleEndian = architecture == 0
                    let global = readUInt16(base, offset: position + 2, littleEndian: littleEndian)
                    let fieldCount = Int(readUInt8(base, offset: position + 4))
                    position += 5
                    var fields: [FieldDefinition] = []
                    fields.reserveCapacity(fieldCount)
                    for _ in 0..<fieldCount {
                        guard position + 3 <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        fields.append(FieldDefinition(
                            number: Int(readUInt8(base, offset: position)),
                            size: Int(readUInt8(base, offset: position + 1)),
                            baseType: readUInt8(base, offset: position + 2)
                        ))
                        position += 3
                    }
                    if header & 0x20 != 0 {
                        guard position < end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        let developerFieldCount = Int(readUInt8(base, offset: position))
                        position += 1
                        for _ in 0..<developerFieldCount {
                            guard position + 3 <= end else {
                                throw ReplayRivalFileParserError.malformed
                            }
                            fields.append(FieldDefinition(
                                number: -1,
                                size: Int(readUInt8(base, offset: position + 1)),
                                baseType: 0x0D
                            ))
                            position += 3
                        }
                    }
                    definitions[local] = MessageDefinition(
                        global: global,
                        littleEndian: littleEndian,
                        fields: fields
                    )
                } else {
                    guard let definition = definitions[local] else {
                        throw ReplayRivalFileParserError.malformed
                    }
                    var record = Record()
                    for field in definition.fields {
                        guard field.size >= 0, position + field.size <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        // A timestamp on any global message establishes the base
                        // used by a later compressed-timestamp message.
                        if field.number >= 0,
                           let value = readBase(
                               base,
                               offset: position,
                               baseType: field.baseType,
                               littleEndian: definition.littleEndian,
                               end: position + field.size
                           ) {
                            if field.number == 253 {
                                assignRecordField(&record, number: field.number, value: value)
                            } else if definition.global == recordGlobal {
                                assignRecordField(&record, number: field.number, value: value)
                            }
                        }
                        position += field.size
                    }
                    if let timestamp = record.timestamp {
                        lastTimestamp = timestamp
                    }
                    if definition.global == recordGlobal, record.timestamp != nil {
                        records.append(record)
                        if records.count > sampleLimit {
                            throw ReplayRivalFileParserError.tooManySamples
                        }
                    }
                }
            }

            guard !records.isEmpty else { return [] }

            var firstTimestamp = UInt32.max
            for (index, record) in records.enumerated() {
                if index.isMultiple(of: 4_096) {
                    try checkReplayImportCancellation()
                }
                if let timestamp = record.timestamp, timestamp < firstTimestamp {
                    firstTimestamp = timestamp
                }
            }
            guard firstTimestamp != UInt32.max else { return [] }

            var output: [RawRivalSample] = []
            output.reserveCapacity(records.count)
            for (index, record) in records.enumerated() {
                if index.isMultiple(of: 4_096) {
                    try checkReplayImportCancellation()
                }
                guard let timestamp = record.timestamp else { continue }
                let speedMetersPerSecond = record.speed.map { Double($0) / 1_000.0 }
                let pace: Double? = {
                    guard let speed = speedMetersPerSecond, speed > 0 else { return nil }
                    return 500.0 / speed
                }()
                let distance = record.distance.map { Double($0) / 100.0 } ?? .nan
                let time = Double(timestamp &- firstTimestamp)
                guard time.isFinite, distance.isFinite else { continue }
                output.append(RawRivalSample(
                    t: time,
                    d: distance,
                    pace: pace,
                    spm: record.cadence.map { Double($0) },
                    hr: record.heartRate.map { Int($0) },
                    watts: record.power.map { Double($0) }
                ))
            }
            return output
        }
    }

    private static func assignRecordField(_ record: inout Record, number: Int, value: Double) {
        switch number {
        case 253:
            if value >= 0, value <= Double(UInt32.max) {
                record.timestamp = UInt32(value)
            }
        case 5:
            if value >= 0, value <= Double(UInt32.max) {
                record.distance = UInt32(value)
            }
        case 6:
            if value >= 0, value <= Double(UInt32.max) {
                record.speed = UInt32(value)
            }
        case 73:
            if record.speed == nil, value >= 0, value <= Double(UInt32.max) {
                record.speed = UInt32(value)
            }
        case 7:
            if value >= 0, value <= Double(UInt16.max) {
                record.power = UInt16(value)
            }
        case 4:
            if value >= 0, value <= Double(UInt8.max) {
                record.cadence = UInt8(value)
            }
        case 3:
            if value >= 0, value <= Double(UInt8.max) {
                record.heartRate = UInt8(value)
            }
        default:
            break
        }
    }

    private static func readBase(
        _ base: UnsafeRawPointer,
        offset: Int,
        baseType: UInt8,
        littleEndian: Bool,
        end: Int
    ) -> Double? {
        let type = baseType & 0x0F
        switch type {
        case 1:
            guard offset + 1 <= end else { return nil }
            let value = Int8(bitPattern: readUInt8(base, offset: offset))
            return value == 0x7F ? nil : Double(value)
        case 0, 2, 10, 13:
            guard offset + 1 <= end else { return nil }
            let value = readUInt8(base, offset: offset)
            return value == 0xFF ? nil : Double(value)
        case 3:
            guard offset + 2 <= end else { return nil }
            let value = Int16(bitPattern: readUInt16(base, offset: offset, littleEndian: littleEndian))
            return value == 0x7FFF ? nil : Double(value)
        case 4, 11:
            guard offset + 2 <= end else { return nil }
            let value = readUInt16(base, offset: offset, littleEndian: littleEndian)
            return value == 0xFFFF ? nil : Double(value)
        case 5:
            guard offset + 4 <= end else { return nil }
            let value = Int32(bitPattern: readUInt32(base, offset: offset, littleEndian: littleEndian))
            return value == 0x7FFF_FFFF ? nil : Double(value)
        case 6, 12:
            guard offset + 4 <= end else { return nil }
            let value = readUInt32(base, offset: offset, littleEndian: littleEndian)
            return value == 0xFFFF_FFFF ? nil : Double(value)
        case 8:
            guard offset + 4 <= end else { return nil }
            let value = Float(bitPattern: readUInt32(base, offset: offset, littleEndian: littleEndian))
            return value.isNaN ? nil : Double(value)
        case 9:
            guard offset + 8 <= end else { return nil }
            let value = Double(bitPattern: readUInt64(base, offset: offset, littleEndian: littleEndian))
            return value.isNaN ? nil : value
        default:
            return nil
        }
    }

    private static func readUInt8(_ base: UnsafeRawPointer, offset: Int) -> UInt8 {
        base.load(fromByteOffset: offset, as: UInt8.self)
    }

    private static func readUInt16(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt16 {
        let b0 = UInt16(base.load(fromByteOffset: offset, as: UInt8.self))
        let b1 = UInt16(base.load(fromByteOffset: offset + 1, as: UInt8.self))
        return littleEndian ? (b0 | (b1 &<< 8)) : ((b0 &<< 8) | b1)
    }

    private static func readUInt32(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt32 {
        let b0 = UInt32(base.load(fromByteOffset: offset, as: UInt8.self))
        let b1 = UInt32(base.load(fromByteOffset: offset + 1, as: UInt8.self))
        let b2 = UInt32(base.load(fromByteOffset: offset + 2, as: UInt8.self))
        let b3 = UInt32(base.load(fromByteOffset: offset + 3, as: UInt8.self))
        if littleEndian {
            return b0 | (b1 &<< 8) | (b2 &<< 16) | (b3 &<< 24)
        }
        return (b0 &<< 24) | (b1 &<< 16) | (b2 &<< 8) | b3
    }

    private static func readUInt64(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt64 {
        let first = UInt64(readUInt32(base, offset: offset, littleEndian: littleEndian))
        let second = UInt64(readUInt32(base, offset: offset + 4, littleEndian: littleEndian))
        return littleEndian ? (first | (second &<< 32)) : (second | (first &<< 32))
    }
}
