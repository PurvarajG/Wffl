import SwiftUI

/// Determinate progress bar with perception-tuned easing:
/// - displayed value = real fraction * 0.92, so it can never park near 100%;
/// - between real updates it creeps forward asymptotically, never crossing
///   the 0.92 ceiling, so it never looks frozen;
/// - when the real fraction reaches 1.0 it animates to 100% in ~0.4s —
///   the fast finish that makes the whole wait feel shorter.
struct EasedProgressBar: View {
    let fraction: Double   // real progress 0...1

    @State private var displayed: Double = 0

    private static let ceiling = 0.92

    var body: some View {
        Capsule()
            .fill(Theme.raisedBG)
            .frame(width: 250, height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * displayed)
                }
            }
            .onAppear { displayed = min(fraction * Self.ceiling, Self.ceiling) }
            .onChange(of: fraction) { _, newValue in
                if newValue >= 1 {
                    withAnimation(.easeIn(duration: 0.4)) { displayed = 1.0 }
                } else {
                    withAnimation(.easeOut(duration: 0.6)) { displayed = min(newValue * Self.ceiling, Self.ceiling) }
                }
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                guard fraction < 1 else { return }
                let target = min(displayed + 0.0025, fraction * Self.ceiling + 0.03, Self.ceiling)
                guard target > displayed else { return }
                withAnimation(.linear(duration: 0.5)) { displayed = target }
            }
    }
}
