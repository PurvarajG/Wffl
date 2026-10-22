import SwiftUI

// The app as it shipped in v1.9.0 (commit 06579e8): Theme, sidebar and Home, copied unchanged
// except for names, static sample data (where it read live state) and film anchors.
// The update film plays "Wffl, as you knew it" from these real views (SPEC 2.2.2).

enum LegacyTheme {
    static let appBG      = Color(hex: 0xF7F3EC)
    static let raisedBG   = Color(hex: 0xEFE9DE)
    static let cardBG     = Color(hex: 0xFFFEFB)
    static let ink        = Color(hex: 0x2C261C)
    static let body       = Color(hex: 0x4A4235)
    static let secondary  = Color(hex: 0x8F8676)
    static let muted      = Color(hex: 0xA89E8D)
    static let hairline   = Color(red: 44/255, green: 38/255, blue: 28/255).opacity(0.08)
    static let accent     = Color(hex: 0x7A9169)
    static let accentSoft = Color(hex: 0x7A9169).opacity(0.16)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

struct LegacyWMark: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = [.init(x: 22, y: 32), .init(x: 36, y: 70), .init(x: 50, y: 46), .init(x: 64, y: 70), .init(x: 78, y: 32)]
        var p = Path()
        let sx = rect.width / 100, sy = rect.height / 100
        p.move(to: CGPoint(x: rect.minX + pts[0].x * sx, y: rect.minY + pts[0].y * sy))
        for pt in pts.dropFirst() {
            p.addLine(to: CGPoint(x: rect.minX + pt.x * sx, y: rect.minY + pt.y * sy))
        }
        return p
    }
}

struct LegacyWMarkView: View {
    var size: CGFloat
    var color: Color = LegacyTheme.ink
    var lineScale: CGFloat = 0.09

    var body: some View {
        LegacyWMark()
            .stroke(color, style: StrokeStyle(lineWidth: size * lineScale, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

enum LegacyNav: String, CaseIterable {
    case home = "Home", dashboard = "Dashboard", meetings = "Meetings", audioFiles = "Audio Files", settings = "Settings"
    var icon: String {
        switch self {
        case .home: "house"
        case .dashboard: "square.grid.2x2"
        case .meetings: "line.3.horizontal"
        case .audioFiles: "music.note"
        case .settings: "gearshape"
        }
    }
}

/// Window layout of the old app on its Home page: 210pt sidebar, hairline, Home.
struct LegacyShell: View {
    @Environment(\.filmClearGround) private var clearGround

    var body: some View {
        HStack(spacing: 0) {
            LegacySidebar()
                .frame(width: 210)
            Rectangle().fill(LegacyTheme.hairline).frame(width: 1)
            LegacyHome()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(clearGround ? Color.clear : LegacyTheme.appBG)
        }
        .background(clearGround ? Color.clear : LegacyTheme.appBG)
    }
}

struct LegacySidebar: View {
    /// Sample: an empty library, like the film's new plate.
    var recordedCount = 0
    @Environment(\.filmClearGround) private var clearGround

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LegacyWMarkView(size: 16, lineScale: 0.14)
                    .filmAnchor(.sidebarMark)
                Text("Wffl")
                    .font(LegacyTheme.display(17))
                    .foregroundStyle(LegacyTheme.ink)
                    .filmAnchor(.sidebarWordmark)
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                navRow(.home)
                navRow(.dashboard)
                navRow(.meetings, count: recordedCount)
                navRow(.audioFiles, count: nil)
            }
            .padding(.horizontal, 8)

            Spacer()
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                navRow(.settings)
                    .padding(.horizontal, 0)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(LegacyTheme.secondary)
                        .padding(.top, 1)
                    Text("On-device only ·\nnothing leaves this Mac")
                        .font(.system(size: 10))
                        .foregroundStyle(LegacyTheme.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LegacyTheme.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .filmAnchor(.privacyNote)
            }
            .padding(8)
        }
        .background(clearGround ? Color.clear : LegacyTheme.raisedBG)
    }

    @ViewBuilder
    private func navRow(_ section: LegacyNav, count: Int? = nil) -> some View {
        let selected = section == .home
        HStack(spacing: 9) {
            Image(systemName: section.icon)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(section.rawValue)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(LegacyTheme.muted)
            }
        }
        .foregroundStyle(selected ? LegacyTheme.ink : LegacyTheme.body)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LegacyTheme.accentSoft)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(LegacyTheme.accent.opacity(0.25)))
            }
        }
        .contentShape(Rectangle())
        .filmAnchor(.navRow(LegacyNav.allCases.firstIndex(of: section)!))
    }
}

/// Full landing screen: one dominant action, Start Recording.
struct LegacyHome: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Home").font(.system(size: 11)).foregroundStyle(LegacyTheme.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Rectangle().fill(LegacyTheme.hairline).frame(height: 1)

            Spacer()

            VStack(spacing: 18) {
                LegacyWMarkView(size: 44, lineScale: 0.11)
                    .filmAnchor(.homeMark)

                Text("Ready when you are.")
                    .font(LegacyTheme.display(38))
                    .foregroundStyle(LegacyTheme.ink)
                    .filmAnchor(.headline)

                Text("Record a meeting and Wffl transcribes and summarizes it —\nentirely on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(LegacyTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").font(.system(size: 13))
                        Text("Start Recording").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(LegacyTheme.accent, in: RoundedRectangle(cornerRadius: 11))
                    .shadow(color: LegacyTheme.accent.opacity(0.35), radius: 10, y: 3)
                    .filmAnchor(.startButton)

                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                        Text("Import audio").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(LegacyTheme.body)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(LegacyTheme.cardBG, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LegacyTheme.hairline))
                    .filmAnchor(.importButton)
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    statusChip(text: "BAPS Whisper ready")
                    statusChip(text: "Local AI Connected")
                }
                .padding(.top, 14)
            }

            Spacer()
            Spacer()
        }
    }

    private func statusChip(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(LegacyTheme.accent)
            Text(.init(text))
                .font(.system(size: 11))
                .foregroundStyle(LegacyTheme.body)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(LegacyTheme.raisedBG.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(LegacyTheme.hairline))
    }
}
