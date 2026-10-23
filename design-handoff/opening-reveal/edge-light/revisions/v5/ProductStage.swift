import AppKit
import SceneKit
import SwiftUI

/// Actual 3D geometry and lighting. The supplied texture is a native 2x render,
/// mapped once onto the front face; no animated gradients or screen-space masks.
@MainActor final class ProductStage {
    let scene = SCNScene()
    let camera = SCNNode()
    private let product = SCNNode()
    private let left = SCNNode()
    private let right = SCNNode()
    private let focus = SCNNode()
    private let screen = SCNMaterial()

    init(plate: CGImage, size: CGSize) {
        scene.background.contents = NSColor.black
        let width: CGFloat = 9.8
        let faceWidth = width - 0.24
        let faceHeight = faceWidth * size.height / size.width
        let height = faceHeight + 0.24
        let thickness: CGFloat = 0.44

        let chassis = SCNBox(width: width, height: height, length: thickness, chamferRadius: 0.10)
        chassis.chamferSegmentCount = 8
        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = NSColor(white: 0.38, alpha: 1)
        metal.metalness.contents = 0.65
        metal.roughness.contents = 0.22
        chassis.materials = [metal]
        product.addChildNode(SCNNode(geometry: chassis))

        let face = SCNPlane(width: faceWidth, height: faceHeight)
        face.cornerRadius = 0.065
        face.widthSegmentCount = 1
        face.heightSegmentCount = 1
        // An actual display emits its own image; the studio lights shape the
        // chassis instead of painting bright circular highlights over its text.
        screen.lightingModel = .constant
        screen.diffuse.contents = plate
        screen.diffuse.magnificationFilter = .linear
        screen.diffuse.minificationFilter = .linear
        screen.diffuse.mipFilter = .linear
        screen.diffuse.maxAnisotropy = 16
        screen.diffuse.intensity = 0
        face.materials = [screen]
        let screenNode = SCNNode(geometry: face)
        screenNode.position.z = thickness / 2 + 0.002
        product.addChildNode(screenNode)
        product.position.y = 0.10
        scene.rootNode.addChildNode(product)

        focus.position = SCNVector3(0, 0.3, 0)
        scene.rootNode.addChildNode(focus)
        for node in [left, right] {
            let light = SCNLight()
            light.type = .directional
            light.color = NSColor(white: 1, alpha: 1)
            light.temperature = 6200
            light.spotInnerAngle = 0
            light.spotOuterAngle = 95
            light.attenuationStartDistance = 0
            light.attenuationEndDistance = 30
            light.attenuationFalloffExponent = 2
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowRadius = 9
            light.shadowSampleCount = 32
            light.shadowMapSize = CGSize(width: 2048, height: 2048)
            light.orthographicScale = 14
            node.light = light
            let aim = SCNLookAtConstraint(target: focus)
            aim.isGimbalLockEnabled = true
            node.constraints = [aim]
            scene.rootNode.addChildNode(node)
        }

        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 31
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 80
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.3
        camera.camera?.bloomIntensity = 0
        camera.camera?.vignettingIntensity = 0
        camera.camera?.automaticallyAdjustsZRange = false
        camera.position = SCNVector3(0, 0.45, 14.0)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        update(0)
    }

    func update(_ t: Double) {
        func ease(_ a: Double, _ b: Double) -> Double {
            let p = min(1, max(0, (t - a) / (b - a)))
            return 0.5 - 0.5 * cos(.pi * p)
        }
        let opening = ease(0.35, 2.5) * (1 - ease(5.1, 7.0))
        let finishing = ease(4.6, 6.9) * (1 - ease(9.4, 10.6))
        let firstTravel = ease(0.35, 7.0)
        let secondTravel = ease(4.6, 10.6)
        let turn = ease(0, 10.8)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        product.eulerAngles = SCNVector3(-0.095 + 0.035 * turn, -0.29 + 0.15 * turn, -0.012)
        left.position = SCNVector3(-6.3 + 2.8 * firstTravel, 4.5 + 0.7 * firstTravel, 1.4 + 3.8 * firstTravel)
        right.position = SCNVector3(6.0 - 0.8 * secondTravel, 2.1 - 2.4 * secondTravel, 1.8 + 3.9 * secondTravel)
        left.light?.intensity = 2500 * opening
        right.light?.intensity = 3000 * finishing
        screen.diffuse.intensity = (0.28 * ease(1.6, 3.8) + 0.30 * ease(5.4, 8.1)) * (1 - ease(9.4, 10.6))
        SCNTransaction.commit()
    }
}

struct ProductStageView: NSViewRepresentable {
    let stage: ProductStage
    let elapsed: Double
    let size: CGSize

    final class Coordinator {
        let renderer = SCNRenderer(device: nil, options: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? { size }
    func updateNSView(_ view: NSImageView, context: Context) {
        // Use the exact renderer used for export, including camera and exposure.
        let renderer = context.coordinator.renderer
        renderer.scene = stage.scene
        renderer.pointOfView = stage.camera
        renderer.autoenablesDefaultLighting = false
        stage.update(elapsed)
        let image = renderer.snapshot(atTime: elapsed,
            with: CGSize(width: size.width * 2, height: size.height * 2),
            antialiasingMode: .multisampling4X)
        image.size = size
        view.image = image
    }
}

/// Prepare the native texture after layout, outside SwiftUI's body evaluation.
struct ProductStagePreview: View {
    let size: CGSize
    let scheme: ColorScheme
    let elapsed: Double
    @State private var stage: ProductStage?
    var body: some View {
        Group {
            if let stage { ProductStageView(stage: stage, elapsed: elapsed, size: size) }
            else { Color.black }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(Int(size.width))x\(Int(size.height))-\(scheme)") {
            guard size.width > 0, size.height > 0 else { return }
            let geometry = ReviewAssets.geometry(size, scheme)
            stage = ProductStage(plate: geometry.plate, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
