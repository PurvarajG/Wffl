import AppKit
import SceneKit

/// Exact-content Tetris pieces fold and travel away to uncover the live native view below.
/// Geometry is built when the viewport changes; scroll progress only updates node transforms.
@MainActor final class FoldSurfaceView: SCNView {
    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    private struct Placement {
        let name: String
        let cells: [Cell]
    }

    private struct Piece {
        let node: SCNNode
        let origin: SIMD2<Float>
        let direction: SIMD2<Float>
        let waveRank: Float
    }

    private let sourceImage: CGImage
    private var pieces: [Piece] = []
    private var currentProgress = 0.0
    private var textureMaterial: SCNMaterial?
    private var backMaterial: SCNMaterial?
    private var sideMaterial: SCNMaterial?
    private let targetCellSize: CGFloat = 82
    private let depth: Float = 12

    /// Four connected tetrominoes exactly tile a 4×4 template.
    /// Rows are top-to-bottom and columns left-to-right.
    private static let template: [Placement] = [
        Placement(name: "L", cells: [Cell(row: 0, column: 0), Cell(row: 1, column: 0),
                                      Cell(row: 2, column: 0), Cell(row: 2, column: 1)]),
        Placement(name: "O", cells: [Cell(row: 0, column: 1), Cell(row: 0, column: 2),
                                      Cell(row: 1, column: 1), Cell(row: 1, column: 2)]),
        Placement(name: "J", cells: [Cell(row: 0, column: 3), Cell(row: 1, column: 3),
                                      Cell(row: 2, column: 2), Cell(row: 2, column: 3)]),
        Placement(name: "I", cells: [Cell(row: 3, column: 0), Cell(row: 3, column: 1),
                                      Cell(row: 3, column: 2), Cell(row: 3, column: 3)])
    ]

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
        guard !pieces.isEmpty else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        let p = Float(currentProgress)
        let maxTravel = hypot(Float(bounds.width), Float(bounds.height)) * 1.6 + max(Float(bounds.width), Float(bounds.height))
        for piece in pieces {
            let start = 0.08 + piece.waveRank * 0.24
            let local = min(max((p - start) / (0.76 - start), 0), 1)
            let eased = local * local * (3 - 2 * local)
            let roll = min(eased / 0.45, 1)
            let rollEase = roll * roll * (3 - 2 * roll)
            let run = min(max((eased - 0.45) / 0.55, 0), 1)
            let runEase = run * run * (3 - 2 * run)
            let angle = rollEase * 0.92 + runEase * 1.08
            let travel = rollEase * 48 + runEase * maxTravel
            piece.node.position = SCNVector3(piece.origin.x + piece.direction.x * travel,
                                             piece.origin.y + piece.direction.y * travel,
                                             11 * sin(rollEase * .pi * 0.5))
            // Rotate each connected tetromino as a single rigid block around its centroid.
            piece.node.rotation = SCNVector4(-piece.direction.y, piece.direction.x, 0, angle)
        }
        SCNTransaction.commit()
        needsDisplay = true
    }

    /// Stable, read-only snapshot for the native review harness when comparing reversed progress.
    func transformSnapshotForReview() -> [(position: SCNVector3, rotation: SCNVector4)] {
        pieces.map { ($0.node.position, $0.node.rotation) }
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
        ambient.intensity = 480
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

        configureMaterials()
        buildPieces(in: scene)
        setProgress(currentProgress)
    }

    private func configureMaterials() {
        let texture = SCNMaterial()
        // Constant shading keeps the captured text/image pixels unchanged at rest.
        texture.lightingModel = .constant
        texture.diffuse.contents = sourceImage
        texture.diffuse.magnificationFilter = .linear
        texture.diffuse.minificationFilter = .linear
        texture.diffuse.mipFilter = .linear
        texture.isDoubleSided = false
        let back = SCNMaterial()
        back.lightingModel = .physicallyBased
        back.diffuse.contents = NSColor(calibratedWhite: 0.105, alpha: 1)
        back.roughness.contents = 0.84
        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = NSColor(calibratedWhite: 0.34, alpha: 1)
        side.roughness.contents = 0.62
        side.isDoubleSided = true
        textureMaterial = texture
        backMaterial = back
        sideMaterial = side
    }

    private func buildPieces(in scene: SCNScene) {
        let columns = max(1, Int(ceil(bounds.width / targetCellSize)))
        let rows = max(1, Int(ceil(bounds.height / targetCellSize)))
        let cellWidth = Float(bounds.width / CGFloat(columns))
        let cellHeight = Float(bounds.height / CGFloat(rows))
        var ownership = Array(repeating: 0, count: rows * columns)
        var cellGroups: [[Cell]] = []

        for chunkRow in stride(from: 0, to: rows, by: 4) {
            for chunkColumn in stride(from: 0, to: columns, by: 4) {
                for placement in Self.template {
                    let cells = placement.cells.compactMap { templateCell -> Cell? in
                        let cell = Cell(row: chunkRow + templateCell.row,
                                        column: chunkColumn + templateCell.column)
                        guard cell.row < rows, cell.column < columns else { return nil }
                        ownership[cell.row * columns + cell.column] += 1
                        return cell
                    }
                    if !cells.isEmpty {
                        precondition(isConnected(cells), "Every clipped boundary piece must stay connected")
                        cellGroups.append(cells)
                    }
                }
            }
        }

        // The fixed template is a non-overlapping cover; assert the actual viewport grid too.
        precondition(ownership.allSatisfy { $0 == 1 }, "Every screen cell must be assigned exactly once")
        precondition(Self.template.allSatisfy { $0.cells.count == 4 && isConnected($0.cells) },
                     "Template entries must be connected tetrominoes")

        let maxRadius = max(1, hypot(Float(bounds.width), Float(bounds.height)) * 0.5)
        pieces = cellGroups.map { cells in
            let points = cells.map { cell in
                SIMD2<Float>((Float(cell.column) + 0.5) * cellWidth - Float(bounds.width) * 0.5,
                             Float(bounds.height) * 0.5 - (Float(cell.row) + 0.5) * cellHeight)
            }
            let center = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
            let radial = SIMD2<Float>(center.x, center.y)
            let radius = simd_length(radial)
            let direction = radius > 0.001 ? radial / radius : SIMD2<Float>(0.7071068, 0.7071068)
            let geometry = pieceGeometry(cells, center: center, cellWidth: cellWidth, cellHeight: cellHeight,
                                         rows: rows, columns: columns)
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(center.x, center.y, 0)
            node.castsShadow = true
            node.name = "TetrisPiece-\(cells.count)"
            scene.rootNode.addChildNode(node)
            return Piece(node: node, origin: center, direction: direction,
                         waveRank: min(radius / maxRadius, 1))
        }
    }

    private func isConnected(_ cells: [Cell]) -> Bool {
        guard let first = cells.first else { return false }
        var visited: Set<Cell> = [first]
        var frontier = [first]
        while let cell = frontier.popLast() {
            for neighbor in [Cell(row: cell.row - 1, column: cell.column),
                             Cell(row: cell.row + 1, column: cell.column),
                             Cell(row: cell.row, column: cell.column - 1),
                             Cell(row: cell.row, column: cell.column + 1)] where cells.contains(neighbor) {
                if visited.insert(neighbor).inserted { frontier.append(neighbor) }
            }
        }
        return visited.count == cells.count
    }

    private func pieceGeometry(_ cells: [Cell], center: SIMD2<Float>, cellWidth: Float,
                               cellHeight: Float, rows: Int, columns: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        var front: [Int32] = []
        var back: [Int32] = []
        var sides: [Int32] = []
        let frontDepth: Float = 0
        let backDepth = -depth

        func appendVertex(_ point: SIMD2<Float>, z: Float, normal: SCNVector3, tex: CGPoint) -> Int32 {
            vertices.append(SCNVector3(point.x, point.y, z))
            normals.append(normal)
            uv.append(tex)
            return Int32(vertices.count - 1)
        }
        func appendQuad(_ points: [SIMD2<Float>], z: Float, normal: SCNVector3,
                        coords: [CGPoint], into indices: inout [Int32], reverse: Bool = false) {
            let base = Int32(vertices.count)
            for index in 0..<4 {
                _ = appendVertex(points[index], z: z, normal: normal, tex: coords[index])
            }
            let order: [Int32] = reverse ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3]
            indices.append(contentsOf: order.map { base + $0 })
        }

        for cell in cells {
            let left = Float(cell.column) * cellWidth - Float(bounds.width) * 0.5 - center.x
            let right = left + cellWidth
            let top = Float(bounds.height) * 0.5 - Float(cell.row) * cellHeight - center.y
            let bottom = top - cellHeight
            let x0 = CGFloat(cell.column) / CGFloat(columns)
            let x1 = CGFloat(cell.column + 1) / CGFloat(columns)
            // Match the existing SceneKit source-image convention: top of screen uses v=0.
            let vTop = CGFloat(cell.row) / CGFloat(rows)
            let vBottom = CGFloat(cell.row + 1) / CGFloat(rows)
            let points = [SIMD2<Float>(left, bottom), SIMD2<Float>(right, bottom),
                          SIMD2<Float>(right, top), SIMD2<Float>(left, top)]
            let coords = [CGPoint(x: x0, y: vBottom), CGPoint(x: x1, y: vBottom),
                          CGPoint(x: x1, y: vTop), CGPoint(x: x0, y: vTop)]
            appendQuad(points, z: frontDepth, normal: SCNVector3(0, 0, 1), coords: coords, into: &front)
            appendQuad(points, z: backDepth, normal: SCNVector3(0, 0, -1), coords: coords, into: &back, reverse: true)

            let exposedEdges: [(Cell, SIMD2<Float>, SIMD2<Float>, CGPoint, CGPoint, SIMD2<Float>)] = [
                (Cell(row: cell.row - 1, column: cell.column), SIMD2(left, top), SIMD2(right, top),
                 CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), SIMD2(0, 1)),
                (Cell(row: cell.row + 1, column: cell.column), SIMD2(right, bottom), SIMD2(left, bottom),
                 CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), SIMD2(0, -1)),
                (Cell(row: cell.row, column: cell.column - 1), SIMD2(left, bottom), SIMD2(left, top),
                 CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), SIMD2(-1, 0)),
                (Cell(row: cell.row, column: cell.column + 1), SIMD2(right, top), SIMD2(right, bottom),
                 CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), SIMD2(1, 0))
            ]
            for (neighbor, start, end, uvStart, uvEnd, outward) in exposedEdges where !cells.contains(neighbor) {
                let indices = [start, end, end, start]
                let tex = [uvStart, uvEnd, uvEnd, uvStart]
                let base = Int32(vertices.count)
                for index in 0..<4 {
                    let z = index < 2 ? frontDepth : backDepth
                    _ = appendVertex(indices[index], z: z, normal: SCNVector3(outward.x, outward.y, 0), tex: tex[index])
                }
                sides.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }

        let result = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                            SCNGeometrySource(normals: normals),
                                            SCNGeometrySource(textureCoordinates: uv)],
                                 elements: [front, back, sides].map {
                                     SCNGeometryElement(indices: $0, primitiveType: .triangles)
                                 })
        result.materials = [textureMaterial!, backMaterial!, sideMaterial!]
        return result
    }
}
