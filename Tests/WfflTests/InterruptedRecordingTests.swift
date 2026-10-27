import AVFoundation
import XCTest
@testable import Wffl

final class InterruptedRecordingTests: XCTestCase {
    /// A WAV whose writer died before closing it: the recorder's own format, header sizes left at zero.
    func testRepairMakesAnUnclosedRecordingReadable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecordingFileWriter()
        try writer.start(url: url)
        writer.append(mic: Array(repeating: 0.1, count: 48_000), sys: Array(repeating: -0.1, count: 48_000))
        _ = writer.finish()

        let handle = try FileHandle(forUpdating: url)
        let head = try XCTUnwrap(handle.read(upToCount: 8192))
        let dataAt = try XCTUnwrap(head.range(of: Data("data".utf8))).lowerBound
        try handle.seek(toOffset: 4); try handle.write(contentsOf: Data(count: 4))
        try handle.seek(toOffset: UInt64(dataAt + 4)); try handle.write(contentsOf: Data(count: 4))
        try handle.close()
        XCTAssertEqual((try? AVAudioFile(forReading: url))?.length ?? 0, 0, "unrepaired file must be unreadable or empty")

        let seconds = try XCTUnwrap(InterruptedRecording.repair(url: url))
        XCTAssertEqual(seconds, 1, accuracy: 0.001)
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 48_000)
    }

    func testRepairLeavesANonWavAlone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 7, count: 100).write(to: url)
        XCTAssertNil(InterruptedRecording.repair(url: url))
    }
}
