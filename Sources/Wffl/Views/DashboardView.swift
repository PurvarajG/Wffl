import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState

    private var thisWeek: [Meeting] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return app.recordedMeetings.filter { $0.createdAt >= start }
    }

    private var capturedTotal: Double {
        app.meetings.reduce(0) { $0 + $1.durationSeconds }
    }

    private var summariesCount: Int {
        app.meetings.filter {
            Database.shared.latestSummary(meetingId: $0.id)?.status == SummaryStatus.completed.rawValue
        }.count
    }

    private var capturedLabel: String {
        let total = Int(capturedTotal)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dashboard").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button {
                    app.newMeetingAndRecord()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle.fill").font(.system(size: 11))
                        Text("Start Recording").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(app.recorder.state != .idle)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        statCard(label: "This week", value: "\(thisWeek.count)", caption: "meetings recorded")
                        statCard(label: "Captured", value: capturedLabel, caption: "of audio, all local")
                        statCard(label: "Summaries", value: "\(summariesCount)", caption: "generated on-device")
                    }

                    Text("Recent activity")
                        .font(Theme.display(19))
                        .foregroundStyle(Theme.ink)

                    VStack(spacing: 8) {
                        ForEach(Array(app.meetings.prefix(6))) { m in
                            activityRow(m)
                        }
                        if app.meetings.isEmpty {
                            Text("Nothing yet — record your first meeting.")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func statCard(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.display(30)).foregroundStyle(Theme.ink)
            Text(caption).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.raisedBG.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
    }

    private func statusFor(_ m: Meeting) -> (String, Bool) {
        if Database.shared.latestSummary(meetingId: m.id)?.status == SummaryStatus.completed.rawValue {
            return ("Summarized", true)
        }
        if !Database.shared.segments(meetingId: m.id).isEmpty {
            return ("Transcript", false)
        }
        return (m.folder == "import" ? "Imported" : "Recorded", false)
    }

    private func activityRow(_ m: Meeting) -> some View {
        let (status, highlight) = statusFor(m)
        let imported = m.folder == "import"
        return Button {
            app.selectedMeetingIds = [m.id]
            app.nav = imported ? .audioFiles : .meetings
        } label: {
            HStack(spacing: 12) {
                Group {
                    if highlight {
                        WMarkView(size: 13, lineScale: 0.16)
                            .frame(width: 30, height: 30)
                            .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 7))
                    } else {
                        Image(systemName: imported ? "music.note" : "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 30, height: 30)
                            .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle(m, status: status))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(highlight ? Theme.accentDark : Theme.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(highlight ? Theme.accentSoft : Theme.raisedBG, in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(highlight ? Theme.cardBG : Theme.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ m: Meeting, status: String) -> String {
        let cal = Calendar.current
        let when: String
        if cal.isDateInToday(m.createdAt) { when = "Today" }
        else if cal.isDateInYesterday(m.createdAt) { when = "Yesterday" }
        else {
            let df = DateFormatter(); df.dateStyle = .medium
            when = df.string(from: m.createdAt)
        }
        var parts = [when]
        if m.durationSeconds > 0 { parts.append(m.durationSeconds.asClock) }
        switch status {
        case "Summarized": parts.append("summary ready")
        case "Transcript": parts.append("transcript ready")
        case "Imported": parts.append("ready to transcribe")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}
