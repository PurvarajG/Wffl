import SwiftUI

/// Named frames of the old window (SPEC 2.2.3). The film dives into the measured Home mark.
enum FilmAnchor: Hashable {
    case sidebarMark, sidebarWordmark, navRow(Int), privacyNote
    case homeMark, headline, startButton, importButton
}

extension EnvironmentValues {
    /// Draws the old window without its ground.
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
