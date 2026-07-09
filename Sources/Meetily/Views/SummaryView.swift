import SwiftUI
import AppKit

struct SummaryView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var summary: MeetingSummary?
    @AppStorage("llmProvider") private var provider = "ollama"

    private var providerKind: LLMProviderKind { LLMProviderKind(rawValue: provider) ?? .ollama }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("\(providerKind.displayName) · \(Prefs.model(for: providerKind))", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if summary?.status == SummaryStatus.completed.rawValue {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary?.markdown ?? "", forType: .string)
                        app.toast = "Summary copied."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    app.generateSummary(for: meeting)
                } label: {
                    Label(summary == nil ? "Generate Summary" : "Regenerate", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(summary?.status == SummaryStatus.generating.rawValue)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            Group {
                if let s = summary {
                    switch s.status {
                    case SummaryStatus.generating.rawValue:
                        VStack(spacing: 10) {
                            Spacer()
                            ProgressView()
                            Text("Summarizing with \(s.model)… (local models can take a minute)")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    case SummaryStatus.failed.rawValue:
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
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
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No summary yet", systemImage: "sparkles",
                        description: Text("Generate meeting notes from the transcript — processed by \(providerKind == .ollama ? "a local open-source model" : providerKind.displayName).")
                    )
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
                    Text(inline(String(line.dropFirst(4)))).font(.headline).padding(.top, 6)
                } else if line.hasPrefix("## ") {
                    Text(inline(String(line.dropFirst(3)))).font(.title3.bold()).padding(.top, 10)
                } else if line.hasPrefix("# ") {
                    Text(inline(String(line.dropFirst(2)))).font(.title2.bold()).padding(.top, 10)
                } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: line.hasPrefix("- [x] ") ? "checkmark.square" : "square")
                            .foregroundStyle(.secondary)
                        Text(inline(String(line.dropFirst(6))))
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(String(line.dropFirst(2))))
                    }
                } else {
                    Text(inline(line))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
