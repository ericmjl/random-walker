import Foundation

/// Deterministic-friendly randomness facade for walk synthesis.
public protocol RandomWalkRNG {
    mutating func nextUInt64() -> UInt64
    mutating func unitUniform(in range: ClosedRange<Double>) -> Double
    mutating func intUniform(in range: ClosedRange<Int>) -> Int
}

/// SplitMix64 in 64-bit, suitable for repeatable tests.
public struct SplitMix64RNG: RandomWalkRNG, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unitUniform(in range: ClosedRange<Double>) -> Double {
        let u = Double(nextUInt64() % 1_000_000) / 999_999.0
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }

    public mutating func intUniform(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        let draw = nextUInt64() % max(span, 1)
        return range.lowerBound + Int(draw)
    }
}

extension SystemRandomNumberGenerator: RandomWalkRNG {
    public mutating func nextUInt64() -> UInt64 {
        UInt64.random(in: .min ... .max, using: &self)
    }

    public mutating func unitUniform(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    public mutating func intUniform(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}
