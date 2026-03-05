import SwiftUI
import simd

struct OrbitCanvasView: View {
    @ObservedObject var simulation: GravitySimulation
    @Binding var selectedPlanet: Int?
    @ObservedObject var launchState: LaunchState

    @State private var pitch: Double = -0.55
    @State private var yaw: Double = 0.15

    @State private var logZoom: Double = 0.0

    private var zoom: Double { exp(logZoom) }

    private let baseMetersPerPoint: Double = 1.496e11 * 0.07

    private var metersPerPoint: Double {
        baseMetersPerPoint / zoom
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            Canvas { context, size in
                let mpp = metersPerPoint

                drawDiagonalGrid(context: context, size: size)

                // Draw trails for all bodies
                for i in 0..<simulation.bodies.count {
                    drawTrail(context: context, index: i,
                              center: center, mpp: mpp)
                }

                // Depth-sort bodies (far first)
                let depthSorted = (0..<simulation.bodies.count).sorted { a, b in
                    rotatePoint(simulation.bodies[a].position).z <
                    rotatePoint(simulation.bodies[b].position).z
                }

                for i in depthSorted {
                    drawBody(context: context, body: simulation.bodies[i], index: i,
                             center: center, mpp: mpp,
                             isSelected: selectedPlanet == i)
                }

                // Draw launch preview
                if case .aiming(let origin, let current, let worldOrigin) = launchState.phase {
                    // Placement dot
                    let placementScreen = project(worldOrigin, center: center, mpp: mpp)
                    let dotRect = CGRect(x: placementScreen.x - 5, y: placementScreen.y - 5, width: 10, height: 10)
                    let rgb = launchState.objectColor
                    context.fill(Path(ellipseIn: dotRect),
                                 with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))

                    // Velocity arrow (opposite to drag direction = slingshot)
                    let dx = origin.x - current.x
                    let dy = origin.y - current.y
                    let dragLen = hypot(dx, dy)
                    if dragLen > 5 {
                        let arrowEnd = CGPoint(x: placementScreen.x + dx, y: placementScreen.y + dy)
                        var arrowPath = Path()
                        arrowPath.move(to: placementScreen)
                        arrowPath.addLine(to: arrowEnd)
                        context.stroke(arrowPath, with: .color(.white.opacity(0.8)), lineWidth: 2)

                        // Arrowhead
                        let angle = atan2(dy, dx)
                        let headLen: CGFloat = 10
                        let head1 = CGPoint(x: arrowEnd.x - headLen * cos(angle - 0.4),
                                            y: arrowEnd.y - headLen * sin(angle - 0.4))
                        let head2 = CGPoint(x: arrowEnd.x - headLen * cos(angle + 0.4),
                                            y: arrowEnd.y - headLen * sin(angle + 0.4))
                        var headPath = Path()
                        headPath.move(to: arrowEnd)
                        headPath.addLine(to: head1)
                        headPath.move(to: arrowEnd)
                        headPath.addLine(to: head2)
                        context.stroke(headPath, with: .color(.white.opacity(0.8)), lineWidth: 2)

                        // Speed label
                        let launchVel = computeLaunchVelocity(origin: origin, current: current, center: center, mpp: mpp)
                        let speed = simd_length(launchVel)
                        let speedText = Text(String(format: "%.1e m/s", speed))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        context.draw(context.resolve(speedText),
                                     at: CGPoint(x: arrowEnd.x + 10, y: arrowEnd.y - 10), anchor: .leading)
                    }

                    // Trajectory preview
                    if launchState.trajectoryPreview.count > 1 {
                        var trajPath = Path()
                        let firstPt = project(launchState.trajectoryPreview[0], center: center, mpp: mpp)
                        trajPath.move(to: firstPt)
                        for idx in 1..<launchState.trajectoryPreview.count {
                            let pt = project(launchState.trajectoryPreview[idx], center: center, mpp: mpp)
                            trajPath.addLine(to: pt)
                        }
                        context.stroke(trajPath,
                                       with: .color(.white.opacity(0.4)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
            }
            .background(Color(red: 0.102, green: 0.090, blue: 0.078))
            .overlay(
                InputCaptureView(
                    onScroll: { delta in
                        logZoom += delta * 0.015
                        logZoom = max(-4.0, min(8.0, logZoom))
                    },
                    onDrag: { dx, dy in
                        guard !launchState.isActive else { return }
                        yaw += dx * 0.005
                        pitch += dy * 0.005
                        pitch = max(-Double.pi / 2.2, min(0.1, pitch))
                    },
                    onClick: { location in
                        if launchState.isActive && !launchState.isAiming {
                            // Place + launch with zero velocity
                            let mpp = metersPerPoint
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let worldPos = unproject(location, center: ctr, mpp: mpp)
                            let body = CelestialBody(
                                id: UUID(),
                                name: launchState.objectName,
                                mass: launchState.objectMass,
                                displayRadius: launchState.objectDisplayRadius,
                                position: worldPos,
                                velocity: .zero,
                                color: launchState.objectColor,
                                semiMajorAxis: 0,
                                eccentricity: 0,
                                inclination: 0,
                                longitudeOfNode: 0
                            )
                            simulation.addBody(body)
                            launchState.completeLaunch()
                        } else if !launchState.isActive {
                            let mpp = metersPerPoint
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            var closestIdx: Int? = nil
                            var closestDist: CGFloat = 30
                            for i in 0..<simulation.bodies.count {
                                let sp = project(simulation.bodies[i].position, center: ctr, mpp: mpp)
                                let d = hypot(location.x - sp.x, location.y - sp.y)
                                if d < closestDist {
                                    closestDist = d
                                    closestIdx = i
                                }
                            }
                            selectedPlanet = closestIdx
                        }
                    },
                    onDragStart: { location in
                        guard launchState.isActive else { return }
                        let mpp = metersPerPoint
                        let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let worldPos = unproject(location, center: ctr, mpp: mpp)
                        launchState.beginAiming(origin: location, worldOrigin: worldPos)
                    },
                    onDragMove: { location in
                        guard launchState.isAiming else { return }
                        launchState.updateAim(current: location)

                        // Recompute trajectory preview
                        if case .aiming(let origin, let current, let worldOrigin) = launchState.phase {
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let vel = computeLaunchVelocity(origin: origin, current: current, center: ctr, mpp: metersPerPoint)
                            let previewBody = CelestialBody(
                                id: UUID(),
                                name: "",
                                mass: launchState.objectMass,
                                displayRadius: launchState.objectDisplayRadius,
                                position: worldOrigin,
                                velocity: vel,
                                color: launchState.objectColor,
                                semiMajorAxis: 0,
                                eccentricity: 0,
                                inclination: 0,
                                longitudeOfNode: 0
                            )
                            launchState.trajectoryPreview = simulation.computeTrajectoryPreview(newBody: previewBody)
                        }
                    },
                    onDragEnd: { location in
                        guard case .aiming(let origin, _, let worldOrigin) = launchState.phase else { return }
                        let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let vel = computeLaunchVelocity(origin: origin, current: location, center: ctr, mpp: metersPerPoint)
                        let body = CelestialBody(
                            id: UUID(),
                            name: launchState.objectName,
                            mass: launchState.objectMass,
                            displayRadius: launchState.objectDisplayRadius,
                            position: worldOrigin,
                            velocity: vel,
                            color: launchState.objectColor,
                            semiMajorAxis: 0,
                            eccentricity: 0,
                            inclination: 0,
                            longitudeOfNode: 0
                        )
                        simulation.addBody(body)
                        launchState.completeLaunch()
                    }
                )
            )
            .overlay(alignment: .bottom) {
                timeControls
            }
        }
    }

    // MARK: - 3D Projection

    private func project(_ pos: SIMD3<Double>, center: CGPoint, mpp: Double) -> CGPoint {
        let rotated = rotatePoint(pos)
        let sx = center.x + CGFloat(rotated.x / mpp)
        let sy = center.y - CGFloat(rotated.y / mpp)
        return CGPoint(x: sx, y: sy)
    }

    private func rotatePoint(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let cosY = cos(yaw), sinY = sin(yaw)
        let x1 = p.x * cosY - p.y * sinY
        let y1 = p.x * sinY + p.y * cosY
        let z1 = p.z

        let cosP = cos(pitch), sinP = sin(pitch)
        let y2 = y1 * cosP - z1 * sinP
        let z2 = y1 * sinP + z1 * cosP

        return SIMD3<Double>(x1, y2, z2)
    }

    /// Inverse-project a screen point back to world space on the z=0 plane
    private func unproject(_ screenPoint: CGPoint, center: CGPoint, mpp: Double) -> SIMD3<Double> {
        let rx = Double(screenPoint.x - center.x) * mpp
        let ry = Double(center.y - screenPoint.y) * mpp

        // Parameterize: rotated = (rx, ry, d) for unknown depth d
        // Inverse pitch then inverse yaw gives world coordinates
        // world.z = ry*sin(-pitch) + d*cos(-pitch) = 0
        // => d = -ry * sin(-pitch) / cos(-pitch) = ry * tan(pitch)
        let cosPi = cos(-pitch), sinPi = sin(-pitch)
        let cosYi = cos(-yaw), sinYi = sin(-yaw)
        let d = ry * tan(pitch)

        let midY = ry * cosPi - d * sinPi
        let worldX = rx * cosYi - midY * sinYi
        let worldY = rx * sinYi + midY * cosYi

        return SIMD3<Double>(worldX, worldY, 0)
    }

    // MARK: - Launch velocity

    // Converts screen drag to world-space velocity.
    // Factor units: 1/seconds. At default zoom, 100px drag ≈ 50,000 m/s (orbital speed at ~0.5 AU).
    private let launchVelocityFactor: Double = 5e-8

    private func computeLaunchVelocity(origin: CGPoint, current: CGPoint,
                                        center: CGPoint, mpp: Double) -> SIMD3<Double> {
        let slingDx = origin.x - current.x
        let slingDy = origin.y - current.y
        guard hypot(slingDx, slingDy) > 1 else { return .zero }

        // Unproject two screen points to get world-space slingshot vector
        let slingEnd = CGPoint(x: origin.x + slingDx, y: origin.y + slingDy)
        let worldStart = unproject(origin, center: center, mpp: mpp)
        let worldEnd = unproject(slingEnd, center: center, mpp: mpp)

        // worldDir is in meters; multiply by factor to get m/s
        return (worldEnd - worldStart) * launchVelocityFactor
    }

    // MARK: - Drawing

    private func drawDiagonalGrid(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 50
        let color = Color(red: 0.165, green: 0.145, blue: 0.125).opacity(0.7)
        let maxDim = max(size.width, size.height) * 2

        var offset: CGFloat = -maxDim
        while offset < maxDim {
            var path = Path()
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
            context.stroke(path, with: .color(color), lineWidth: 0.5)

            var path2 = Path()
            path2.move(to: CGPoint(x: offset, y: 0))
            path2.addLine(to: CGPoint(x: offset - size.height, y: size.height))
            context.stroke(path2, with: .color(color), lineWidth: 0.5)

            offset += spacing
        }
    }

    private func drawTrail(context: GraphicsContext, index: Int,
                           center: CGPoint, mpp: Double) {
        let trail = simulation.trailPoints3D[index]
        let count = trail.count
        guard count >= 2 else { return }

        let rgb = simulation.bodies[index].color
        let baseColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        // Draw segments from oldest (index 0) to newest (index count-1)
        // Newest = near body = bright, oldest = far = transparent
        for seg in 0..<(count - 1) {
            let sp0 = project(trail[seg], center: center, mpp: mpp)
            let sp1 = project(trail[seg + 1], center: center, mpp: mpp)

            // t goes from 0 (oldest) to 1 (newest)
            let t = Double(seg) / Double(count - 1)
            let opacity = t * t * 0.6  // quadratic fade-in, max 0.6
            let lineWidth: CGFloat = 1.0 + CGFloat(t) * 1.5

            var segPath = Path()
            segPath.move(to: sp0)
            segPath.addLine(to: sp1)

            context.stroke(segPath,
                           with: .color(baseColor.opacity(opacity)),
                           lineWidth: lineWidth)
        }
    }

    private func drawBody(context: GraphicsContext, body: CelestialBody, index: Int,
                          center: CGPoint, mpp: Double, isSelected: Bool) {
        let sp = project(body.position, center: center, mpp: mpp)

        // Planet radius scales directly with zoom (via mpp).
        // displayRadius is a "real size" in meters that we project to screen,
        // with a generous multiplier so they're visible, plus a minimum size.
        let projectedR = CGFloat(body.displayRadius * 3e5 / mpp)
        let r = max(body.displayRadius * 0.4, projectedR)

        let rgb = body.color
        let color = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        let bodyRect = CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: bodyRect), with: .color(color))

        if isSelected {
            let selR = r + 4
            let selRect = CGRect(x: sp.x - selR, y: sp.y - selR, width: selR * 2, height: selR * 2)
            context.stroke(Path(ellipseIn: selRect), with: .color(.white.opacity(0.7)), lineWidth: 1.5)

            let text = Text(body.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
            context.draw(context.resolve(text),
                         at: CGPoint(x: sp.x, y: sp.y - r - 10), anchor: .bottom)
        }
    }

    // MARK: - Controls

    private var timeControls: some View {
        HStack(spacing: 16) {
            Button(action: { simulation.togglePause() }) {
                Image(systemName: simulation.isRunning ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Speed")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Slider(value: $simulation.timeScale, in: 100_000...10_000_000)
                    .frame(width: 180)
            }

            Button(action: {
                simulation.resetSimulation()
                launchState.deactivate()
                if let sel = selectedPlanet, sel >= simulation.bodies.count {
                    selectedPlanet = nil
                }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 16)
    }
}

// MARK: - Input handling

struct InputCaptureView: NSViewRepresentable {
    let onScroll: (Double) -> Void
    let onDrag: (Double, Double) -> Void
    let onClick: (CGPoint) -> Void
    var onDragStart: ((CGPoint) -> Void)? = nil
    var onDragMove: ((CGPoint) -> Void)? = nil
    var onDragEnd: ((CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> InputNSView {
        let view = InputNSView()
        view.onScroll = onScroll
        view.onDrag = onDrag
        view.onClick = onClick
        view.onDragStart = onDragStart
        view.onDragMove = onDragMove
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: InputNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDrag = onDrag
        nsView.onClick = onClick
        nsView.onDragStart = onDragStart
        nsView.onDragMove = onDragMove
        nsView.onDragEnd = onDragEnd
    }
}

class InputNSView: NSView {
    var onScroll: ((Double) -> Void)?
    var onDrag: ((Double, Double) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var isDragging = false
    private var dragStartedAbsolute = false
    private var lastDragPoint: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Double(event.scrollingDeltaY))
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragStartedAbsolute = false
        lastDragPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let viewPoint = convert(current, from: nil)
        let flipped = CGPoint(x: viewPoint.x, y: bounds.height - viewPoint.y)

        if !isDragging {
            isDragging = true
            // Fire drag start with absolute position
            let startViewPoint = convert(lastDragPoint, from: nil)
            let startFlipped = CGPoint(x: startViewPoint.x, y: bounds.height - startViewPoint.y)
            onDragStart?(startFlipped)
            dragStartedAbsolute = true
        }

        // Delta-based drag (for rotation)
        let dx = Double(current.x - lastDragPoint.x)
        let dy = Double(current.y - lastDragPoint.y)
        lastDragPoint = current
        onDrag?(dx, -dy)

        // Absolute position drag move
        onDragMove?(flipped)
    }

    override func mouseUp(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let flipped = CGPoint(x: viewPoint.x, y: bounds.height - viewPoint.y)

        if isDragging && dragStartedAbsolute {
            onDragEnd?(flipped)
        } else if !isDragging {
            onClick?(flipped)
        }
    }
}
