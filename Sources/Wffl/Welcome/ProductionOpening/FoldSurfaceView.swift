import AppKit
import SceneKit
import simd

private struct CubeBakePose: Sendable {
    let x, y, z: Float
    let real, ix, iy, iz: Float
}

private struct CubeBakeResult: Sendable {
    let poses: [[CubeBakePose]]
    let rows: Int
    let columns: Int
    let contacts: Int
}

/// SceneKit's deterministic physics simulation runs on a worker queue. Only plain
/// transform samples cross back to the main actor; visible nodes are built there.
private enum CubePhysicsBake {
    private struct Cube {
        let node: SCNNode
        let row: Int
        let column: Int
        let releaseTime: TimeInterval
        let initial: SIMD3<Float>
    }
    private final class ContactCounter: NSObject, SCNPhysicsContactDelegate {
        var count = 0
        func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) { count += 1 }
    }

    static func run(width: CGFloat, height: CGFloat) async throws -> CubeBakeResult {
        let side: Float = 80
        let step = 1.0 / 120.0
        let frameCount = 601
        let columns = max(1, Int(ceil(width / CGFloat(side))))
        let rows = max(1, Int(ceil(height / CGFloat(side))))
        let imageWidth = Float(width), imageHeight = Float(height)
        let simulation = SCNScene()
        simulation.physicsWorld.gravity = SCNVector3(0, -1000, 0)
        simulation.physicsWorld.timeStep = step
        let contacts = ContactCounter()
        simulation.physicsWorld.contactDelegate = contacts
        let box = SCNBox(width: CGFloat(side), height: CGFloat(side), length: CGFloat(side), chamferRadius: 0)
        let shape = SCNPhysicsShape(geometry: box, options: nil)
        let releaseStep = 1.1 / Double(max(rows - 1, 1))
        var cubes: [Cube] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let position = SIMD3<Float>(-imageWidth * 0.5 + (Float(column) + 0.5) * side,
                                            imageHeight * 0.5 - (Float(row) + 0.5) * side, -side * 0.5)
                let node = SCNNode(geometry: box)
                node.simdPosition = position
                let body = SCNPhysicsBody(type: .kinematic, shape: shape)
                body.mass = 1; body.friction = 0.2; body.restitution = 0.08
                body.angularDamping = 0.08; body.contactTestBitMask = -1
                node.physicsBody = body
                simulation.rootNode.addChildNode(node)
                let columnOffset = Double((column * 17 + row * 23) % 41) / 100
                cubes.append(Cube(node: node, row: row, column: column,
                                  releaseTime: Double(rows - 1 - row) * releaseStep + columnOffset,
                                  initial: position))
            }
        }
        func staticBox(_ w: Float, _ h: Float, _ d: Float, _ position: SCNVector3) -> SCNNode {
            let geometry = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geometry, options: nil))
            simulation.rootNode.addChildNode(node)
            return node
        }
        let floor = staticBox(imageWidth + side * 6, side * 0.2, side * 10,
                              SCNVector3(0, -imageHeight * 0.5 - side * 0.6, -side * 1.75))
        _ = staticBox(side, imageHeight + side * 8, side * 10,
                      SCNVector3(-imageWidth * 0.5 - side * 0.75, 0, -side * 1.75))
        _ = staticBox(side, imageHeight + side * 8, side * 10,
                      SCNVector3(imageWidth * 0.5 + side * 0.75, 0, -side * 1.75))
        _ = staticBox(imageWidth + side * 8, imageHeight + side * 8, side * 0.2,
                      SCNVector3(0, 0, side * 1.1))
        _ = staticBox(imageWidth + side * 8, imageHeight + side * 8, side * 0.2,
                      SCNVector3(0, 0, -side * 4.1))
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = simulation
        renderer.isPlaying = true
        _ = renderer.snapshot(atTime: 0, with: NSSize(width: 2, height: 2), antialiasingMode: .none)
        let identity = simd_quatf(real: 1, imag: SIMD3<Float>(repeating: 0))
        var poses = cubes.map { cube in [CubeBakePose(x: cube.initial.x, y: cube.initial.y, z: cube.initial.z,
                                                       real: identity.real, ix: identity.imag.x,
                                                       iy: identity.imag.y, iz: identity.imag.z)] }
        var released = Array(repeating: false, count: cubes.count)
        for frame in 1..<frameCount {
            if frame.isMultiple(of: 20) { try Task.checkCancellation(); await Task.yield() }
            let time = Double(frame) * step
            for (index, cube) in cubes.enumerated() where !released[index] && time >= cube.releaseTime {
                let body = SCNPhysicsBody(type: .dynamic, shape: shape)
                body.mass = 1; body.friction = 0.2; body.restitution = 0.08
                body.angularDamping = 0.08; body.contactTestBitMask = -1
                cube.node.physicsBody = body
                let seed = (cube.row * 73856093) ^ (cube.column * 19349663) ^ 0x45D9F3B
                let jitter = Float(abs(seed % 1000)) / 1000
                var axisVector = SIMD3<Float>(
                    (Float((cube.column * 17 + cube.row * 31) % 11) / 10 - 0.5) * 2,
                    (Float((cube.column * 23 + cube.row * 19) % 13) / 12 - 0.5) * 2,
                    Float((cube.column * 11 + cube.row * 7) % 9) / 4 - 1)
                if simd_length_squared(axisVector) < 0.01 { axisVector = SIMD3<Float>(0, 0, 1) }
                let axis = simd_normalize(axisVector)
                body.velocity = SCNVector3((jitter - 0.5) * 200, -8, -40 - Float(abs(seed % 141)))
                body.angularVelocity = SCNVector4(axis.x, axis.y, axis.z, 2 + jitter)
                released[index] = true
            }
            if time >= 2.4, floor.parent != nil { floor.removeFromParentNode() }
            _ = renderer.snapshot(atTime: time, with: NSSize(width: 2, height: 2), antialiasingMode: .none)
            for (index, cube) in cubes.enumerated() {
                let transform = cube.node.presentation.simdTransform
                let rotation = simd_float3x3(columns: (
                    SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                    SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                    SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
                let q = simd_normalize(simd_quatf(rotation))
                poses[index].append(CubeBakePose(x: transform.columns.3.x, y: transform.columns.3.y,
                                                  z: transform.columns.3.z, real: q.real,
                                                  ix: q.imag.x, iy: q.imag.y, iz: q.imag.z))
            }
        }
        return CubeBakeResult(poses: poses, rows: rows, columns: columns, contacts: contacts.count)
    }
}

/// Equal-sized textured cubes tumble under baked physics, then fall below the live view.
/// The independent simulation is sampled once; scroll scrubbing only interpolates saved poses.
@MainActor final class FoldSurfaceView: SCNView {
    private struct Pose {
        let position: SIMD3<Float>
        let orientation: simd_quatf
    }

    private struct PlaybackCube {
        let node: SCNNode
        let poses: [Pose]
    }

    private let sourceImage: CGImage
    private var playbackCubes: [PlaybackCube] = []
    private var currentProgress = 0.0
    private let cubeSide: Float = 80
    private let simulationStep: TimeInterval = 1.0 / 120.0
    private let simulationDuration: TimeInterval = 5.0
    private var frameCount: Int { Int(simulationDuration / simulationStep) + 1 }
    private var bakeGeneration = 0
    private var bakeTask: Task<CubeBakeResult?, Never>?
    var onBakeReady: (() -> Void)?
    private(set) var hasBaked = false

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

    func setProgress(_ value: Double) {
        currentProgress = value.isFinite ? min(max(value, 0), 1) : 0
        isHidden = currentProgress >= 1
        guard !playbackCubes.isEmpty else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        let simTime = currentProgress * simulationDuration
        let frame = min(max(simTime / simulationStep, 0), Double(frameCount - 1))
        let lowerIndex = Int(frame)
        let upperIndex = min(lowerIndex + 1, frameCount - 1)
        let amount = Float(frame - Double(lowerIndex))
        for cube in playbackCubes {
            let first = cube.poses[lowerIndex]
            let second = cube.poses[upperIndex]
            cube.node.simdPosition = simd_mix(first.position, second.position, SIMD3<Float>(repeating: amount))
            cube.node.simdOrientation = simd_slerp(first.orientation, second.orientation, amount)
        }
        SCNTransaction.commit()
        needsDisplay = true
    }

    func cancelBake() {
        bakeGeneration += 1
        bakeTask?.cancel()
        bakeTask = nil
    }

    /// Stable transform ordering for the handoff review's forward/reverse comparisons.
    func transformSnapshotForReview() -> [(position: SCNVector3, rotation: SCNVector4)] {
        playbackCubes.map { ($0.node.position, $0.node.rotation) }
    }

    private func rebuildScene() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let displayScene = SCNScene()
        displayScene.background.contents = NSColor.clear
        self.scene = displayScene

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 1
        camera.zFar = 10000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, Float(bounds.height / (2 * tan(CGFloat.pi / 12))))
        displayScene.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 480
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        displayScene.rootNode.addChildNode(ambientNode)
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
        displayScene.rootNode.addChildNode(keyNode)

        let receiver = SCNPlane(width: bounds.width, height: bounds.height)
        let shadow = SCNMaterial()
        shadow.lightingModel = .shadowOnly
        shadow.diffuse.contents = NSColor.black
        shadow.writesToDepthBuffer = false
        receiver.materials = [shadow]
        let receiverNode = SCNNode(geometry: receiver)
        receiverNode.position.z = -3
        receiverNode.castsShadow = false
        displayScene.rootNode.addChildNode(receiverNode)

        configureMaterials()
        bakeGeneration += 1
        let generation = bakeGeneration
        let width = bounds.width, height = bounds.height
        bakeTask?.cancel()
        hasBaked = false
        playbackCubes = []
        let work = Task.detached(priority: .userInitiated) {
            try? await CubePhysicsBake.run(width: width, height: height)
        }
        bakeTask = work
        Task { @MainActor [weak self, weak displayScene] in
            guard let result = await work.value, let self, let displayScene,
                  generation == self.bakeGeneration, self.scene === displayScene,
                  self.bounds.width == width, self.bounds.height == height else { return }
            self.install(result, into: displayScene)
        }
        setProgress(currentProgress)
    }

    private var frontMaterial: SCNMaterial!
    private var graphiteMaterial: SCNMaterial!

    private func configureMaterials() {
        let front = SCNMaterial()
        front.lightingModel = .constant
        front.diffuse.contents = sourceImage
        front.diffuse.magnificationFilter = .linear
        front.diffuse.minificationFilter = .linear
        front.diffuse.mipFilter = .linear
        front.diffuse.wrapS = .clamp
        front.diffuse.wrapT = .clamp
        front.isDoubleSided = false
        let graphite = SCNMaterial()
        graphite.lightingModel = .physicallyBased
        graphite.diffuse.contents = NSColor(calibratedWhite: 0.13, alpha: 1)
        graphite.roughness.contents = 0.78
        graphite.isDoubleSided = true
        frontMaterial = front
        graphiteMaterial = graphite
    }

    private func install(_ result: CubeBakeResult, into displayScene: SCNScene) {
        let columns = result.columns
        let rows = result.rows
        let imageWidth = Float(bounds.width)
        let imageHeight = Float(bounds.height)
        playbackCubes = []
        for row in 0..<rows {
            for column in 0..<columns {
                let geometry = cubeGeometry(row: row, column: column, rows: rows, columns: columns,
                                            imageWidth: imageWidth, imageHeight: imageHeight)
                let node = SCNNode(geometry: geometry)
                node.simdPosition = result.poses[row * columns + column].first.map { SIMD3($0.x, $0.y, $0.z) }!
                node.castsShadow = true
                node.name = "Cube-\(row)-\(column)"
                displayScene.rootNode.addChildNode(node)
                let poses = result.poses[row * columns + column].map {
                    Pose(position: SIMD3($0.x, $0.y, $0.z),
                         orientation: simd_quatf(real: $0.real, imag: SIMD3($0.ix, $0.iy, $0.iz)))
                }
                playbackCubes.append(PlaybackCube(node: node, poses: poses))
            }
        }
        print("Falling-cubes physics bake: \(playbackCubes.count) equal cubes, \(frameCount) frames at 120 Hz, \(result.contacts) contacts")
        hasBaked = true
        setProgress(currentProgress)
        onBakeReady?()
    }

    private func cubeGeometry(row: Int, column: Int, rows: Int, columns: Int,
                              imageWidth: Float, imageHeight: Float) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var frontIndices: [Int32] = []
        var sideIndices: [Int32] = []

        let half = cubeSide * 0.5
        let u0 = CGFloat(Float(column) * cubeSide / imageWidth)
        let u1 = CGFloat(Float(column + 1) * cubeSide / imageWidth)
        let v0 = CGFloat(Float(row) * cubeSide / imageHeight)
        let v1 = CGFloat(Float(row + 1) * cubeSide / imageHeight)
        func face(_ points: [SIMD3<Float>], normal: SIMD3<Float>, uv: [CGPoint], into indices: inout [Int32]) {
            let base = Int32(vertices.count)
            for index in 0..<4 {
                let point = points[index]
                vertices.append(SCNVector3(point.x, point.y, point.z))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
                texcoords.append(uv[index])
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        let front = [SIMD3<Float>(-half, -half, half), SIMD3(half, -half, half),
                     SIMD3(half, half, half), SIMD3(-half, half, half)]
        face(front, normal: SIMD3(0, 0, 1),
             uv: [CGPoint(x: u0, y: v1), CGPoint(x: u1, y: v1),
                  CGPoint(x: u1, y: v0), CGPoint(x: u0, y: v0)], into: &frontIndices)

        let solidUV = Array(repeating: CGPoint.zero, count: 4)
        face([SIMD3(-half, -half, -half), SIMD3(-half, half, -half),
              SIMD3(half, half, -half), SIMD3(half, -half, -half)], normal: SIMD3(0, 0, -1),
             uv: solidUV, into: &sideIndices)
        face([SIMD3(-half, half, half), SIMD3(half, half, half),
              SIMD3(half, half, -half), SIMD3(-half, half, -half)], normal: SIMD3(0, 1, 0),
             uv: solidUV, into: &sideIndices)
        face([SIMD3(-half, -half, -half), SIMD3(half, -half, -half),
              SIMD3(half, -half, half), SIMD3(-half, -half, half)], normal: SIMD3(0, -1, 0),
             uv: solidUV, into: &sideIndices)
        face([SIMD3(-half, -half, -half), SIMD3(-half, -half, half),
              SIMD3(-half, half, half), SIMD3(-half, half, -half)], normal: SIMD3(-1, 0, 0),
             uv: solidUV, into: &sideIndices)
        face([SIMD3(half, -half, half), SIMD3(half, -half, -half),
              SIMD3(half, half, -half), SIMD3(half, half, half)], normal: SIMD3(1, 0, 0),
             uv: solidUV, into: &sideIndices)

        let frontElement = SCNGeometryElement(indices: frontIndices, primitiveType: .triangles)
        let sideElement = SCNGeometryElement(indices: sideIndices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                              SCNGeometrySource(normals: normals),
                                              SCNGeometrySource(textureCoordinates: texcoords)],
                                   elements: [frontElement, sideElement])
        geometry.materials = [frontMaterial, graphiteMaterial]
        return geometry
    }
}
