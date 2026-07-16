import Foundation

/// Intermediate sample shared by the format-specific rival decoders before
/// common validation, ordering, and pace/power derivation.
struct RawRivalSample {
    var t: TimeInterval
    var d: Double
    var pace: TimeInterval?
    var spm: Double?
    var hr: Int?
    var watts: Double?
}

/// Convert an optional positive metric to the nearest `Int` without relying on
/// `Double(Int.max)`, which rounds up to an unrepresentable value on 64-bit
/// platforms.
func checkedPositiveRoundedInt(_ value: Double) -> Int? {
    guard value.isFinite, value > 0 else { return nil }
    return Int(exactly: value.rounded())
}

@inline(__always)
func checkReplayImportCancellation() throws {
    try Task<Never, Never>.checkCancellation()
}
