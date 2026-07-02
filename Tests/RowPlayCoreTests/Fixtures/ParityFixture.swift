import Foundation

/// A single parity check: inputs and expected outputs for cross-platform comparison.
struct ParityFixture<Input: Codable & Equatable, Output: Codable & Equatable>: Codable {
    let name: String
    let input: Input
    let expected: Output

    init(name: String, input: Input, expected: Output) {
        self.name = name
        self.input = input
        self.expected = expected
    }
}
