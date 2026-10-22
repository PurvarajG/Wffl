import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState

    private var thisWeek: [Meeting] {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!
        return app.recordedMeetings.filter { interval.contains($0.createdAt) }
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

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        return Array(repeating: nil, count: leading) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func capturedSeconds(on day: Date) -> Double {
        app.meetings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    private func capturedDescription(_ seconds: Double) -> String {
        if seconds <= 0 { return "No audio captured" }
        if seconds < 60 { return "Under 1 minute captured" }
        return "\(Int(seconds / 60)) minutes captured"
    }

    private var weekdayLabels: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dashboard").font(Theme.text(11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button {
                    app.newMeetingAndRecord()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle.fill").font(.system(size: 11))
                        Text("Start Recording").font(Theme.text(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
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
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            weeklyOverview.frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
                            calendarCard.frame(width: 350)
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            weeklyOverview
                            calendarCard
                        }
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
                                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEETINGS THIS WEEK")
                .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
            Text("\(thisWeek.count)")
                .font(Theme.display(105)).tracking(-5)
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("\(thisWeek.count) meetings recorded this week")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 27) {
                quietMetric(capturedLabel, label: "CAPTURED")
                quietMetric("\(summariesCount)", label: "SUMMARIES")
            }
            Text("Captured audio is stored locally. Summaries use your configured service.")
                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func quietMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(27)).foregroundStyle(Theme.ink)
            Text(label).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Date().formatted(.dateTime.month(.wide).year()))
                .font(Theme.display(24)).foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 9) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let captured = capturedSeconds(on: day)
                        VStack(spacing: 5) {
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                            Circle().fill(captured > 0 ? Theme.ink : Theme.accentSoft)
                                .frame(width: 7, height: 7)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(capturedDescription(captured))")
                        .help("\(day.formatted(date: .abbreviated, time: .omitted)) · \(capturedDescription(captured))")
                    } else { Color.clear.frame(height: 26) }
                }
            }
        }
        .wfflCard()
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
                        .font(Theme.text(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle(m, status: status))
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(status)
                    .font(Theme.text(11, weight: .medium))
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
