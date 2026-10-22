import Combine
import SwiftUI

// Recording. The ink instrument at the top (state, timer, the dot field drawn from the real input
// level), the live draft as the main column, and notes that are stamped with the recording time.

struct LiveSession: View {
    @EnvironmentObject var app: AppState
    @State private var history: [Float] = Array(repeating: 0, count: 56)
    @State private var note = ""
    @State private var stamped: [(at: String, text: String)] = []
    private let tick = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var state: RecorderController.RecState { app.recorder.state }
    private var stateLabel: String {
        switch state {
        case .idle: "Idle"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .paused: "Paused"
        case .stopping: "Saving"
        }
    }
    private var meeting: Meeting? { app.meeting(app.recorder.activeMeetingId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            instrument
            HStack(alignment: .top, spacing: 24) {
                transcript.frame(maxWidth: .infinity, alignment: .topLeading)
                notesPanel.frame(width: 300)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(Theme.appBG.ignoresSafeArea())
        .onReceive(tick) { _ in
            guard state == .recording else { return }
            let level = max(app.recorder.micLevel, app.recorder.sysLevel)
            history.append(min(1, level * 2.2))
            if history.count > 56 { history.removeFirst(history.count - 56) }
        }
    }

    private var instrument: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if state == .recording { LiveDot(size: 8) } else { Circle().fill(Theme.panelDim).frame(width: 8, height: 8) }
                        Text(stateLabel).font(Theme.text(13, weight: .semibold))
                            .foregroundStyle(state == .recording ? Theme.live : Theme.panelInk)
                        Text(sourcesLabel).font(Theme.text(13)).foregroundStyle(Theme.panelDim)
                    }
                    Text(app.recorder.elapsed.asClock)
                        .font(Theme.display(76)).tracking(-3).monospacedDigit().foregroundStyle(Theme.panelInk)
                        .accessibilityLabel("Elapsed \(app.recorder.elapsed.asClock)")
                }
                .fixedSize()
                DotMatrix(history: history, rows: 9, dot: 6, live: state == .recording)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .opacity(state == .paused ? 0.45 : 1)
                    .accessibilityElement()
                    .accessibilityLabel(state == .recording ? "Input level, live" : "Input level, paused")
            }
            if let warning = app.recorder.audioWarning ?? app.recorder.errorMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Theme.text(12.5)).foregroundStyle(Theme.peach)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var sourcesLabel: String {
        let mic = app.recorder.micMuted ? "Microphone muted" : "Microphone"
        return app.recorder.systemAudioActive ? "\(mic) and Mac audio" : "\(mic) only, Mac audio off"
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Live transcript").heading(17)
                Text("A draft. It is transcribed again and cleaned up when you stop.")
                    .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if app.recorder.liveSegments.isEmpty {
                            Text(state == .preparing ? "Preparing audio and transcription…"
                                 : state == .paused ? "Paused. Your draft stays here."
                                 : state == .stopping ? "Saving the recording and draft transcript…"
                                 : "Listening. Words appear as they are recognised.")
                                .font(Theme.text(15)).foregroundStyle(Theme.secondary)
                        }
                        ForEach(Array(app.recorder.liveSegments.enumerated()), id: \.element.id) { i, seg in
                            let last = i == app.recorder.liveSegments.count - 1
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(seg.startTime.asClock).font(Theme.mono(11.5)).foregroundStyle(Theme.tertiary)
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    let who = seg.source == "mic" ? "Me" : seg.source == "system" ? "Them" : "Speaker"
                                    Text(who).font(Theme.text(12.5, weight: .semibold)).foregroundStyle(who == "Me" ? Theme.ink : Theme.secondary)
                                    Text(seg.text).font(Theme.text(last ? 20 : 16)).foregroundStyle(last ? Theme.ink : Theme.body)
                                        .lineSpacing(4).textSelection(.enabled)
                                }
                            }
                            .id(seg.id)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: app.recorder.liveSegments.count) { _, _ in
                    if let last = app.recorder.liveSegments.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").heading(15)
            Text("Stamped with the recording time and saved with the meeting.")
                .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
            ForEach(Array(stamped.enumerated()), id: \.offset) { _, n in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(n.at).font(Theme.mono(11)).foregroundStyle(Theme.tertiary)
                    Text(n.text).font(Theme.text(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("Type a note and press Return", text: $note, axis: .vertical)
                .textFieldStyle(.plain).font(Theme.text(13))
                .padding(12)
                .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onSubmit { addNote(note); note = "" }
            Button { addNote("Bookmark") } label: { Label("Bookmark this moment", systemImage: "bookmark") }
                .buttonStyle(QuietPill())
                .keyboardShortcut("b", modifiers: .command)
                .help("Mark this moment in the notes (⌘B)")
        }
        .workPanel()
        .disabled(meeting == nil || state == .stopping)
    }

    private func addNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let m = meeting else { return }
        let at = app.recorder.elapsed.asClock
        stamped.append((at, t))
        let line = "[\(at)] \(t)"
        app.saveNotes(m, notes: m.notes.isEmpty ? line : m.notes + "\n" + line)
    }
}
