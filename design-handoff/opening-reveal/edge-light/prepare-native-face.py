"""Extract current product views with inert data; never compile the retired Home."""
from pathlib import Path
import sys

repo, output = map(Path, sys.argv[1:])
shell = (repo / "Sources/Wffl/Views/ContentView.swift").read_text()
ask = (repo / "Sources/Wffl/Views/AskHome.swift").read_text()
models = (repo / "Sources/Wffl/Models/Models.swift").read_text()


def between(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


assert "case ask, actions, audioFiles" in shell, "Expected current app-v2 navigation"
assert 'Text("Recent")' in ask and "struct AskPanel:" in ask
# Readiness uses its product layout, with fixed inputs instead of TCC/service checks.
readiness_body = between(ask, "    var body: some View {\n        Group {", "        .task(id:")
readiness = """struct ReadinessNotice: View {
    private struct Item: Identifiable {
        let id: String
        let text: String
        let action: String
        let run: () -> Void
    }
    private let items = [
        Item(id: "engine", text: "BAPS Whisper is not downloaded yet, so nothing can be transcribed.", action: "Open Settings", run: {}),
        Item(id: "mic", text: "Wffl needs microphone access to record you.", action: "Allow in System Settings", run: {})
    ]
""" + readiness_body + "    }\n}\n"

parts = [
    "import AppKit\nimport SwiftUI\n",
    between(shell, "enum NavSection:", "enum MeetingNudgePresentation"),
    between(shell, "enum SidebarItem:", "struct ContentView:"),
    between(shell, "struct Sidebar:", "struct MeetingActionsMenu:"),
    between(models, "struct Meeting:", "// MARK: - Transcript segment"),
    between(ask, "struct AskHome:", "// MARK: - Readiness"),
    readiness,
    between(ask, "struct RecentMeetings:", "// MARK: - Search"),
    ask[ask.index("struct OpenItemsPanel:"):],
]
output.write_text("\n".join(parts))
print(f"Prepared current native Ask, Sidebar and WindowToolbar: {output}")
