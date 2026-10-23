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
    private let leftFocus = SCNNode()
    private let rightFocus = SCNNode()
    private let screen = SCNMaterial()

    init(plate: CGImage, size: CGSize) {
        scene.background.contents = NSColor.black
        let faceWidth: CGFloat = 9.62
        let faceHeight = faceWidth * size.height / size.width

        func material(_ value: CGFloat, metal: CGFloat, roughness: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor(calibratedRed: value * 0.96, green: value * 0.985, blue: value, alpha: 1)
            m.metalness.contents = metal
            m.roughness.contents = roughness
            return m
        }
        let body = material(0.22, metal: 0.88, roughness: 0.28)
        let rear = material(0.14, metal: 0.76, roughness: 0.36)
        let lip = material(0.34, metal: 0.92, roughness: 0.36)
        let gasket = material(0.004, metal: 0, roughness: 0.90)
        let glass = material(0.009, metal: 0.05, roughness: 0.13)
        glass.clearCoat.contents = 0.22
        glass.clearCoatRoughness.contents = 0.22

        // Concentric solids and small polished bevels. Corner radius is
        // independent of the cross-section, so the frame cannot inflate like rubber.
        addLayer(width: faceWidth + 0.24, height: faceHeight + 0.24,
                 radius: 0.24, depth: 0.54, bevel: 0.026, front: 0.15, material: body)
        addLayer(width: faceWidth + 0.18, height: faceHeight + 0.18,
                 radius: 0.21, depth: 0.065, bevel: 0.012, front: -0.39, material: rear)
        addLayer(width: faceWidth + 0.18, height: faceHeight + 0.18,
                 radius: 0.21, depth: 0.028, bevel: 0.012, front: 0.174, material: lip)
        addLayer(width: faceWidth + 0.12, height: faceHeight + 0.12,
                 radius: 0.18, depth: 0.018, bevel: 0.004, front: 0.184, material: gasket)
        addLayer(width: faceWidth + 0.06, height: faceHeight + 0.06,
                 radius: 0.15, depth: 0.019, bevel: 0.005, front: 0.208, material: glass)

        let face = SCNPlane(width: faceWidth, height: faceHeight)
        face.cornerRadius = 0.12
        screen.lightingModel = .constant
        screen.diffuse.contents = plate
        screen.diffuse.magnificationFilter = .linear
        screen.diffuse.minificationFilter = .linear
        screen.diffuse.mipFilter = .linear
        screen.diffuse.maxAnisotropy = 16
        screen.diffuse.intensity = 0
        face.materials = [screen]
        let screenNode = SCNNode(geometry: face)
        screenNode.position.z = 0.218
        product.addChildNode(screenNode)
        product.position.y = 0.05
        scene.rootNode.addChildNode(product)

        // Two broad studio softboxes reflected by real surface normals.
        // Float HDR data retains the highlight rolloff before camera tonemapping.
        scene.lightingEnvironment.contents = Self.studioEnvironment
        scene.lightingEnvironment.intensity = 0

        leftFocus.position = SCNVector3(-2.8, 1.8, 0)
        rightFocus.position = SCNVector3(3.0, -0.7, 0)
        scene.rootNode.addChildNode(leftFocus)
        scene.rootNode.addChildNode(rightFocus)
        for (node, target) in [(left, leftFocus), (right, rightFocus)] {
            let light = SCNLight()
            light.type = .spot
            light.spotInnerAngle = 24
            light.spotOuterAngle = 68
            light.attenuationStartDistance = 3
            light.attenuationEndDistance = 18
            light.attenuationFalloffExponent = 2
            light.color = NSColor(white: 1, alpha: 1)
            light.temperature = 6200
            light.castsShadow = false
            light.shadowMode = .deferred
            light.shadowRadius = 9
            light.shadowSampleCount = 32
            light.shadowMapSize = CGSize(width: 2048, height: 2048)
            light.orthographicScale = 14
            node.light = light
            let aim = SCNLookAtConstraint(target: target)
            aim.isGimbalLockEnabled = true
            node.constraints = [aim]
            scene.rootNode.addChildNode(node)
        }

        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 80
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.3
        camera.camera?.bloomIntensity = 0
        camera.camera?.vignettingIntensity = 0
        camera.camera?.automaticallyAdjustsZRange = false
        camera.position = SCNVector3(0, 0.35, 15.0)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        update(0)
    }

    private func addLayer(width: CGFloat, height: CGFloat, radius: CGFloat,
                          depth: CGFloat, bevel: CGFloat, front: CGFloat, material: SCNMaterial) {
        // Explicit rings give the straight edges and rounded corners continuous
        // analytic normals; text-outline tessellation produces unstable slivers here.
        let steps = 32
        let count = 4 * (steps + 1)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []
        func ring(z: CGFloat, inset: CGFloat, radial: CGFloat, axial: CGFloat) {
            let r = radius - inset
            let centers = [CGPoint(x: width/2-radius, y: -height/2+radius),
                           CGPoint(x: width/2-radius, y: height/2-radius),
                           CGPoint(x: -width/2+radius, y: height/2-radius),
                           CGPoint(x: -width/2+radius, y: -height/2+radius)]
            for corner in 0..<4 {
                for i in 0...steps {
                    let angle = (CGFloat(corner) - 1) * .pi/2 + CGFloat(i)/CGFloat(steps) * .pi/2
                    let x = cos(angle), y = sin(angle)
                    vertices.append(SCNVector3(centers[corner].x + r*x, centers[corner].y + r*y, z))
                    normals.append(SCNVector3(radial*x, radial*y, axial))
                }
            }
        }
        let back = front - depth
        for i in 0...8 {
            let angle = .pi/2 * (1 - CGFloat(i)/8)
            ring(z: back + bevel - bevel*sin(angle), inset: bevel*(1-cos(angle)),
                 radial: cos(angle), axial: -sin(angle))
        }
        for i in 0...8 {
            let angle = .pi/2 * CGFloat(i)/8
            ring(z: front - bevel + bevel*sin(angle), inset: bevel*(1-cos(angle)),
                 radial: cos(angle), axial: sin(angle))
        }
        for row in 0..<17 {
            for i in 0..<count {
                let a = UInt32(row*count+i), b = UInt32(row*count+(i+1)%count)
                let c = UInt32((row+1)*count+i), d = UInt32((row+1)*count+(i+1)%count)
                indices += [a,b,c, b,d,c]
            }
        }
        let backCenter = UInt32(vertices.count)
        vertices.append(SCNVector3(0,0,back)); normals.append(SCNVector3(0,0,-1))
        let frontCenter = UInt32(vertices.count)
        vertices.append(SCNVector3(0,0,front)); normals.append(SCNVector3(0,0,1))
        for i in 0..<count {
            let a = UInt32(i), b = UInt32((i+1)%count)
            indices += [backCenter,b,a, frontCenter,UInt32(17*count)+a,UInt32(17*count)+b]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        product.addChildNode(SCNNode(geometry: geometry))
    }

    private static let studioEnvironment: CGImage = {
        let width = 2048, height = 1024
        var pixels = [Float](repeating: 0, count: width * height * 4)
        func box(_ u: Double, _ v: Double, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Double {
            let dx = min(abs(u - x), 1 - abs(u - x)) / w
            let dy = abs(v - y) / h
            return exp(-pow(dx, 8) - pow(dy, 8))
        }
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let key = 3.8 * box(u, v, 0.18, 0.37, 0.09, 0.24)
                let rim = 5.0 * box(u, v, 0.70, 0.43, 0.025, 0.32)
                let value = Float(0.0004 + key + rim)
                let index = (y * width + x) * 4
                pixels[index] = value * 0.96
                pixels[index + 1] = value * 0.985
                pixels[index + 2] = value
                pixels[index + 3] = 1
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        let info = CGBitmapInfo.floatComponents.union(.byteOrder32Little)
            .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(width: width, height: height, bitsPerComponent: 32,
                       bitsPerPixel: 128, bytesPerRow: width * 16,
                       space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                       bitmapInfo: info, provider: CGDataProvider(data: data)!,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }()

    func update(_ t: Double) {
        func ease(_ a: Double, _ b: Double) -> Double {
            let p = min(1, max(0, (t - a) / (b - a)))
            return p * p * p * (p * (p * 6 - 15) + 10)
        }
        let opening = ease(0.35, 2.5) * (1 - ease(5.1, 7.0))
        let finishing = ease(4.6, 6.9) * (1 - ease(9.4, 10.6))
        let firstTravel = ease(0.35, 7.0)
        let secondTravel = ease(4.6, 10.6)
        let turn = ease(0, 10.8)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        product.eulerAngles = SCNVector3(-0.22 + 0.10 * turn, -0.64 + 0.32 * turn, 0)
        left.position = SCNVector3(-6.3 + 2.8 * firstTravel, 4.5 + 0.7 * firstTravel, 1.4 + 3.8 * firstTravel)
        right.position = SCNVector3(6.0 - 0.8 * secondTravel, 2.1 - 2.4 * secondTravel, 1.8 + 3.9 * secondTravel)
        left.light?.intensity = 700 * opening
        right.light?.intensity = 900 * finishing
        scene.lightingEnvironment.intensity = 0.28 * opening + 0.32 * finishing
        scene.lightingEnvironment.contentsTransform = SCNMatrix4MakeRotation(-0.42 + 0.64 * turn, 0, 1, 0)
        screen.diffuse.intensity = (0.12 * ease(2.1, 4.5) + 0.38 * ease(5.4, 8.1)) * (1 - ease(9.4, 10.6))
        SCNTransaction.commit()
        SCNTransaction.flush()
    }
}

struct ProductStageView: NSViewRepresentable {
    let stage: ProductStage
    let elapsed: Double
    let size: CGSize

    final class Coordinator {
        let renderer = SCNRenderer(device: nil, options: nil)
        var stageID: ObjectIdentifier?
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
        if context.coordinator.stageID != ObjectIdentifier(stage) {
            renderer.scene = stage.scene
            renderer.pointOfView = stage.camera
            renderer.autoenablesDefaultLighting = false
            _ = renderer.prepare(stage.scene, shouldAbortBlock: nil)
            context.coordinator.stageID = ObjectIdentifier(stage)
        }
        stage.update(elapsed)
        let image = renderer.snapshot(atTime: elapsed,
            with: CGSize(width: size.width * 2, height: size.height * 2),
            antialiasingMode: .multisampling8X)
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
