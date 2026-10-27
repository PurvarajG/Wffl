import Foundation

/// Accumulates download callbacks without inventing progress when the size is unknown.
struct UpdateProgress {
    private(set) var bytesReceived: UInt64 = 0
    private(set) var expectedBytes: UInt64 = 0

    mutating func setExpected(_ length: UInt64) { expectedBytes = length }
    mutating func received(_ length: UInt64) {
        let (total, overflow) = bytesReceived.addingReportingOverflow(length)
        bytesReceived = overflow ? UInt64.max : total
    }
    var fraction: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(Double(bytesReceived) / Double(expectedBytes), 1)
    }
}
