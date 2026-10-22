import Foundation

// Sample library for the prototype. Invented content, labelled as such wherever it could be mistaken.

struct SampleMeeting: Identifiable, Hashable {
    let id: Int
    let title: String
    let weekday: String
    let dayNumber: Int
    let time: String
    let minutes: Int
    let imported: Bool
    let speakers: [String]
    let gist: String
    let decisions: Int
    let actions: Int

    var duration: String { minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min" }
    var clock: String { String(format: "%d:%02d:00", minutes / 60, minutes % 60) }
    var relativeDay: String {
        switch dayNumber { case 22: "Today"; case 21: "Yesterday"; default: "\(weekday) \(dayNumber) Oct" }
    }
}

struct Line: Identifiable {
    let id = UUID()
    let at: String
    let who: String
    let text: String
}

struct ActionItem: Identifiable {
    let id = UUID()
    let text: String
    let owner: String
    let due: String
    let meeting: String
    var done = false
}

struct SearchHit: Identifiable {
    let id = UUID()
    let meeting: String
    let when: String
    let at: String
    let who: String
    let before: String
    let match: String
    let after: String
}

enum Sample {
    static let meetings: [SampleMeeting] = [
        .init(id: 1, title: "Weekly product sync", weekday: "Thu", dayNumber: 22, time: "10:30", minutes: 42, imported: false,
              speakers: ["Me", "Priya", "Daniel"], gist: "Show the model size before the download starts.", decisions: 3, actions: 3),
        .init(id: 8, title: "Onboarding copy pass", weekday: "Thu", dayNumber: 22, time: "15:00", minutes: 18, imported: false,
              speakers: ["Me", "Priya"], gist: "First screen asks for the microphone, nothing else.", decisions: 1, actions: 2),
        .init(id: 2, title: "Design review: onboarding", weekday: "Wed", dayNumber: 21, time: "15:00", minutes: 28, imported: false,
              speakers: ["Me", "Priya"], gist: "Drop the setup checklist from Home; show readiness only when something is missing.", decisions: 2, actions: 1),
        .init(id: 3, title: "Mandir AV planning", weekday: "Mon", dayNumber: 19, time: "19:30", minutes: 65, imported: false,
              speakers: ["Me", "Speaker 2", "Speaker 3"], gist: "Record the Sunday sabha from the desk feed, not the room mic.", decisions: 2, actions: 4),
        .init(id: 4, title: "1:1 with Sam", weekday: "Sat", dayNumber: 18, time: "09:00", minutes: 31, imported: false,
              speakers: ["Me", "Sam"], gist: "Sam takes over release notes from 1.10.", decisions: 1, actions: 1),
        .init(id: 5, title: "Interview: iOS engineer", weekday: "Thu", dayNumber: 16, time: "14:00", minutes: 54, imported: false,
              speakers: ["Me", "Speaker 2"], gist: "Strong on audio APIs; follow up on SwiftUI depth.", decisions: 0, actions: 1),
        .init(id: 6, title: "Sunday satsang", weekday: "Sun", dayNumber: 12, time: "17:00", minutes: 82, imported: true,
              speakers: ["Speaker 1"], gist: "Transcribed with BAPS Whisper; Gujarati terms kept in Latin letters.", decisions: 0, actions: 0),
        .init(id: 7, title: "Voice memo: ideas", weekday: "Thu", dayNumber: 9, time: "22:14", minutes: 6, imported: true,
              speakers: ["Me"], gist: "A menu bar button that starts recording the current call.", decisions: 0, actions: 1),
    ]

    static var recent: [SampleMeeting] { Array(meetings.prefix(5)) }

    /// The week ledger: Thursday 22 back to Monday 19, with an empty Tuesday.
    static let week: [(weekday: String, number: Int, meetings: [SampleMeeting])] = [
        ("Thursday", 22, meetings.filter { $0.dayNumber == 22 }),
        ("Wednesday", 21, meetings.filter { $0.dayNumber == 21 }),
        ("Tuesday", 20, []),
        ("Monday", 19, meetings.filter { $0.dayNumber == 19 }),
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
        "Warn about metered connections before the download, not during it.",
        "Parakeet stays the default for English; BAPS Whisper is offered next to it.",
    ]

    static let actions: [ActionItem] = [
        .init(text: "Mock the size-first and metered states", owner: "Priya", due: "Thu", meeting: "Weekly product sync"),
        .init(text: "Draft release notes: recordings stay where they are", owner: "Daniel", due: "Fri", meeting: "Weekly product sync"),
        .init(text: "Check BAPS Whisper download on a hotspot", owner: "Me", due: "Fri", meeting: "Weekly product sync"),
        .init(text: "Route the desk feed into the Mac on Sunday", owner: "Me", due: "Sun", meeting: "Mandir AV planning"),
        .init(text: "Rewrite the microphone permission screen", owner: "Priya", due: "Mon", meeting: "Onboarding copy pass"),
        .init(text: "Send Sam the 1.10 release checklist", owner: "Me", due: "Done", meeting: "1:1 with Sam", done: true),
    ]

    static let suggestions = ["model size", "what Priya owns this week", "desk feed", "release notes"]

    static let hits: [SearchHit] = [
        .init(meeting: "Weekly product sync", when: "Today", at: "00:46", who: "Priya",
              before: "The flow works, but you can’t tell how big the ", match: "model size", after: " is going to be."),
        .init(meeting: "Weekly product sync", when: "Today", at: "00:58", who: "Me",
              before: "We show the ", match: "model size", after: " first. Then the button."),
        .init(meeting: "Design review: onboarding", when: "Yesterday", at: "12:31", who: "Priya",
              before: "If the ", match: "model size", after: " is on the card, nobody needs the checklist."),
    ]

    static let chapters: [(String, String)] = [
        ("00:00", "First-run download"), ("08:40", "Metered connections"), ("19:15", "Default engine"), ("31:02", "Release notes"),
    ]
    static let talkShare: [(String, Double)] = [("Me", 0.41), ("Priya", 0.34), ("Daniel", 0.25)]
}
