import XCTest
@testable import Wffl

/// The mixer keeps real time: it never inserts silence into a track, and it
/// never stops recording one source because the other went quiet.
final class MixBusClockTests: XCTestCase {

    /// Seeded generator so every run sees the same audio.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testMixerAddsNoGapsWhenSourcesArriveInDifferentBursts() {
        let bus = MixBus()
        bus.systemEnabled = true
        var micOut: [Float] = []
        var sysOut: [Float] = []
        bus.onTracks = { mic, sys, _ in micOut += mic; sysOut += sys }

        // Ten seconds of audio on each side. Every input sample is 1.0, so any 0.0 in the output is a gap the mixer inserted.
        let total = 480_000
        var micSent = 0, sysSent = 0
        var rng = SeededRNG(state: 7)
        var tickIndex = 0
        while micSent < total || sysSent < total {
            tickIndex += 1
            let due = min(total, tickIndex * 9_600)   // both sources run at 48 kHz; only their burst sizes differ
            // Microphone: whole 4096-frame buffers, so it overshoots the tick by up to 4095 samples.
            while micSent < due {
                let n = min(4_096, total - micSent)
                bus.pushMic([Float](repeating: 1, count: n)); micSent += n
            }
            // System audio: 960-frame buffers, running up to two buffers late.
            let sysDue = due == total ? total : max(0, due - Int.random(in: 0...2, using: &rng) * 960)
            while sysSent < sysDue {
                let n = min(960, total - sysSent)
                bus.pushSystem([Float](repeating: 1, count: n)); sysSent += n
            }
            bus.tick()
        }
        bus.tick(flush: true)

        XCTAssertEqual(micOut.count, total, "output is exactly as long as the input")
        XCTAssertEqual(sysOut.count, total)
        XCTAssertFalse(micOut.contains(0), "no silence inserted into the microphone track")
        XCTAssertFalse(sysOut.contains(0), "no silence inserted into the system track")
    }

    func testMixerStopsWaitingForASourceThatStalls() {
        let bus = MixBus()
        bus.systemEnabled = true
        var seconds = 0.0
        bus.onTracks = { _, _, d in seconds += d }
        // System audio delivers nothing at all; the microphone must still be recorded.
        for _ in 0..<50 { bus.pushMic([Float](repeating: 1, count: 9_600)); bus.tick() }
        bus.tick(flush: true)
        XCTAssertEqual(seconds, 10, accuracy: 0.01)
    }

    func testMicOnlyRecordingPassesStraightThrough() {
        let bus = MixBus()
        bus.systemEnabled = false
        var micOut: [Float] = []
        bus.onTracks = { mic, _, _ in micOut += mic }
        for _ in 0..<5 { bus.pushMic([Float](repeating: 1, count: 4_096)); bus.tick() }
        XCTAssertEqual(micOut.count, 5 * 4_096)
    }
}
