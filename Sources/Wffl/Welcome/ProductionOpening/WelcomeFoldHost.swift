import AppKit
import SwiftUI

/// The page that folds: the tour at a moment in time, or the finished setup page, frozen.
enum OpeningFoldSource {
    case tour(Double)
    case setup(SetupFrame)

    /// What changes the hosted face. A frozen setup frame never changes while it is hosted.
    fileprivate var key: String {
        switch self {
        case .tour(let t): "tour.\(t)"
        case .setup: "setup"
        }
    }

    /// The page itself, without chrome. Setup is always rendered for full motion: Reduced Motion never folds.
    @MainActor func face(scheme: ColorScheme) -> AnyView {
        switch self {
        case .tour(let t):
            AnyView(FilmStage(t: t).ignoresSafeArea().environment(\.colorScheme, scheme))
        case .setup(let frame):
            AnyView(SetupStageView(core: frame.core, t: frame.t, levels: frame.levels, reduced: false,
                                   interactive: false, send: { _ in })
                .ignoresSafeArea().environment(\.colorScheme, scheme))
        }
    }
}

/// AppKit owns the two sibling renderers so SwiftUI cannot remove SceneKit while
/// reconciling the tour. The outgoing page is hidden after capture so that only
/// the live application, outside this host, remains beneath the folding faces.
@MainActor
struct WelcomeFoldHost: NSViewRepresentable {
    let source: OpeningFoldSource
    let foldProgress: Double
    let colorScheme: ColorScheme
    var onSurfaceReady: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> WelcomeFoldHostView {
        let view = WelcomeFoldHostView(frame: .zero, source: source, foldProgress: foldProgress, colorScheme: colorScheme)
        view.onSurfaceReady = onSurfaceReady
        return view
    }

    func updateNSView(_ view: WelcomeFoldHostView, context: Context) {
        view.update(source: source, foldProgress: foldProgress, colorScheme: colorScheme)
    }
    static func dismantleNSView(_ view: WelcomeFoldHostView, coordinator: ()) { view.shutdown() }
}

@MainActor
final class WelcomeFoldHostView: NSView {
    private let hosting: NSHostingView<AnyView>
    private var foldSurface: FoldSurfaceView?
    private var pendingFoldSurface: FoldSurfaceView?
    private var lastSize: CGSize = .zero
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0
    var onSurfaceReady: (Bool) -> Void = { _ in }
    private var reportedReady = false

    private func reportReady(_ ready: Bool) {
        guard reportedReady != ready else { return }
        reportedReady = ready
        DispatchQueue.main.async { [weak self] in self?.onSurfaceReady(ready) }
    }
    private var currentSource: OpeningFoldSource
    private var hostedFace = ""
    private var currentProgress: Double
    private var currentColorScheme: ColorScheme

    init(frame: CGRect, source: OpeningFoldSource, foldProgress: Double, colorScheme: ColorScheme) {
        currentSource = source
        currentProgress = foldProgress
        currentColorScheme = colorScheme
        hostedFace = source.key + (colorScheme == .dark ? ".dark" : ".light")
        hosting = NSHostingView(rootView: source.face(scheme: colorScheme))
        super.init(frame: frame)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:source:foldProgress:colorScheme:)") }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        if lastSize != bounds.size {
            lastSize = bounds.size
            if currentProgress > 0 { refreshFoldSource() }
        }
    }

    func update(source: OpeningFoldSource, foldProgress: Double, colorScheme: ColorScheme) {
        let appearanceChanged = currentColorScheme != colorScheme
        currentSource = source
        currentProgress = min(1, max(0, foldProgress))
        currentColorScheme = colorScheme
        let face = source.key + (colorScheme == .dark ? ".dark" : ".light")
        if face != hostedFace {
            hostedFace = face
            hosting.rootView = source.face(scheme: colorScheme)
        }
        hosting.frame = bounds
        if currentProgress > 0 {
            if appearanceChanged || (foldSurface == nil && captureTask == nil && pendingFoldSurface == nil) {
                refreshFoldSource()
            }
            hosting.isHidden = foldSurface?.hasBaked == true
            foldSurface?.setProgress(currentProgress)
            foldSurface?.isHidden = false
            pendingFoldSurface?.setProgress(currentProgress)
            pendingFoldSurface?.isHidden = true
            reportReady(foldSurface?.hasBaked == true)
        } else {
            captureTask?.cancel(); captureTask = nil
            captureGeneration += 1
            cancelPendingSurface()
            releaseSurface()
            hosting.isHidden = false
            reportReady(false)
        }
    }

    func shutdown() {
        captureGeneration += 1
        captureTask?.cancel(); captureTask = nil
        releaseSurface()
        hosting.rootView = AnyView(EmptyView())
        hostedFace = ""
    }

    private func releaseSurface() {
        cancelPendingSurface()
        foldSurface?.cancelBake()
        foldSurface?.rendersContinuously = false
        foldSurface?.isPlaying = false
        foldSurface?.scene = nil
        foldSurface?.removeFromSuperview()
        foldSurface = nil
    }

    private func refreshFoldSource() {
        guard bounds.width > 0, bounds.height > 0, let window else { return }
        captureGeneration += 1
        let generation = captureGeneration
        let size = bounds.size, scheme = currentColorScheme, source = currentSource
        let visibleSource = foldSurface?.hasBaked != true
        captureTask?.cancel()
        cancelPendingSurface()
        if visibleSource {
            hosting.isHidden = false
            reportReady(false)
        }
        captureTask = Task { @MainActor [weak self, weak window] in
            guard let window else { return }
            // Keep the original page visible until its actual native capture is ready.
            let image = await OpeningTourCapture.render(size: size, scheme: scheme, owner: window,
                                                       source: source, visibleSource: visibleSource)
            guard !Task.isCancelled, let self, generation == self.captureGeneration,
                  self.bounds.size == size else { return }
            self.captureTask = nil
            guard let image else {
                self.hosting.isHidden = self.foldSurface?.hasBaked == true
                self.reportReady(self.foldSurface?.hasBaked == true)
                return
            }
            let surface = FoldSurfaceView(frame: self.bounds, image: image)
            surface.autoresizingMask = [.width, .height]
            surface.onBakeReady = { [weak self, weak surface] in
                guard let self, let surface, self.pendingFoldSurface === surface else { return }
                self.activatePendingSurface(surface)
            }
            surface.isHidden = true
            self.addSubview(surface, positioned: .above, relativeTo: self.foldSurface ?? self.hosting)
            self.pendingFoldSurface = surface
            surface.setProgress(self.currentProgress)
            surface.isHidden = true
            self.hosting.isHidden = self.foldSurface?.hasBaked == true
            self.reportReady(self.foldSurface?.hasBaked == true)
        }
    }

    private func activatePendingSurface(_ surface: FoldSurfaceView) {
        guard pendingFoldSurface === surface, surface.hasBaked else { return }
        let previous = foldSurface
        surface.setProgress(currentProgress)
        surface.isHidden = currentProgress <= 0
        foldSurface = surface
        pendingFoldSurface = nil
        previous?.cancelBake()
        previous?.rendersContinuously = false
        previous?.isPlaying = false
        previous?.scene = nil
        previous?.removeFromSuperview()
        hosting.isHidden = currentProgress > 0
        reportReady(currentProgress > 0)
    }

    private func cancelPendingSurface() {
        pendingFoldSurface?.cancelBake()
        pendingFoldSurface?.rendersContinuously = false
        pendingFoldSurface?.isPlaying = false
        pendingFoldSurface?.scene = nil
        pendingFoldSurface?.removeFromSuperview()
        pendingFoldSurface = nil
    }
}
