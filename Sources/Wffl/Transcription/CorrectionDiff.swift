import Foundation

/// Works out which words a user changed when they corrected a transcript
/// line. Each returned pair is a candidate alias for the normalization pack:
/// "the engine wrote `heard`, the user meant `meant`".
///
/// Word-level longest-common-subsequence alignment, compared case-insensitively
/// with surrounding punctuation stripped. Only replacements count: a word the
/// user simply added or removed has no mis-heard counterpart, and a rewrite of
/// more than `maxSpanWords` words is a rephrase, not a spelling fix.
enum CorrectionDiff {
    struct Pair: Equatable, Hashable {
        let heard: String
        let meant: String
    }

    static let maxSpanWords = 3

    static func pairs(old: String, new: String) -> [Pair] {
        let a = words(old), b = words(new)
        let ak = a.map { $0.lowercased() }, bk = b.map { $0.lowercased() }

        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = ak[i] == bk[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var out: [Pair] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            defer { removed = []; added = [] }
            guard !removed.isEmpty, !added.isEmpty,
                  removed.count <= maxSpanWords, added.count <= maxSpanWords else { return }
            let pair = Pair(heard: removed.joined(separator: " "), meant: added.joined(separator: " "))
            if !out.contains(pair) { out.append(pair) }
        }

        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, ak[i] == bk[j] {
                flush(); i += 1; j += 1
            } else if j < b.count, i == a.count || lcs[i][j + 1] >= lcs[i + 1][j] {
                added.append(b[j]); j += 1
            } else {
                removed.append(a[i]); i += 1
            }
        }
        flush()
        return out
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
}
