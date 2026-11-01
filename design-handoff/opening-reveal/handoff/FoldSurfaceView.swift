import AppKit
import SceneKit
import simd

/// Equal-sized textured cubes tumble under baked physics, then fall below the live view.
/// The independent simulation is sampled once; scroll scrubbing only interpolates saved poses.
@MainActor final class FoldSurfaceView: SCNView {
    private struct Pose {
        let position: SIMD3<Float>
        let orientation: simd_quatf
    }

    private struct Cube {
        let node: SCNNode
        let row: Int
        let column: Int
        let releaseTime: TimeInterval
        let initialPosition: SIMD3<Float>
    }

    private struct PlaybackCube {
        let node: SCNNode
        let poses: [Pose]
    }

    private final class ContactCounter: NSObject, SCNPhysicsContactDelegate {
        var count = 0
        func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
            count += 1
        }
    }

    private let sourceImage: CGImage
    private var playbackCubes: [PlaybackCube] = []
    private var currentProgress = 0.0
    private let cubeSide: Float = 80
    private let simulationStep: TimeInterval = 1.0 / 120.0
    private let simulationDuration: TimeInterval = 5.0
    private var frameCount: Int { Int(simulationDuration / simulationStep) + 1 }

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
        buildAndBakeCubes(into: displayScene)
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

    private func buildAndBakeCubes(into displayScene: SCNScene) {
        let columns = max(1, Int(ceil(bounds.width / CGFloat(cubeSide))))
        let rows = max(1, Int(ceil(bounds.height / CGFloat(cubeSide))))
        let imageWidth = Float(bounds.width)
        let imageHeight = Float(bounds.height)
        let simScene = SCNScene()
        simScene.physicsWorld.gravity = SCNVector3(0, -1000, 0)
        simScene.physicsWorld.timeStep = simulationStep
        let contactCounter = ContactCounter()
        simScene.physicsWorld.contactDelegate = contactCounter

        let box = SCNBox(width: CGFloat(cubeSide), height: CGFloat(cubeSide), length: CGFloat(cubeSide), chamferRadius: 0)
        let physicsShape = SCNPhysicsShape(geometry: box, options: nil)
        var cubes: [Cube] = []
        var posesByCube: [[Pose]] = []
        let rowReleaseStep: TimeInterval = 1.1 / Double(max(rows - 1, 1))

        for row in 0..<rows {
            for column in 0..<columns {
                let geometry = cubeGeometry(row: row, column: column, rows: rows, columns: columns,
                                            imageWidth: imageWidth, imageHeight: imageHeight)
                let node = SCNNode(geometry: geometry)
                let x = -imageWidth * 0.5 + (Float(column) + 0.5) * cubeSide
                let y = imageHeight * 0.5 - (Float(row) + 0.5) * cubeSide
                let position = SIMD3<Float>(x, y, -cubeSide * 0.5)
                node.simdPosition = position
                node.castsShadow = true
                node.name = "Cube-\(row)-\(column)"
                // Kinematic cubes hold the exact captured grid until their staggered release.
                let body = SCNPhysicsBody(type: .kinematic, shape: physicsShape)
                body.mass = 1
                body.friction = 0.2
                body.restitution = 0.08
                body.angularDamping = 0.08
                body.contactTestBitMask = -1
                node.physicsBody = body
                simScene.rootNode.addChildNode(node)
                let columnOffset = Double((column * 17 + row * 23) % 41) / 100
                cubes.append(Cube(node: node, row: row, column: column,
                                  releaseTime: Double(rows - 1 - row) * rowReleaseStep + columnOffset,
                                  initialPosition: position))
                posesByCube.append([])
            }
        }

        let floorY = -imageHeight * 0.5 - cubeSide * 0.6
        let floor = addStaticBox(width: imageWidth + cubeSide * 6, height: cubeSide * 0.2,
                                 length: cubeSide * 10, position: SCNVector3(0, floorY, -cubeSide * 1.75),
                                 to: simScene)
        _ = addStaticBox(width: cubeSide, height: imageHeight + cubeSide * 8, length: cubeSide * 10,
                     position: SCNVector3(-imageWidth * 0.5 - cubeSide * 0.75, 0, -cubeSide * 1.75), to: simScene)
        _ = addStaticBox(width: cubeSide, height: imageHeight + cubeSide * 8, length: cubeSide * 10,
                     position: SCNVector3(imageWidth * 0.5 + cubeSide * 0.75, 0, -cubeSide * 1.75), to: simScene)
        _ = addStaticBox(width: imageWidth + cubeSide * 8, height: imageHeight + cubeSide * 8, length: cubeSide * 0.2,
                     position: SCNVector3(0, 0, cubeSide * 1.1), to: simScene)
        _ = addStaticBox(width: imageWidth + cubeSide * 8, height: imageHeight + cubeSide * 8, length: cubeSide * 0.2,
                     position: SCNVector3(0, 0, -cubeSide * 4.1), to: simScene)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = simScene
        renderer.isPlaying = true
        _ = renderer.snapshot(atTime: 0, with: NSSize(width: 2, height: 2), antialiasingMode: .none)
        let identity = simd_quatf(real: 1, imag: SIMD3<Float>(repeating: 0))
        for (index, cube) in cubes.enumerated() {
            posesByCube[index].append(Pose(position: cube.initialPosition, orientation: identity))
        }

        var released = Array(repeating: false, count: cubes.count)
        for step in 1..<frameCount {
            let time = Double(step) * simulationStep
            for (index, cube) in cubes.enumerated() where !released[index] && time >= cube.releaseTime {
                release(cube, shape: physicsShape)
                released[index] = true
            }
            if time >= 2.4, floor.parent != nil { floor.removeFromParentNode() }
            _ = renderer.snapshot(atTime: time, with: NSSize(width: 2, height: 2), antialiasingMode: .none)
            recordTransforms(cubes, into: &posesByCube)
        }

        playbackCubes = zip(cubes, posesByCube).map { cube, poses in
            let geometry = cube.node.geometry!
            let node = SCNNode(geometry: geometry)
            node.simdPosition = cube.initialPosition
            node.castsShadow = true
            node.name = cube.node.name
            displayScene.rootNode.addChildNode(node)
            return PlaybackCube(node: node, poses: poses)
        }

        let maximumDisplacement = zip(cubes, posesByCube).map { cube, poses in
            poses.map { simd_length($0.position - cube.initialPosition) }.max() ?? 0
        }.max() ?? 0
        print("Tetris physics bake: \(cubes.count) equal cubes, \(frameCount) frames at 120 Hz, " +
              "max displacement \(Int(maximumDisplacement)) pt, \(contactCounter.count) contacts; " +
              "floor released at 2.4 s, duration 5.0 s")
    }

    private func release(_ cube: Cube, shape: SCNPhysicsShape) {
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = 1
        body.friction = 0.2
        body.restitution = 0.08
        body.angularDamping = 0.08
        body.contactTestBitMask = -1
        cube.node.physicsBody = body
        let seed = (cube.row * 73856093) ^ (cube.column * 19349663) ^ 0x45D9F3B
        let jitter = Float(abs(seed % 1000)) / 1000
        let lateral = (jitter - 0.5) * 200
        let depthNudge = -40 - Float(abs(seed % 141))
        let spin = 2 + jitter
        var axisVector = SIMD3<Float>(
            (Float((cube.column * 17 + cube.row * 31) % 11) / 10 - 0.5) * 2,
            (Float((cube.column * 23 + cube.row * 19) % 13) / 12 - 0.5) * 2,
            Float((cube.column * 11 + cube.row * 7) % 9) / 4 - 1)
        if simd_length_squared(axisVector) < 0.01 { axisVector = SIMD3<Float>(0, 0, 1) }
        let axis = simd_normalize(axisVector)
        body.velocity = SCNVector3(lateral, -8, depthNudge)
        body.angularVelocity = SCNVector4(axis.x, axis.y, axis.z, spin)
    }

    private func recordTransforms(_ cubes: [Cube], into poses: inout [[Pose]]) {
        for (index, cube) in cubes.enumerated() {
            let transform = cube.node.presentation.simdTransform
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let rotation = simd_float3x3(columns: (
                SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
            let orientation = simd_quatf(rotation)
            poses[index].append(Pose(position: position, orientation: simd_normalize(orientation)))
        }
    }

    private func addStaticBox(width: Float, height: Float, length: Float, position: SCNVector3,
                              to scene: SCNScene) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0)
        geometry.firstMaterial = graphiteMaterial
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geometry, options: nil))
        scene.rootNode.addChildNode(node)
        return node
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
