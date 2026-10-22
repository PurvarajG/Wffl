import SwiftUI

/// Named frames the update film measures in both the old and the new plate (SPEC 2.2.3).
enum FilmAnchor: Hashable {
    case sidebarMark, sidebarWordmark, navRow(Int), privacyNote
    case homeMark, headline, startButton, importButton, continueCard
}

/// Selection and recede state the film drives inside the live `SidebarView`. Nil outside the film.
struct FilmSidebarState: Equatable {
    /// Fractional nav row (0 Home, 1 Dashboard, 2 Meetings) while the pill glides; nil uses the real selection.
    var selection: Double?
    var listOpacity = 1.0
    var recede = 0.0
    var markOpacity = 1.0
}

extension EnvironmentValues {
    @Entry var filmSidebar: FilmSidebarState? = nil
    /// The film draws one ground for the whole window while the skin cools, so the plates drop theirs.
    @Entry var filmClearGround = false
}

private struct FilmAnchorKey: PreferenceKey {
    static var defaultValue: [FilmAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [FilmAnchor: Anchor<CGRect>], nextValue: () -> [FilmAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct FilmRectsKey: PreferenceKey {
    static var defaultValue: [FilmAnchor: CGRect] = [:]
    static func reduce(value: inout [FilmAnchor: CGRect], nextValue: () -> [FilmAnchor: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's bounds to the nearest `filmMeasured` ancestor. Free outside the film.
    func filmAnchor(_ id: FilmAnchor) -> some View {
        anchorPreference(key: FilmAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Resolves every `filmAnchor` below into this view's own coordinate space and hands the frames back.
    func filmMeasured(_ onChange: @escaping ([FilmAnchor: CGRect]) -> Void) -> some View {
        overlayPreferenceValue(FilmAnchorKey.self) { anchors in
            GeometryReader { proxy in
                Color.clear.preference(key: FilmRectsKey.self, value: anchors.mapValues { proxy[$0] })
            }
        }
        .onPreferenceChange(FilmRectsKey.self) { onChange($0) }
    }
}
