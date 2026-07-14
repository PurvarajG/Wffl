import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// Sidebar list for the Audio Files section: drop zone + imported file rows.
/// Mirrors MeetingSidebarList — the sidebar picks a file, the center pane
/// (AudioFilesPage) shows its transcript/summary, same as Meetings does.
struct AudioFileSidebarList: View {
    @EnvironmentObject var app: AppState
    @State private var dropTargeted = false
    @State private var player: AVAudioPlayer?
    @State private var playingId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                dropZone

                if let job = app.importJob {
                    HStack(spacing: 8) {
                        ProgressView(value: job.progress).tint(Theme.accent).controlSize(.small)
                        Text("\(Int(job.progress * 100))%")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 2)
                }

                ForEach(app.importedMeetings) { m in
                    fileRow(m)
                }

                if app.importedMeetings.isEmpty {
                    Text("No audio files yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentDark)
            Text("Drop audio to transcribe")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("on-device, never uploaded")
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(dropTargeted ? Theme.accentSoft : Theme.raisedBG.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropTargeted ? Theme.accent : Theme.muted.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .wfflImportRequested, object: nil)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        Task { @MainActor in app.importAudioFile(url: url) }
                    }
                }
            }
            return true
        }
    }

    private func status(_ m: Meeting) -> String {
        if Database.shared.latestSummary(meetingId: m.id)?.status == SummaryStatus.completed.rawValue { return "Ready" }
        if !Database.shared.segments(meetingId: m.id).isEmpty { return "Transcript" }
        return "Imported"
    }

    private func fileRow(_ m: Meeting) -> some View {
        let st = status(m)
        let transcribed = st != "Imported"
        let isPlaying = playingId == m.id
        let isSelected = app.selectedMeetingIds == [m.id]

        return HStack(spacing: 8) {
            Button {
                togglePlay(m)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(transcribed ? Theme.secondary : .white)
                    .frame(width: 22, height: 22)
                    .background(transcribed ? Theme.raisedBG : Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(m.audioPath == nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(m.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(subtitle(m))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    if transcribed {
                        Text(st)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(st == "Ready" ? Theme.accentDark : Theme.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if st == "Imported" {
                if app.importJob?.meetingId == m.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        app.retranscribe(m)
                    } label: {
                        Text("Transcribe")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.cardBG)
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            }
        }
        // Tapping anywhere on the row opens it in the center pane — not just
        // the status badge. Play/Transcribe stay as their own buttons.
        .contentShape(Rectangle())
        .onTapGesture { app.selectedMeetingIds = [m.id] }
        .contextMenu {
            Button("Delete", role: .destructive) { app.delete(m) }
        }
    }

    private func subtitle(_ m: Meeting) -> String {
        var parts: [String] = []
        if m.durationSeconds > 0 { parts.append(m.durationSeconds.asClock) }
        parts.append(Calendar.current.isDateInToday(m.createdAt) ? "today" : shortDate(m.createdAt))
        return parts.joined(separator: " · ")
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private func togglePlay(_ m: Meeting) {
        if playingId == m.id {
            player?.stop(); player = nil; playingId = nil
            return
        }
        guard let path = m.audioPath else { return }
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player?.play()
        playingId = player == nil ? nil : m.id
    }
}

/// Center pane for the Audio Files section: shows the selected imported
/// file's transcript/summary/notes, or a placeholder when nothing's picked.
struct AudioFilesPage: View {
    @EnvironmentObject var app: AppState

    private var selected: Meeting? {
        guard let m = app.meeting(app.selectedMeetingId), m.folder == "import" else { return nil }
        return m
    }

    var body: some View {
        VStack(spacing: 0) {
            if let meeting = selected {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else {
                VStack(spacing: 10) {
                    WMarkView(size: 34, color: Theme.muted)
                    Text("Select an audio file")
                        .font(Theme.display(22)).foregroundStyle(Theme.ink)
                    Text("Drop an audio file in the sidebar, or pick one from the list, to see its transcript and summary.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
