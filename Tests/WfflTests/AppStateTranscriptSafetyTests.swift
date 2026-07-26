import XCTest
@testable import Wffl

/// T-01: the manual "Re-transcribe" path used to delete a meeting's segments
/// *before* running the replacement transcription (`AppState.swift:529-534`
/// at commit `7bd2c7b`). If that replacement then failed, was cancelled, or
/// the app quit mid-run, the transcript was gone with nothing to restore it.
///
/// A true black-box test of this would construct `AppState` and drive
/// `retranscribe` end to end, but `AppState.init()` calls
/// `setUpMeetingSentinel()`, which calls `UNUserNotificationCenter.current()`
/// — that aborts the whole process with `bundleProxyForCurrentProcess is nil`
/// when run from the `swift test` command-line host (no app bundle). That is
/// a pre-existing gap unrelated to T-01 and out of scope to fix here, so
/// `AppState` cannot safely be instantiated from any test in this target.
///
/// Instead this locks down the actual guarantee at the source level: the
/// unconditional pre-delete is gone, `runTranscription` is always called
/// with `replaceExisting: true`, and `deleteSegments` has exactly the call
/// sites the plan's own Auditor check requires (the `Database` definition
/// and the guarded call inside `runTranscription`). If a future change
/// reintroduces an early delete, this fails.
final class AppStateTranscriptSafetyTests: XCTestCase {
    private func readAppStateSource() throws -> String {
        // #filePath of this test file lives at Tests/WfflTests/...; walk up
        // to the package root and into Sources/Wffl/AppState.swift so this
        // doesn't depend on the working directory `swift test` is invoked from.
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent() // AppStateTranscriptSafetyTests.swift -> WfflTests/
            .deletingLastPathComponent() // WfflTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> package root
        let appStatePath = packageRoot.appendingPathComponent("Sources/Wffl/AppState.swift")
        return try String(contentsOf: appStatePath, encoding: .utf8)
    }

    private struct AnchorNotFound: Error {}

    private func retranscribeBody(_ source: String) throws -> String {
        guard let start = source.range(of: "func retranscribe(_ meeting: Meeting"),
              let bodyStart = source.range(of: "{", range: start.upperBound..<source.endIndex) else {
            XCTFail("could not locate retranscribe(_:quietly:) in AppState.swift")
            throw AnchorNotFound()
        }
        // Grab a generous fixed window rather than brace-matching — the
        // function body is short and this is a regression guard, not a parser.
        let window = source[bodyStart.upperBound...].prefix(1200)
        return String(window)
    }

    func testRetranscribeNoLongerDeletesBeforeTranscribing() throws {
        let source = try readAppStateSource()
        let body = try retranscribeBody(source)

        XCTAssertFalse(
            body.contains("deleteSegments"),
            "retranscribe() must not delete segments itself — replacement must be staged by runTranscription and only swapped in on success (T-01)."
        )
        XCTAssertTrue(
            body.contains("replaceExisting: true"),
            "retranscribe() must call runTranscription with replaceExisting: true unconditionally, so both the manual and quiet paths stage-then-swap (T-01)."
        )
    }

    func testDeleteSegmentsHasOnlyTheExpectedCallSites() throws {
        let source = try readAppStateSource()
        let callSites = source.components(separatedBy: "\n").enumerated()
            .filter { $0.element.contains("deleteSegments") }

        // Exactly one call site left in AppState.swift: the guarded replace
        // inside runTranscription (`if replaceExisting, !out.isEmpty { ... }`).
        // T-02 will move this into a transactional replaceSegments; until
        // then it must stay singular and guarded.
        XCTAssertEqual(callSites.count, 1,
            "expected exactly one deleteSegments call site in AppState.swift, found \(callSites.count): \(callSites.map(\.element))")

        if let (lineIndex, _) = callSites.first {
            let lines = source.components(separatedBy: "\n")
            let precedingContext = lines[max(0, lineIndex - 3)...lineIndex].joined(separator: "\n")
            XCTAssertTrue(
                precedingContext.contains("replaceExisting") && precedingContext.contains("!out.isEmpty"),
                "the remaining deleteSegments call must stay guarded by `replaceExisting` and `!out.isEmpty` so it only fires after a successful, non-empty transcription:\n\(precedingContext)"
            )
        }
    }
}
