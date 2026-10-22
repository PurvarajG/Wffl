import SwiftUI
import AppKit

struct SummaryView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var summary: MeetingSummary?
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""

    private var providerKind: LLMProviderKind { LLMProviderKind(rawValue: provider) ?? .ollama }
    private var disclosure: ProcessingDisclosure { .current }
    private var isQueued: Bool { app.pendingSummaryMeetingIds.contains(meeting.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                    Text(disclosure.shortLabel)
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if summary?.status == SummaryStatus.completed.rawValue {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary?.markdown ?? "", forType: .string)
                        app.toast = "Summary copied."
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy summary")
                    .accessibilityLabel("Copy summary")
                }
                Button {
                    app.generateSummary(for: meeting)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text(summary == nil ? "Generate Summary" : "Regenerate")
                            .font(Theme.text(11.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summary == nil ? "Generate summary" : "Regenerate summary")
                .disabled(summary?.status == SummaryStatus.generating.rawValue || isQueued)
            }
            .padding(.horizontal, 24).padding(.vertical, 8)

            Group {
                if isQueued {
                    VStack(spacing: 10) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Waiting for transcript to finalize…")
                            .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                } else if let s = summary {
                    switch s.status {
                    case SummaryStatus.generating.rawValue:
                        VStack(spacing: 10) {
                            Spacer()
                            EasedProgressBar(fraction: app.summaryProgress[meeting.id] ?? 0,
                                             indeterminateCreep: true)
                            Text(app.summaryReadingPhase.contains(meeting.id)
                                 ? "Reading transcript… (large meetings take a few minutes before text appears)"
                                 : "Summarizing transcript… (this may take a minute)")
                                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            Button("Cancel") { app.cancelSummary(for: meeting) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Cancel summary")
                                .font(Theme.text(11.5, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Theme.raisedBG, in: Capsule())
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    case SummaryStatus.failed.rawValue where s.error == "Cancelled.":
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.muted)
                            Text("Summary cancelled").font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    case SummaryStatus.failed.rawValue:
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.danger)
                            Text("Summary failed").font(Theme.text(13, weight: .semibold))
                            Text(s.error ?? "Unknown error")
                                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 480)
                                .textSelection(.enabled)
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    default:
                        ScrollView {
                            MarkdownView(markdown: s.markdown)
                                .padding(.horizontal, 28).padding(.vertical, 24)
                                .frame(maxWidth: 860, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.muted)
                        Text("No summary yet").font(Theme.display(20)).foregroundStyle(Theme.ink)
                        Text("Generate meeting notes from the transcript. \(disclosure.detail)")
                            .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: app.summaryRefresh) { _, _ in reload() }
    }

    private func reload() {
        summary = Database.shared.latestSummary(meetingId: meeting.id)
    }
}

/// Minimal Markdown renderer for the summary: headings, bullets, checkboxes,
/// and inline styles via AttributedString.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else if line.hasPrefix("### ") {
                    Text(inline(String(line.dropFirst(4)))).font(Theme.display(15)).foregroundStyle(Theme.ink).padding(.top, 6)
                } else if line.hasPrefix("## ") {
                    Text(inline(String(line.dropFirst(3)))).font(Theme.display(17)).foregroundStyle(Theme.ink).padding(.top, 10)
                } else if line.hasPrefix("# ") {
                    Text(inline(String(line.dropFirst(2)))).font(Theme.display(20)).foregroundStyle(Theme.ink).padding(.top, 10)
                } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line.hasPrefix("- [x] ") ? "Done" : "Open")
                            .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                        Text(inline(String(line.dropFirst(6)))).font(Theme.text(15)).foregroundStyle(Theme.body)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -2)
                        Text(inline(String(line.dropFirst(2)))).font(Theme.text(15)).foregroundStyle(Theme.body)
                    }
                } else {
                    Text(inline(line)).font(Theme.text(15)).foregroundStyle(Theme.body).lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
