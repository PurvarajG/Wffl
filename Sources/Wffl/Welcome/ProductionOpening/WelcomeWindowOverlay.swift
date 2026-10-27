import AppKit
import SwiftUI

/// Install above the complete native content area, including its toolbar. SwiftUI's
/// overlay modifier sits below native toolbar items and cannot provide this handoff.
struct WelcomeWindowOverlay: NSViewRepresentable {
    let isPresented: Bool
    let app: AppState
    let welcome: WelcomeJourneyCoordinator
    var model: WelcomeOpeningModel? = nil
    var mode: WelcomeMode = .film
    /// The review app supplies a fixture session; production leaves it nil.
    var makeSetup: (@MainActor () -> SetupSession)? = nil
    var onFinish: () -> Void = {}
    var onStop: () -> Void = {}
    var onHandover: () -> Void = {}
    var onSetupReached: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Anchor { Anchor() }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.update = { [weak anchor, coordinator = context.coordinator] in
            guard let window = anchor?.window else { return }
            coordinator.update(window: window, configuration: self)
        }
        DispatchQueue.main.async { anchor.update?() }
    }

    static func dismantleNSView(_ nsView: Anchor, coordinator: Coordinator) {
        nsView.update = nil
        coordinator.remove()
    }

    final class Anchor: NSView {
        var update: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); update?() }
    }

    @MainActor final class Coordinator {
        private var overlay: TransparentHostingView?
        private weak var window: NSWindow?
        private weak var previousResponder: NSResponder?

        func update(window: NSWindow, configuration: WelcomeWindowOverlay) {
            guard configuration.isPresented else { remove(); return }
            guard overlay == nil, let parent = window.contentView?.superview else { return }
            self.window = window
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
               let control = editor.delegate as? NSControl { previousResponder = control }
            else { previousResponder = window.firstResponder }
            let journey: WelcomeJourneyView
            if let model = configuration.model {
                journey = WelcomeJourneyView(model: model, mode: configuration.mode, makeSetup: configuration.makeSetup)
            }
            else {
                journey = WelcomeJourneyView(onFinish: configuration.onFinish, onStop: configuration.onStop,
                                             onHandover: configuration.onHandover,
                                             onSetupReached: configuration.onSetupReached, mode: configuration.mode,
                                             makeSetup: configuration.makeSetup)
            }
            let root = AnyView(journey.ignoresSafeArea()
                .environmentObject(configuration.app).environmentObject(configuration.welcome))
            let hosting = TransparentHostingView(rootView: root)
            hosting.sizingOptions = []
            hosting.frame = parent.bounds
            hosting.autoresizingMask = [.width, .height]
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            hosting.layer?.isOpaque = false
            parent.addSubview(hosting, positioned: .above, relativeTo: nil)
            overlay = hosting
        }

        func remove() {
            guard let overlay else { return }
            overlay.removeFromSuperview()
            overlay.rootView = AnyView(EmptyView())
            self.overlay = nil
            if let window {
                let restore = previousResponder
                // SwiftUI clears its FocusState while dismantling the welcome root.
                // Restore afterwards so that cleanup cannot steal the focus back.
                DispatchQueue.main.async { [weak window, weak restore] in
                    guard let window else { return }
                    if let view = restore as? NSView, view.window === window,
                       window.makeFirstResponder(view) { return }
                    window.makeFirstResponder(window.contentView)
                }
            }
            previousResponder = nil
            window = nil
        }
    }

    final class TransparentHostingView: NSHostingView<AnyView> {
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            return super.hitTest(point) ?? self
        }
    }
}
