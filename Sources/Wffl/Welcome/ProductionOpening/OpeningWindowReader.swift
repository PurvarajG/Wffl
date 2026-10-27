import AppKit
import SwiftUI

struct OpeningWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { Reader(onWindow: onWindow) }
    func updateNSView(_ view: Reader, context: Context) { }
    final class Reader: NSView {
        let onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let attached = window
            DispatchQueue.main.async { [weak self] in self?.onWindow(attached) }
        }
    }
}

/// Retain only the finishing gesture's momentum after the welcome view is removed.
/// A new gesture or ordinary wheel event reaches Ask immediately.
@MainActor enum WelcomeFinishingGestureGuard {
    private static var monitors: [Int: Any] = [:]
    private static var closeObservers: [Int: NSObjectProtocol] = [:]

    private static func remove(for id: Int) {
        if let monitor = monitors.removeValue(forKey: id) { NSEvent.removeMonitor(monitor) }
        if let observer = closeObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
    }

    static func install(for window: NSWindow) {
        let id = window.windowNumber
        remove(for: id)
        closeObservers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { _ in MainActor.assumeIsolated { remove(for: id) } }
        monitors[id] = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak window] event in
            guard let window else { remove(for: id); return event }
            guard event.window === window else { return event }
            let fresh = event.phase.contains(.began) || event.phase.contains(.mayBegin)
                || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            let ended = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
            if fresh || ended { remove(for: id) }
            return fresh ? event : nil
        }
    }
}
