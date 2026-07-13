import SwiftUI
import AppKit

struct SummaryView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var summary: MeetingSummary?
    @AppStorage("llmProvider") private var provider = "ollama"

    private var providerKind: LLMProviderKind { LLMProviderKind(rawValue: provider) ?? .ollama }
    private var isQueued: Bool { app.pendingSummaryMeetingIds.contains(meeting.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                    Text(providerKind == .ollama
                         ? "Processed privately on this Mac"
                         : "Processed with \(providerKind.displayName)")
                        .font(.system(size: 11))
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
                }
                Button {
                    app.generateSummary(for: meeting)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text(summary == nil ? "Generate Summary" : "Regenerate")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(summary?.status == SummaryStatus.generating.rawValue || isQueued)
            }
            .padding(.horizontal, 24).padding(.vertical, 8)

            Group {
                if isQueued {
                    VStack(spacing: 10) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Waiting for transcript to finalize…")
                            .font(.callout).foregroundStyle(.secondary)
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
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Cancel") { app.cancelSummary(for: meeting) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Theme.raisedBG, in: Capsule())
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    case SummaryStatus.failed.rawValue where s.error == "Cancelled.":
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.muted)
                            Text("Summary cancelled").font(.headline).foregroundStyle(Theme.ink)
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    case SummaryStatus.failed.rawValue:
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.danger)
                            Text("Summary failed").font(.headline)
                            Text(s.error ?? "Unknown error")
                                .font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 480)
                                .textSelection(.enabled)
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    default:
                        ScrollView {
                            MarkdownView(markdown: s.markdown)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.muted)
                        Text("No summary yet").font(Theme.display(20)).foregroundStyle(Theme.ink)
                        Text("Generate meeting notes from the transcript — \(providerKind == .ollama ? "everything is processed privately on this Mac" : "processed with \(providerKind.displayName)").")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
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
                        Image(systemName: line.hasPrefix("- [x] ") ? "checkmark.square" : "square")
                            .foregroundStyle(Theme.accent)
                        Text(inline(String(line.dropFirst(6)))).font(.system(size: 13)).foregroundStyle(Theme.body)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -2)
                        Text(inline(String(line.dropFirst(2)))).font(.system(size: 13)).foregroundStyle(Theme.body)
                    }
                } else {
                    Text(inline(line)).font(.system(size: 13)).foregroundStyle(Theme.body).lineSpacing(3)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
