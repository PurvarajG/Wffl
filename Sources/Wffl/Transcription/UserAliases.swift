import Foundation

/// Aliases the user taught Wffl by correcting a transcript line. Kept in its
/// own file, never inside `normalization-pack.json`: that file is replaced
/// whenever a release ships a newer bundled pack, and a user's own fixes must
/// survive that.
///
/// This type only stores. Whether an alias is safe to use is still decided by
/// `NormalizationPack.Loaded(validating:)` — an English-word alias is stored
/// here and rejected there, so the user can see why it isn't applied.
final class UserAliases {
    static let fileName = "normalization-pack.user.json"
    static let shared = UserAliases(fileURL: Database.appSupportDir.appendingPathComponent(fileName))

    private struct File: Codable { var entries: [NormalizationPack.Entry] }

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) { self.fileURL = fileURL }

    func entries() -> [NormalizationPack.Entry] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    func add(heard: String, meant: String) {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let meant = meant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !meant.isEmpty, heard.lowercased() != meant.lowercased() else { return }
        lock.lock(); defer { lock.unlock() }
        var all = read()
        if let i = all.firstIndex(where: { $0.canonical == meant }) {
            guard !all[i].aliases.contains(where: { $0.lowercased() == heard.lowercased() }) else { return }
            all[i].aliases.append(heard)
        } else {
            all.append(NormalizationPack.Entry(canonical: meant, aliases: [heard]))
        }
        write(all)
    }

    func remove(heard: String, meant: String) {
        lock.lock(); defer { lock.unlock() }
        var all = read()
        guard let i = all.firstIndex(where: { $0.canonical == meant }) else { return }
        all[i].aliases.removeAll { $0.lowercased() == heard.lowercased() }
        if all[i].aliases.isEmpty { all.remove(at: i) }
        write(all)
    }

    private func read() -> [NormalizationPack.Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.entries
    }

    private func write(_ entries: [NormalizationPack.Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(File(entries: entries)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
