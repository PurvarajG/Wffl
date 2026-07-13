import SwiftUI

struct MeetingListView: View {
    @EnvironmentObject var app: AppState

    private var grouped: [(String, [Meeting])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateStyle = .medium
        var groups: [(String, [Meeting])] = []
        for m in app.filteredMeetings {
            let label: String
            if cal.isDateInToday(m.createdAt) { label = "Today" }
            else if cal.isDateInYesterday(m.createdAt) { label = "Yesterday" }
            else { label = df.string(from: m.createdAt) }
            if let idx = groups.firstIndex(where: { $0.0 == label }) {
                groups[idx].1.append(m)
            } else {
                groups.append((label, [m]))
            }
        }
        return groups
    }

    var body: some View {
        List(selection: $app.selectedMeetingId) {
            ForEach(grouped, id: \.0) { label, meetings in
                Section(label) {
                    ForEach(meetings) { m in
                        MeetingRow(meeting: m)
                            .tag(m.id)
                            .contextMenu {
                                Button("Delete Meeting", role: .destructive) { app.delete(m) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $app.searchText, placement: .sidebar, prompt: "Search meetings")
        .overlay {
            if app.meetings.isEmpty {
                ContentUnavailableView("No meetings yet", systemImage: "mic.slash", description: Text("Hit ⌘N to record your first meeting."))
            }
        }
    }
}

struct MeetingRow: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    private var isRecordingThis: Bool { app.recorder.activeMeetingId == meeting.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isRecordingThis {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
                Text(meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(meeting.createdAt, style: .time)
                if meeting.durationSeconds > 0 {
                    Text("·")
                    Text(meeting.durationSeconds.asClock)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
