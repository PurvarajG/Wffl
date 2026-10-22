import Foundation

struct SampleMeeting: Identifiable, Hashable {
    let id: Int
    let title: String
    let day: String
    let time: String
    let minutes: Int
    let imported: Bool
    let speakers: [String]

    var duration: String { minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min" }
    var meta: String { "\(day) · \(time) · \(duration)" }
}

struct Line: Identifiable {
    let id = UUID()
    let at: String
    let who: String
    let text: String
}

enum Sample {
    static let meetings: [SampleMeeting] = [
        .init(id: 1, title: "Weekly product sync", day: "Today", time: "10:30", minutes: 42, imported: false, speakers: ["Me", "Priya", "Daniel"]),
        .init(id: 2, title: "Design review: onboarding", day: "Yesterday", time: "15:00", minutes: 28, imported: false, speakers: ["Me", "Priya"]),
        .init(id: 3, title: "Mandir AV planning", day: "Monday", time: "19:30", minutes: 65, imported: false, speakers: ["Me", "Speaker 2", "Speaker 3"]),
        .init(id: 4, title: "1:1 with Sam", day: "18 Oct", time: "09:00", minutes: 31, imported: false, speakers: ["Me", "Sam"]),
        .init(id: 5, title: "Interview: iOS engineer", day: "16 Oct", time: "14:00", minutes: 54, imported: false, speakers: ["Me", "Speaker 2"]),
        .init(id: 6, title: "Sunday satsang", day: "12 Oct", time: "17:00", minutes: 82, imported: true, speakers: ["Speaker 1"]),
        .init(id: 7, title: "Voice memo: ideas", day: "9 Oct", time: "22:14", minutes: 6, imported: true, speakers: ["Me"]),
    ]

    static let groups: [(String, [SampleMeeting])] = [
        ("Today", meetings.filter { $0.day == "Today" }),
        ("This week", meetings.filter { ["Yesterday", "Monday"].contains($0.day) }),
        ("Earlier", meetings.filter { !["Today", "Yesterday", "Monday"].contains($0.day) }),
    ]

    static let transcript: [Line] = [
        .init(at: "00:41", who: "Me", text: "Where are we on the first-run download?"),
        .init(at: "00:46", who: "Priya", text: "The flow works, but you can’t tell how big the model is."),
        .init(at: "00:58", who: "Me", text: "We show the size first. Then the button."),
        .init(at: "01:12", who: "Daniel", text: "And if they’re on a hotspot we say so before it starts, not halfway through."),
        .init(at: "01:30", who: "Priya", text: "I can mock both states by Thursday."),
        .init(at: "01:44", who: "Me", text: "Good. Let’s keep the default on Parakeet for English and offer BAPS Whisper next to it."),
        .init(at: "02:05", who: "Daniel", text: "Release notes should say the old recordings stay where they are."),
    ]

    static let live: [Line] = [
        .init(at: "18:02", who: "Them", text: "So the export keeps speaker names?"),
        .init(at: "18:09", who: "Me", text: "Yes, once you rename them they carry into the Markdown."),
        .init(at: "18:20", who: "Them", text: "Then I’ll send the notes straight after the call."),
    ]

    static let overview = "The first-run model download is clear except for its size. The team agreed to show the size before the download button, warn on metered connections up front, and keep Parakeet as the English default with BAPS Whisper offered beside it."
    static let decisions = [
        "Show the model size before the download starts.",
        "Warn about metered connections before, not during, the download.",
        "Parakeet stays the default for English; BAPS Whisper is offered next to it.",
    ]
    static let actions = [
        ("Priya", "Mock the size-first and metered states", "Thu"),
        ("Daniel", "Draft release notes: recordings stay where they are", "Fri"),
        ("Me", "Check BAPS Whisper download on a hotspot", "Fri"),
    ]
}
