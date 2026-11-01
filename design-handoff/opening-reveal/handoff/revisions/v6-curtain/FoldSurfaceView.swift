import AppKit
import SceneKit

/// Two continuous, textured sheets peel away from a single vertical seam.
/// All deformation is derived from scroll progress; the native destination stays fixed below.
@MainActor final class FoldSurfaceView: SCNView {
    private let sourceImage: CGImage
    private var sheets: [SCNNode] = []
    private var currentProgress = 0.0
    private var surfaceMaterials: [SCNMaterial] = []
    private let segments = 96
    private let thickness: Float = 1.15

    override var isOpaque: Bool { false }

    init(frame: CGRect, image: CGImage) {
        sourceImage = image
        super.init(frame: frame, options: nil)
        backgroundColor = .clear
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        if #available(macOS 26.0, *) {
            layer?.preferredDynamicRange = .standard
        } else {
            layer?.wantsExtendedDynamicRangeContent = false
        }
        allowsCameraControl = false
        rendersContinuously = true
        preferredFramesPerSecond = 60
        antialiasingMode = .multisampling4X
        rebuildScene()
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:image:)") }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = bounds.size != newSize
        super.setFrameSize(newSize)
        if changed { rebuildScene() }
    }

    func setProgress(_ value: Double) {
        currentProgress = value.isFinite ? min(max(value, 0), 1) : 0
        isHidden = currentProgress >= 1
        guard sheets.count == 2 else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        for (index, node) in sheets.enumerated() {
            node.geometry = geometry(side: index == 0 ? -1 : 1, progress: currentProgress)
        }
        SCNTransaction.commit()
        needsDisplay = true
    }

    private func rebuildScene() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        self.scene = scene
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 1
        camera.zFar = 10000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, Float(bounds.height / (2 * tan(CGFloat.pi / 12))))
        scene.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 350
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        let key = SCNLight()
        key.type = .directional
        key.intensity = 850
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
        key.shadowRadius = 12
        key.shadowSampleCount = 16
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.22, -0.32, 0)
        scene.rootNode.addChildNode(keyNode)

        let receiver = SCNPlane(width: bounds.width, height: bounds.height)
        let shadow = SCNMaterial()
        shadow.lightingModel = .shadowOnly
        shadow.diffuse.contents = NSColor.black
        shadow.writesToDepthBuffer = false
        receiver.materials = [shadow]
        let receiverNode = SCNNode(geometry: receiver)
        receiverNode.position.z = -3
        receiverNode.castsShadow = false
        scene.rootNode.addChildNode(receiverNode)
        sheets = (0..<2).map { _ in
            let node = SCNNode()
            node.castsShadow = true
            scene.rootNode.addChildNode(node)
            return node
        }
        setProgress(currentProgress)
    }

    private func geometry(side: Float, progress: Double) -> SCNGeometry {
        let p = Float(progress)
        let half = Float(bounds.width) * 0.5
        let height = Float(bounds.height)
        // The central edge leads. The sheet progressively bends through a broad arc,
        // then travels beyond the viewport; no crosscuts or independent tiles exist.
        let bend = sin(p * .pi) * 1.26
        let travel = half * 1.35 * pow(p, 1.7)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        for back in 0...1 {
            for row in 0...1 {
                for column in 0...segments {
                    let u = Float(column) / Float(segments) // seam to outside
                    let angle = bend * (1 - u)
                    // Integrating the tangent gives a continuous inextensible curve.
                    let distance: Float = bend > 0.0001
                        ? half * (sin(bend) - sin(bend * (1 - u))) / bend
                        : half * u
                    let z: Float = bend > 0.0001
                        ? half * (cos(bend * (1 - u)) - cos(bend)) / bend
                        : 0
                    let nx = -side * sin(angle)
                    let nz = cos(angle)
                    let offset = back == 0 ? Float(0) : -thickness
                    vertices.append(SCNVector3(side * (distance + travel) + nx * offset,
                                               row == 0 ? -height * 0.5 : height * 0.5,
                                               z + nz * offset))
                    normals.append(SCNVector3(back == 0 ? nx : -nx, 0, back == 0 ? nz : -nz))
                    uv.append(CGPoint(x: CGFloat(0.5 + side * u * 0.5), y: row == 0 ? 1 : 0))

                }
            }
        }
        let stride = segments + 1
        let faceCount = stride * 2
        var front: [Int32] = []
        var back: [Int32] = []
        var edges: [Int32] = []
        func quad(_ a: Int, _ b: Int, _ c: Int, _ d: Int, into indices: inout [Int32], reverse: Bool = false) {
            let points = reverse ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
            indices.append(contentsOf: points.map(Int32.init))
        }
        for column in 0..<segments {
            quad(column, column + 1, stride + column, stride + column + 1, into: &front, reverse: side < 0)
            quad(faceCount + column, faceCount + column + 1, faceCount + stride + column,
                 faceCount + stride + column + 1, into: &back, reverse: side > 0)
            quad(column, faceCount + column, column + 1, faceCount + column + 1, into: &edges)
            quad(stride + column, stride + column + 1, faceCount + stride + column,
                 faceCount + stride + column + 1, into: &edges)
        }
        for column in [0, segments] {
            quad(column, stride + column, faceCount + column, faceCount + stride + column, into: &edges)
        }
        if surfaceMaterials.isEmpty {
            let texture = SCNMaterial()
            texture.lightingModel = .constant
            texture.diffuse.contents = sourceImage
            texture.diffuse.magnificationFilter = .linear
            texture.diffuse.minificationFilter = .linear
            texture.diffuse.mipFilter = .linear
            texture.isDoubleSided = false
            texture.shaderModifiers = [.surface: "_surface.diffuse.rgb *= 1.0 - 0.22 * abs(_surface.normal.x);"]
            let underside = SCNMaterial()
            underside.lightingModel = .physicallyBased
            underside.diffuse.contents = NSColor(calibratedWhite: 0.13, alpha: 1)
            underside.roughness.contents = 0.82
            let edge = SCNMaterial()
            edge.lightingModel = .physicallyBased
            edge.diffuse.contents = NSColor(calibratedWhite: 0.42, alpha: 1)
            edge.roughness.contents = 0.64
            edge.isDoubleSided = true
            surfaceMaterials = [texture, underside, edge]
        }
        let result = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                           SCNGeometrySource(textureCoordinates: uv)],
                                 elements: [front, back, edges].map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        result.materials = surfaceMaterials
        return result
    }
}
