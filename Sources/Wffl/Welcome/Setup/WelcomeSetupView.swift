// The live setup page: a TimelineView over the pure stage, driven by a `SetupSession`.
// It starts the session's clock when it first appears and tells the session when it is on screen, so
// the microphone meter runs only while setup is visible.
import SwiftUI

struct WelcomeSetupView: View {
    @ObservedObject var session: SetupSession
    let reduced: Bool

    /// The stage waits one tick for `begin()`, so the entrance never starts mid-way.
    @State private var started = false

    var body: some View {
        ZStack {
            Setup.Palette.ground
            if started {
                let finished = session.core.isFinished
                // It keeps animating through the settle beat after finishing, until the frame is handed over.
                TimelineView(.animation(paused: session.isHandedOver)) { timeline in
                    SetupStageView(core: session.core, t: session.time(at: timeline.date), levels: session.levels,
                                   reduced: reduced, interactive: !finished, send: session.send)
                }
            }
        }
        .onChange(of: reduced) { _, value in session.reducedMotion = value }
        .onAppear {
            session.reducedMotion = reduced
            session.begin()
            session.setVisible(true)
            started = true
        }
        .onDisappear { session.setVisible(false) }
    }
}
