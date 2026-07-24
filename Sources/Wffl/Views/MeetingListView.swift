import SwiftUI

/// Grouped meeting list embedded in the sidebar under the Meetings nav item.
struct MeetingSidebarList: View {
    @EnvironmentObject var app: AppState
    @State private var confirmingDelete = false
    @State private var renamingId: String?

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(grouped, id: \.0) { label, meetings in
                    Text(label.uppercased())
                        .font(.system(size: 9.5, weight: .medium))
                        .kerning(1.0)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(meetings) { m in
                        MeetingRow(meeting: m, renamingId: $renamingId)
                            .contextMenu { contextMenu(for: m) }
                    }
                }
                if app.filteredMeetings.isEmpty {
                    Text(app.searchText.isEmpty ? "No meetings yet — hit ⌘N to record." : "No matches.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .padding(12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onDeleteCommand {
            guard !app.selectedMeetingIds.isEmpty else { return }
            confirmingDelete = true
        }
        .confirmationDialog(
            "Delete \(app.selectedMeetingIds.count) meetings? Recordings and transcripts are removed permanently.",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(app.selectedMeetingIds.count) Meetings", role: .destructive) {
                app.deleteMeetings(ids: app.selectedMeetingIds)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func contextMenu(for m: Meeting) -> some View {
        if app.selectedMeetingIds.count > 1 && app.selectedMeetingIds.contains(m.id) {
            Button("Delete \(app.selectedMeetingIds.count) Meetings", role: .destructive) {
                confirmingDelete = true
            }
        } else {
            Button("Rename") { renamingId = m.id }
            Button("Delete Meeting", role: .destructive) { app.delete(m) }
        }
    }
}

struct MeetingRow: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @Binding var renamingId: String?

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var isRecordingThis: Bool { app.recorder.activeMeetingId == meeting.id }
    private var isSelected: Bool { app.selectedMeetingIds.contains(meeting.id) }

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.command) {
                if isSelected { app.selectedMeetingIds.remove(meeting.id) }
                else { app.selectedMeetingIds.insert(meeting.id) }
            } else {
                app.selectedMeetingIds = [meeting.id]
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isRecordingThis {
                        Circle().fill(Theme.clay).frame(width: 7, height: 7)
                    }
                    if renamingId == meeting.id {
                        TextField("Meeting title", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .focused($focused)
                            .onAppear {
                                draft = meeting.title
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                            }
                            .onSubmit { app.rename(meeting, to: draft); renamingId = nil }
                            .onExitCommand { renamingId = nil }
                    } else {
                        Text(meeting.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                HStack(spacing: 6) {
                    Text(meeting.createdAt, style: .time)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                    if meeting.durationSeconds > 0 {
                        Text(meeting.durationSeconds.asClock)
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.cardBG)
                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
