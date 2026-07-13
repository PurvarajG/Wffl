import Foundation

/// Per-meeting evidence gate for the Gujarati/BAPS retrofit layers (glossary
/// prompt, forced fuzzy correction, LLM corrector). Every meeting starts
/// neutral; the gate only flips on once the *raw* ASR output (before any
/// correction — otherwise forced rewrites would confirm themselves) shows
/// enough distinct vocabulary tripwires that the meeting genuinely contains
/// BAPS/Gujarati speech. Never disables once enabled.
///
/// Confined to the transcriber's serial processing queue: `observe` is only
/// ever called from that queue. `enabled` is read from other queues/actors
/// (e.g. the main actor between segments) — that's a benign racy read of a
/// Bool that only ever flips false -> true, so no lock is needed.
final class VocabularyGate {
    enum Mode: String { case auto, on, off }

    private(set) var enabled: Bool
    private let mode: Mode
    private var hits: Set<String> = []
    static let threshold = 3

    init(mode: Mode) {
        self.mode = mode
        enabled = (mode == .on)
    }

    /// Feed RAW ASR text (before any correction). Returns true if this call
    /// flipped the gate on.
    @discardableResult
    func observe(rawText: String) -> Bool {
        guard mode == .auto, !enabled, !rawText.isEmpty else { return false }
        let lower = rawText.lowercased()
        let collapsedRaw = String(lower.filter { !$0.isWhitespace })

        for tripwire in Vocabulary.shared.tripwires {
            let needle = tripwire.text.lowercased()
            if wordBoundaryMatch(needle, in: lower) {
                hits.insert(needle)
                continue
            }
            // ASR sometimes splits a compound/phrase term across a word
            // boundary it shouldn't ("sat sang" for "satsang", "swami
            // narayan" for "Swaminarayan") — catch that by comparing the
            // space-collapsed forms too.
            guard tripwire.collapsible else { continue }
            let collapsedNeedle = String(needle.filter { !$0.isWhitespace })
            if collapsedNeedle.count >= 5, collapsedRaw.contains(collapsedNeedle) {
                hits.insert(collapsedNeedle)
            }
        }

        guard hits.count >= Self.threshold else { return false }
        enabled = true
        return true
    }

    private func wordBoundaryMatch(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
    }
}
