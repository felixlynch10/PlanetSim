import SwiftUI
import simd

struct OrbitCanvasView: View {
    @ObservedObject var simulation: GravitySimulation
    @Binding var selectedPlanet: Int?
    @ObservedObject var launchState: LaunchState
    @Binding var followingBody: Int?
    @Binding var showLabels: Bool
    @Binding var showForceVectors: Bool
    @Binding var showOrbits: Bool

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
                let followOffset = followingBody.flatMap { idx in
                    idx < simulation.bodies.count ? simulation.bodies[idx].position : nil
                } ?? .zero

                drawDiagonalGrid(context: context, size: size)

                // Draw orbit predictions
                if showOrbits {
                    for i in 1..<simulation.bodies.count {
                        drawOrbitPrediction(context: context, index: i,
                                           center: center, mpp: mpp, followOffset: followOffset)
                    }
                }

                // Draw trails
                for i in 0..<simulation.bodies.count {
                    drawTrail(context: context, index: i,
                              center: center, mpp: mpp, followOffset: followOffset)
                }

                // Collision flashes
                for collision in simulation.recentCollisions {
                    drawCollisionFlash(context: context, position: collision.position,
                                      time: collision.time, center: center, mpp: mpp,
                                      followOffset: followOffset)
                }

                // Depth-sort bodies
                let depthSorted = (0..<simulation.bodies.count).sorted { a, b in
                    rotatePoint(simulation.bodies[a].position - followOffset).z <
                    rotatePoint(simulation.bodies[b].position - followOffset).z
                }

                for i in depthSorted {
                    let body = simulation.bodies[i]
                    switch body.bodyType {
                    case .blackHole:
                        drawBlackHole(context: context, body: body, index: i,
                                      center: center, mpp: mpp,
                                      isSelected: selectedPlanet == i, followOffset: followOffset)
                    case .wormhole:
                        drawWormhole(context: context, body: body, index: i,
                                     center: center, mpp: mpp,
                                     isSelected: selectedPlanet == i, followOffset: followOffset)
                    case .neutronStar:
                        drawNeutronStar(context: context, body: body, index: i,
                                        center: center, mpp: mpp,
                                        isSelected: selectedPlanet == i, followOffset: followOffset)
                    case .normal:
                        let isStar = i == 0 && body.mass > 1e29
                        drawBody(context: context, body: body, index: i,
                                 center: center, mpp: mpp,
                                 isSelected: selectedPlanet == i,
                                 isStar: isStar, followOffset: followOffset)
                    }
                }

                // Force vectors
                if showForceVectors {
                    let accels = simulation.computeAccelerations()
                    for i in 0..<simulation.bodies.count {
                        drawForceVector(context: context, body: simulation.bodies[i],
                                       acceleration: accels[i], center: center, mpp: mpp,
                                       followOffset: followOffset)
                    }
                }

                // Launch preview
                if case .aiming(let origin, let current, let worldOrigin) = launchState.phase {
                    drawLaunchPreview(context: context, origin: origin, current: current,
                                    worldOrigin: worldOrigin, center: center, mpp: mpp,
                                    followOffset: followOffset)
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
                            let mpp = metersPerPoint
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let followOffset = followingBody.flatMap { idx in
                                idx < simulation.bodies.count ? simulation.bodies[idx].position : nil
                            } ?? .zero
                            let worldPos = unproject(location, center: ctr, mpp: mpp) + followOffset

                            if launchState.objectType == .wormhole {
                                handleWormholeClick(worldPos: worldPos)
                            } else {
                                let body = CelestialBody(
                                    id: UUID(),
                                    name: launchState.objectName,
                                    mass: launchState.objectMass,
                                    displayRadius: launchState.objectDisplayRadius,
                                    position: worldPos,
                                    velocity: .zero,
                                    color: launchState.objectColor,
                                    semiMajorAxis: 0, eccentricity: 0,
                                    inclination: 0, longitudeOfNode: 0,
                                    bodyType: launchState.objectType
                                )
                                simulation.addBody(body)
                                launchState.completeLaunch(placedBodyId: body.id)
                            }
                        } else if !launchState.isActive {
                            let mpp = metersPerPoint
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let followOffset = followingBody.flatMap { idx in
                                idx < simulation.bodies.count ? simulation.bodies[idx].position : nil
                            } ?? .zero
                            var closestIdx: Int? = nil
                            var closestDist: CGFloat = 30
                            for i in 0..<simulation.bodies.count {
                                let sp = project(simulation.bodies[i].position, center: ctr, mpp: mpp, followOffset: followOffset)
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
                        if launchState.objectType == .wormhole { return }
                        let mpp = metersPerPoint
                        let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let followOffset = followingBody.flatMap { idx in
                            idx < simulation.bodies.count ? simulation.bodies[idx].position : nil
                        } ?? .zero
                        let worldPos = unproject(location, center: ctr, mpp: mpp) + followOffset
                        launchState.beginAiming(origin: location, worldOrigin: worldPos)
                    },
                    onDragMove: { location in
                        guard launchState.isAiming else { return }
                        launchState.updateAim(current: location)

                        if case .aiming(let origin, let current, let worldOrigin) = launchState.phase {
                            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let vel = computeLaunchVelocity(origin: origin, current: current, center: ctr, mpp: metersPerPoint)
                            let previewBody = CelestialBody(
                                id: UUID(), name: "",
                                mass: launchState.objectMass,
                                displayRadius: launchState.objectDisplayRadius,
                                position: worldOrigin, velocity: vel,
                                color: launchState.objectColor,
                                semiMajorAxis: 0, eccentricity: 0,
                                inclination: 0, longitudeOfNode: 0,
                                bodyType: launchState.objectType
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
                            position: worldOrigin, velocity: vel,
                            color: launchState.objectColor,
                            semiMajorAxis: 0, eccentricity: 0,
                            inclination: 0, longitudeOfNode: 0,
                            bodyType: launchState.objectType
                        )
                        simulation.addBody(body)
                        launchState.completeLaunch(placedBodyId: body.id)
                    },
                    onKeyPress: { key in
                        handleKeyPress(key, geoSize: geo.size)
                    }
                )
            )
            .overlay(alignment: .bottom) {
                timeControls
            }
            .overlay(alignment: .topTrailing) {
                statsOverlay
            }
        }
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ key: String, geoSize: CGSize) {
        switch key {
        case " ":
            simulation.togglePause()
        case "r":
            simulation.resetSimulation()
            launchState.deactivate()
            followingBody = nil
            selectedPlanet = nil
        case "l":
            showLabels.toggle()
        case "v":
            showForceVectors.toggle()
        case "o":
            showOrbits.toggle()
        case "f":
            if let sel = selectedPlanet {
                followingBody = followingBody == sel ? nil : sel
            }
        case "z":
            zoomToFit(geoSize: geoSize)
        case "\u{1B}": // Escape
            if launchState.isActive {
                launchState.deactivate()
            } else {
                selectedPlanet = nil
                followingBody = nil
            }
        default:
            if let num = Int(key), num >= 1, num <= min(9, simulation.bodies.count) {
                selectedPlanet = num - 1
            }
        }
    }

    private func zoomToFit(geoSize: CGSize) {
        guard !simulation.bodies.isEmpty else { return }
        let followOffset = followingBody.flatMap { idx in
            idx < simulation.bodies.count ? simulation.bodies[idx].position : nil
        } ?? .zero

        var maxScreenDist: Double = 0
        let center = CGPoint(x: geoSize.width / 2, y: geoSize.height / 2)
        let halfW = Double(geoSize.width) * 0.4
        let halfH = Double(geoSize.height) * 0.4

        for body in simulation.bodies {
            let rotated = rotatePoint(body.position - followOffset)
            let screenX = abs(rotated.x)
            let screenY = abs(rotated.y)
            maxScreenDist = max(maxScreenDist, screenX, screenY)
        }

        guard maxScreenDist > 0 else { return }
        let targetMpp = maxScreenDist / min(halfW, halfH)
        let targetZoom = baseMetersPerPoint / targetMpp
        logZoom = log(targetZoom)
    }

    // MARK: - 3D Projection

    private func project(_ pos: SIMD3<Double>, center: CGPoint, mpp: Double, followOffset: SIMD3<Double> = .zero) -> CGPoint {
        let rotated = rotatePoint(pos - followOffset)
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

    private func unproject(_ screenPoint: CGPoint, center: CGPoint, mpp: Double) -> SIMD3<Double> {
        let rx = Double(screenPoint.x - center.x) * mpp
        let ry = Double(center.y - screenPoint.y) * mpp

        let cosPi = cos(-pitch), sinPi = sin(-pitch)
        let cosYi = cos(-yaw), sinYi = sin(-yaw)
        let d = ry * tan(pitch)

        let midY = ry * cosPi - d * sinPi
        let worldX = rx * cosYi - midY * sinYi
        let worldY = rx * sinYi + midY * cosYi

        return SIMD3<Double>(worldX, worldY, 0)
    }

    // MARK: - Launch velocity

    private let launchVelocityFactor: Double = 5e-8

    private func computeLaunchVelocity(origin: CGPoint, current: CGPoint,
                                        center: CGPoint, mpp: Double) -> SIMD3<Double> {
        let slingDx = origin.x - current.x
        let slingDy = origin.y - current.y
        guard hypot(slingDx, slingDy) > 1 else { return .zero }

        let slingEnd = CGPoint(x: origin.x + slingDx, y: origin.y + slingDy)
        let worldStart = unproject(origin, center: center, mpp: mpp)
        let worldEnd = unproject(slingEnd, center: center, mpp: mpp)

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
                           center: CGPoint, mpp: Double, followOffset: SIMD3<Double>) {
        guard index < simulation.trailPoints3D.count else { return }
        let trail = simulation.trailPoints3D[index]
        let count = trail.count
        guard count >= 2 else { return }

        let rgb = simulation.bodies[index].color
        let baseColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        for seg in 0..<(count - 1) {
            let p0 = trail[seg]
            let p1 = trail[seg + 1]

            // Skip NaN markers (wormhole teleport gaps)
            if p0.x.isNaN || p0.y.isNaN || p0.z.isNaN ||
               p1.x.isNaN || p1.y.isNaN || p1.z.isNaN {
                continue
            }

            var sp0 = project(p0, center: center, mpp: mpp, followOffset: followOffset)
            var sp1 = project(p1, center: center, mpp: mpp, followOffset: followOffset)

            // Apply lensing near black holes
            sp0 = applyLensingDistortion(sp0, center: center, mpp: mpp, followOffset: followOffset)
            sp1 = applyLensingDistortion(sp1, center: center, mpp: mpp, followOffset: followOffset)

            let t = Double(seg) / Double(count - 1)
            let opacity = t * t * 0.6
            let lineWidth: CGFloat = 1.0 + CGFloat(t) * 1.5

            var segPath = Path()
            segPath.move(to: sp0)
            segPath.addLine(to: sp1)

            context.stroke(segPath,
                           with: .color(baseColor.opacity(opacity)),
                           lineWidth: lineWidth)
        }
    }

    private func applyLensingDistortion(_ point: CGPoint, center: CGPoint, mpp: Double,
                                         followOffset: SIMD3<Double>) -> CGPoint {
        var result = point
        for body in simulation.bodies where body.bodyType == .blackHole {
            let bhScreen = project(body.position, center: center, mpp: mpp, followOffset: followOffset)
            let rsScreen = CGFloat(body.schwarzschildRadius / mpp)
            let maxEffect = rsScreen * 5

            let dx = result.x - bhScreen.x
            let dy = result.y - bhScreen.y
            let dist = hypot(dx, dy)

            guard dist > 1 && dist < maxEffect else { continue }

            let pushStrength = rsScreen * rsScreen / (dist * dist) * 2.0
            let nx = dx / dist
            let ny = dy / dist
            result.x += nx * pushStrength
            result.y += ny * pushStrength
        }
        return result
    }

    private func drawBody(context: GraphicsContext, body: CelestialBody, index: Int,
                          center: CGPoint, mpp: Double, isSelected: Bool,
                          isStar: Bool, followOffset: SIMD3<Double>) {
        let sp = project(body.position, center: center, mpp: mpp, followOffset: followOffset)

        let projectedR = CGFloat(body.displayRadius * 3e5 / mpp)
        let r = max(body.displayRadius * 0.4, projectedR)

        let rgb = body.color
        let color = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        // Star glow — flat concentric rings
        if isStar {
            let glowLayers: [(scale: CGFloat, opacity: Double)] = [
                (3.0, 0.04), (2.2, 0.06), (1.6, 0.10)
            ]
            for layer in glowLayers {
                let gr = r * layer.scale
                let glowRect = CGRect(x: sp.x - gr, y: sp.y - gr, width: gr * 2, height: gr * 2)
                context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(layer.opacity)))
            }
        }

        let bodyRect = CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: bodyRect), with: .color(color))

        if isSelected {
            let selR = r + 4
            let selRect = CGRect(x: sp.x - selR, y: sp.y - selR, width: selR * 2, height: selR * 2)
            context.stroke(Path(ellipseIn: selRect), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        }

        // Labels
        let shouldShowLabel = isSelected || showLabels
        if shouldShowLabel {
            let fontSize: CGFloat = isSelected ? 11 : 9
            let opacity: Double = isSelected ? 1.0 : 0.5
            let text = Text(body.name)
                .font(.system(size: fontSize, weight: isSelected ? .medium : .regular))
                .foregroundColor(.white.opacity(opacity))
            context.draw(context.resolve(text),
                         at: CGPoint(x: sp.x, y: sp.y - r - 8), anchor: .bottom)
        }
    }

    // MARK: - Black Hole Rendering

    private func drawBlackHole(context: GraphicsContext, body: CelestialBody, index: Int,
                               center: CGPoint, mpp: Double, isSelected: Bool,
                               followOffset: SIMD3<Double>) {
        let sp = project(body.position, center: center, mpp: mpp, followOffset: followOffset)
        let rsScreen = max(CGFloat(body.schwarzschildRadius / mpp), 8.0)

        // -- Outer gravitational glow: warm dim haze around the hole --
        let glowLayers: [(scale: CGFloat, r: Double, g: Double, b: Double, opacity: Double)] = [
            (6.0, 0.15, 0.06, 0.01, 0.03),
            (4.5, 0.20, 0.08, 0.02, 0.05),
            (3.5, 0.30, 0.12, 0.03, 0.06),
            (2.5, 0.45, 0.18, 0.04, 0.08),
        ]
        for layer in glowLayers {
            let gr = rsScreen * layer.scale
            let rect = CGRect(x: sp.x - gr, y: sp.y - gr, width: gr * 2, height: gr * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(Color(red: layer.r, green: layer.g, blue: layer.b).opacity(layer.opacity)))
        }

        // -- Accretion disk (behind event horizon, drawn first) --
        // Multiple band passes for thickness, with Doppler asymmetry
        let diskOuterR = rsScreen * 4.0
        let diskInnerR = rsScreen * 1.8
        let tiltY: CGFloat = 0.28  // vertical squish for inclination
        let bands = 5
        for band in 0..<bands {
            let t = CGFloat(band) / CGFloat(bands - 1)  // 0=inner, 1=outer
            let bandR = diskInnerR + (diskOuterR - diskInnerR) * t
            let steps = 80
            var diskPath = Path()
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * 2.0 * .pi
                let cosA = CGFloat(cos(angle))
                let sinA = CGFloat(sin(angle))
                let x = sp.x + bandR * cosA
                let y = sp.y + bandR * tiltY * sinA
                if step == 0 { diskPath.move(to: CGPoint(x: x, y: y)) }
                else { diskPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Doppler: left side (approaching) is brighter/bluer, right side is dimmer/redder
            let innerBright = 1.0 - Double(t) * 0.6  // inner bands brighter
            // Warm orange-yellow for hot gas
            let dr = 0.95 * innerBright
            let dg = 0.55 * innerBright
            let db = 0.12 * innerBright
            let lineW: CGFloat = max(1.0, 2.5 - CGFloat(t) * 1.5)
            context.stroke(diskPath,
                           with: .color(Color(red: dr, green: dg, blue: db).opacity(0.4 * innerBright)),
                           style: StrokeStyle(lineWidth: lineW))
        }

        // -- Photon ring: thin bright ring at 1.5 * rs --
        let photonR = rsScreen * 1.5
        let photonRect = CGRect(x: sp.x - photonR, y: sp.y - photonR,
                                width: photonR * 2, height: photonR * 2)
        context.stroke(Path(ellipseIn: photonRect),
                       with: .color(Color(red: 1.0, green: 0.85, blue: 0.5).opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.2))

        // -- Event horizon: true black void --
        let shadowR = rsScreen * 1.05  // slightly larger to eat into the photon ring
        let ehRect = CGRect(x: sp.x - shadowR, y: sp.y - shadowR,
                            width: shadowR * 2, height: shadowR * 2)
        context.fill(Path(ellipseIn: ehRect), with: .color(.black))

        // -- Einstein ring: very faint bright edge right at the shadow boundary --
        context.stroke(Path(ellipseIn: ehRect),
                       with: .color(Color(red: 1.0, green: 0.9, blue: 0.6).opacity(0.2)),
                       lineWidth: 0.8)

        // -- Front half of accretion disk (over the black hole) --
        // Only the bottom arc of the tilted disk passes in front
        for band in 0..<bands {
            let t = CGFloat(band) / CGFloat(bands - 1)
            let bandR = diskInnerR + (diskOuterR - diskInnerR) * t
            let innerBright = 1.0 - Double(t) * 0.6
            let steps = 40
            var frontPath = Path()
            // Draw only the front arc (bottom half, sin > 0 in screen space)
            for step in 0...steps {
                let angle = Double.pi + Double(step) / Double(steps) * Double.pi  // pi to 2*pi
                let cosA = CGFloat(cos(angle))
                let sinA = CGFloat(sin(angle))
                let x = sp.x + bandR * cosA
                let y = sp.y + bandR * tiltY * sinA
                if step == 0 { frontPath.move(to: CGPoint(x: x, y: y)) }
                else { frontPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            let dr = 0.95 * innerBright
            let dg = 0.55 * innerBright
            let db = 0.12 * innerBright
            let lineW: CGFloat = max(1.0, 2.5 - CGFloat(t) * 1.5)
            context.stroke(frontPath,
                           with: .color(Color(red: dr, green: dg, blue: db).opacity(0.5 * innerBright)),
                           style: StrokeStyle(lineWidth: lineW))
        }

        // Selection + label
        if isSelected {
            let selR = rsScreen * 2.0 + 4
            let selRect = CGRect(x: sp.x - selR, y: sp.y - selR, width: selR * 2, height: selR * 2)
            context.stroke(Path(ellipseIn: selRect), with: .color(.white.opacity(0.5)), lineWidth: 1.5)
        }
        if isSelected || showLabels {
            let text = Text(body.name).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(isSelected ? 1 : 0.5))
            context.draw(context.resolve(text), at: CGPoint(x: sp.x, y: sp.y - rsScreen * 2 - 10), anchor: .bottom)
        }
    }

    // MARK: - Wormhole Rendering

    private func drawWormhole(context: GraphicsContext, body: CelestialBody, index: Int,
                              center: CGPoint, mpp: Double, isSelected: Bool,
                              followOffset: SIMD3<Double>) {
        let sp = project(body.position, center: center, mpp: mpp, followOffset: followOffset)
        let baseR: CGFloat = max(CGFloat(body.displayRadius * 3e5 / mpp), 6.0)
        let time = simulation.elapsedSeconds

        // -- Outer space-warp glow: subtle bluish distortion haze --
        let outerGlowR = baseR * 3.5
        let outerRect = CGRect(x: sp.x - outerGlowR, y: sp.y - outerGlowR,
                               width: outerGlowR * 2, height: outerGlowR * 2)
        context.fill(Path(ellipseIn: outerRect),
                     with: .color(Color(red: 0.15, green: 0.25, blue: 0.6).opacity(0.06)))

        // -- Warped concentric rings that rotate slowly --
        let ringCount = 6
        for ring in 0..<ringCount {
            let t = Double(ring) / Double(ringCount - 1)  // 0=inner, 1=outer
            let ringR = baseR * CGFloat(0.6 + t * 2.0)
            let rotAngle = time * (0.3 + t * 0.2) + Double(ring) * 0.5  // each ring rotates differently
            let warpAmount = 0.15 + t * 0.1  // how elliptical the warp is
            let steps = 60
            var ringPath = Path()
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * 2.0 * .pi + rotAngle
                // Warp the circle into a subtly shifting ellipse
                let warpX = 1.0 + warpAmount * cos(angle * 2.0 + time * 0.5)
                let warpY = 1.0 + warpAmount * sin(angle * 2.0 + time * 0.7)
                let x = sp.x + ringR * CGFloat(cos(angle) * warpX)
                let y = sp.y + ringR * CGFloat(sin(angle) * warpY)
                if step == 0 { ringPath.move(to: CGPoint(x: x, y: y)) }
                else { ringPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            let opacity = 0.5 - t * 0.35
            let blue = 0.7 + t * 0.3
            let green = 0.5 + t * 0.2
            context.stroke(ringPath,
                           with: .color(Color(red: 0.3 - t * 0.15, green: green, blue: blue).opacity(max(opacity, 0.08))),
                           style: StrokeStyle(lineWidth: max(0.6, 1.5 - CGFloat(t) * 0.8)))
        }

        // -- Bright throat center with pulsing glow --
        let pulsePhase = sin(time * 2.5) * 0.3 + 0.7
        let throatR = baseR * 0.5
        let throatGlowR = baseR * CGFloat(0.9 * pulsePhase)
        let tgRect = CGRect(x: sp.x - throatGlowR, y: sp.y - throatGlowR,
                            width: throatGlowR * 2, height: throatGlowR * 2)
        context.fill(Path(ellipseIn: tgRect),
                     with: .color(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.25 * pulsePhase)))

        let throatRect = CGRect(x: sp.x - throatR, y: sp.y - throatR,
                                width: throatR * 2, height: throatR * 2)
        context.fill(Path(ellipseIn: throatRect),
                     with: .color(Color(red: 0.85, green: 0.92, blue: 1.0).opacity(0.9)))

        // -- Connection line to paired wormhole --
        if let linkedId = body.linkedWormholeId,
           let partner = simulation.bodies.first(where: { $0.id == linkedId }) {
            let partnerSp = project(partner.position, center: center, mpp: mpp, followOffset: followOffset)
            // Draw a wavy connection line
            let dx = partnerSp.x - sp.x
            let dy = partnerSp.y - sp.y
            let dist = hypot(dx, dy)
            let steps = max(20, Int(dist / 4))
            var wavePath = Path()
            wavePath.move(to: sp)
            for step in 1...steps {
                let frac = CGFloat(step) / CGFloat(steps)
                let baseX = sp.x + dx * frac
                let baseY = sp.y + dy * frac
                // Perpendicular wave
                let perpX = -dy / dist
                let perpY = dx / dist
                let waveAmp = CGFloat(sin(Double(frac) * .pi)) * min(8.0, dist * 0.03)
                let wave = CGFloat(sin(Double(frac) * 12.0 + time * 2.0)) * waveAmp
                let px = baseX + perpX * wave
                let py = baseY + perpY * wave
                wavePath.addLine(to: CGPoint(x: px, y: py))
            }
            let fadeOpacity = min(0.35, 100.0 / Double(dist + 1))
            context.stroke(wavePath,
                           with: .color(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(fadeOpacity)),
                           style: StrokeStyle(lineWidth: 1.0))
        }

        if isSelected {
            let selR = baseR * 2.0 + 4
            let selRect = CGRect(x: sp.x - selR, y: sp.y - selR, width: selR * 2, height: selR * 2)
            context.stroke(Path(ellipseIn: selRect), with: .color(.white.opacity(0.5)), lineWidth: 1.5)
        }
        if isSelected || showLabels {
            let text = Text(body.name).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(isSelected ? 1 : 0.5))
            context.draw(context.resolve(text), at: CGPoint(x: sp.x, y: sp.y - baseR * 2.5 - 8), anchor: .bottom)
        }
    }

    // MARK: - Neutron Star Rendering

    private func drawNeutronStar(context: GraphicsContext, body: CelestialBody, index: Int,
                                 center: CGPoint, mpp: Double, isSelected: Bool,
                                 followOffset: SIMD3<Double>) {
        let sp = project(body.position, center: center, mpp: mpp, followOffset: followOffset)
        let projectedR = CGFloat(body.displayRadius * 3e5 / mpp)
        let r = max(body.displayRadius * 0.4, projectedR)
        let time = simulation.elapsedSeconds

        // Rapid pulsar rotation (fast spin)
        let pulseFreq = 8.0  // Hz-like
        let pulsePhase = time * pulseFreq
        let pulseBright = 0.5 + 0.5 * abs(sin(pulsePhase))

        // -- Outer magnetosphere glow --
        let magR = r * 4.0
        let magRect = CGRect(x: sp.x - magR, y: sp.y - magR, width: magR * 2, height: magR * 2)
        context.fill(Path(ellipseIn: magRect),
                     with: .color(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.04)))

        // -- Pulsar jets (magnetic pole beams) --
        let jetLength = r * CGFloat(5.0 + pulseBright * 3.0)
        let jetWidth = r * CGFloat(0.3 + pulseBright * 0.2)
        let jetOpacity = 0.15 + pulseBright * 0.25

        // Top jet
        var topJet = Path()
        topJet.move(to: CGPoint(x: sp.x - jetWidth * 0.5, y: sp.y))
        topJet.addLine(to: CGPoint(x: sp.x, y: sp.y - jetLength))
        topJet.addLine(to: CGPoint(x: sp.x + jetWidth * 0.5, y: sp.y))
        topJet.closeSubpath()
        context.fill(topJet, with: .color(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(jetOpacity)))

        // Bottom jet
        var bottomJet = Path()
        bottomJet.move(to: CGPoint(x: sp.x - jetWidth * 0.5, y: sp.y))
        bottomJet.addLine(to: CGPoint(x: sp.x, y: sp.y + jetLength))
        bottomJet.addLine(to: CGPoint(x: sp.x + jetWidth * 0.5, y: sp.y))
        bottomJet.closeSubpath()
        context.fill(bottomJet, with: .color(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(jetOpacity)))

        // -- Inner glow layers --
        let innerGlow = r * CGFloat(1.8 + pulseBright * 0.5)
        let igRect = CGRect(x: sp.x - innerGlow, y: sp.y - innerGlow,
                            width: innerGlow * 2, height: innerGlow * 2)
        context.fill(Path(ellipseIn: igRect),
                     with: .color(Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.12 + pulseBright * 0.1)))

        // -- Intense core --
        let coreR = r * CGFloat(0.8 + pulseBright * 0.2)
        let coreRect = CGRect(x: sp.x - coreR, y: sp.y - coreR,
                              width: coreR * 2, height: coreR * 2)
        context.fill(Path(ellipseIn: coreRect),
                     with: .color(Color(red: 0.92, green: 0.95, blue: 1.0)))

        // -- Hot white center point --
        let dotR = max(1.5, r * 0.3)
        let dotRect = CGRect(x: sp.x - dotR, y: sp.y - dotR, width: dotR * 2, height: dotR * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(.white))

        if isSelected {
            let selR = r * 2.0 + 4
            let selRect = CGRect(x: sp.x - selR, y: sp.y - selR, width: selR * 2, height: selR * 2)
            context.stroke(Path(ellipseIn: selRect), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        }
        if isSelected || showLabels {
            let text = Text(body.name).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(isSelected ? 1 : 0.5))
            context.draw(context.resolve(text), at: CGPoint(x: sp.x, y: sp.y - jetLength - 8), anchor: .bottom)
        }
    }

    // MARK: - Wormhole Click Handler

    private func handleWormholeClick(worldPos: SIMD3<Double>) {
        let bodyId = UUID()
        var body = CelestialBody(
            id: bodyId,
            name: launchState.objectName,
            mass: launchState.objectMass,
            displayRadius: launchState.objectDisplayRadius,
            position: worldPos,
            velocity: .zero,
            color: launchState.objectColor,
            semiMajorAxis: 0, eccentricity: 0,
            inclination: 0, longitudeOfNode: 0,
            bodyType: .wormhole
        )
        body.throatRadius = launchState.objectThroatRadius

        if case .placingSecond(let firstId, _) = launchState.wormholePlacementPhase {
            body.linkedWormholeId = firstId
            simulation.addBody(body)
            if let firstIdx = simulation.bodies.firstIndex(where: { $0.id == firstId }) {
                simulation.bodies[firstIdx].linkedWormholeId = bodyId
            }
            launchState.completeLaunch(placedBodyId: bodyId)
        } else {
            simulation.addBody(body)
            launchState.completeLaunch(placedBodyId: bodyId)
        }
    }

    private func drawForceVector(context: GraphicsContext, body: CelestialBody,
                                 acceleration: SIMD3<Double>, center: CGPoint, mpp: Double,
                                 followOffset: SIMD3<Double>) {
        let sp = project(body.position, center: center, mpp: mpp, followOffset: followOffset)

        // Scale: log of acceleration magnitude, mapped to 20-80px arrow
        let accMag = simd_length(acceleration)
        guard accMag > 0 else { return }

        let logAcc = log10(accMag)
        let arrowLen = CGFloat(max(15, min(60, (logAcc + 5) * 12)))

        let accDir = simd_normalize(acceleration)
        let rotated = rotatePoint(accDir)
        let screenDx = CGFloat(rotated.x) * arrowLen
        let screenDy = CGFloat(-rotated.y) * arrowLen

        let arrowEnd = CGPoint(x: sp.x + screenDx, y: sp.y + screenDy)

        var arrowPath = Path()
        arrowPath.move(to: sp)
        arrowPath.addLine(to: arrowEnd)
        context.stroke(arrowPath, with: .color(.white.opacity(0.3)), lineWidth: 1.5)

        // Arrowhead
        let angle = atan2(screenDy, screenDx)
        let headLen: CGFloat = 6
        let head1 = CGPoint(x: arrowEnd.x - headLen * cos(angle - 0.5),
                            y: arrowEnd.y - headLen * sin(angle - 0.5))
        let head2 = CGPoint(x: arrowEnd.x - headLen * cos(angle + 0.5),
                            y: arrowEnd.y - headLen * sin(angle + 0.5))
        var headPath = Path()
        headPath.move(to: arrowEnd)
        headPath.addLine(to: head1)
        headPath.move(to: arrowEnd)
        headPath.addLine(to: head2)
        context.stroke(headPath, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
    }

    private func drawOrbitPrediction(context: GraphicsContext, index: Int,
                                     center: CGPoint, mpp: Double, followOffset: SIMD3<Double>) {
        guard let points = simulation.predictOrbitPoints(index: index) else { return }
        guard points.count > 1 else { return }

        let rgb = simulation.bodies[index].color
        let color = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        var orbitPath = Path()
        let first = project(points[0], center: center, mpp: mpp, followOffset: followOffset)
        orbitPath.move(to: first)
        for i in 1..<points.count {
            let pt = project(points[i], center: center, mpp: mpp, followOffset: followOffset)
            orbitPath.addLine(to: pt)
        }
        context.stroke(orbitPath,
                       with: .color(color.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawCollisionFlash(context: GraphicsContext, position: SIMD3<Double>,
                                    time: Date, center: CGPoint, mpp: Double,
                                    followOffset: SIMD3<Double>) {
        let age = simulation.simulationTime.timeIntervalSince(time)
        let maxAge: Double = 2.0
        guard age < maxAge else { return }

        let t = age / maxAge
        let sp = project(position, center: center, mpp: mpp, followOffset: followOffset)
        let r = CGFloat(10 + t * 30)
        let opacity = (1.0 - t) * 0.6

        let flashRect = CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: flashRect),
                     with: .color(Color.white.opacity(opacity)))
    }

    private func drawLaunchPreview(context: GraphicsContext, origin: CGPoint, current: CGPoint,
                                   worldOrigin: SIMD3<Double>, center: CGPoint, mpp: Double,
                                   followOffset: SIMD3<Double>) {
        let placementScreen = project(worldOrigin, center: center, mpp: mpp, followOffset: followOffset)
        let dotRect = CGRect(x: placementScreen.x - 5, y: placementScreen.y - 5, width: 10, height: 10)
        let rgb = launchState.objectColor
        context.fill(Path(ellipseIn: dotRect),
                     with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))

        let dx = origin.x - current.x
        let dy = origin.y - current.y
        let dragLen = hypot(dx, dy)
        if dragLen > 5 {
            let arrowEnd = CGPoint(x: placementScreen.x + dx, y: placementScreen.y + dy)
            var arrowPath = Path()
            arrowPath.move(to: placementScreen)
            arrowPath.addLine(to: arrowEnd)
            context.stroke(arrowPath, with: .color(.white.opacity(0.8)), lineWidth: 2)

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

            let launchVel = computeLaunchVelocity(origin: origin, current: current, center: center, mpp: mpp)
            let speed = simd_length(launchVel)
            let bound = simulation.wouldBeBound(position: worldOrigin, velocity: launchVel, mass: launchState.objectMass)
            let speedLabel = String(format: "%.1e m/s", speed)
            let orbitLabel = bound ? "Bound" : "Escape"
            let labelColor: Color = bound ? Color(red: 0.3, green: 0.8, blue: 0.4) : Color(red: 0.9, green: 0.3, blue: 0.2)

            let speedText = Text(speedLabel)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
            context.draw(context.resolve(speedText),
                         at: CGPoint(x: arrowEnd.x + 10, y: arrowEnd.y - 10), anchor: .leading)

            let orbitText = Text(orbitLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
            context.draw(context.resolve(orbitText),
                         at: CGPoint(x: arrowEnd.x + 10, y: arrowEnd.y + 2), anchor: .leading)
        }

        // Trajectory preview
        if launchState.trajectoryPreview.count > 1 {
            let launchVel = computeLaunchVelocity(origin: origin, current: current, center: center, mpp: mpp)
            let bound = simulation.wouldBeBound(position: worldOrigin, velocity: launchVel, mass: launchState.objectMass)
            let trajColor: Color = bound
                ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.4)
                : Color(red: 0.9, green: 0.3, blue: 0.2).opacity(0.4)

            var trajPath = Path()
            let firstPt = project(launchState.trajectoryPreview[0], center: center, mpp: mpp, followOffset: followOffset)
            trajPath.move(to: firstPt)
            for idx in 1..<launchState.trajectoryPreview.count {
                let pt = project(launchState.trajectoryPreview[idx], center: center, mpp: mpp, followOffset: followOffset)
                trajPath.addLine(to: pt)
            }
            context.stroke(trajPath,
                           with: .color(trajColor),
                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    // MARK: - Controls

    private var timeControls: some View {
        HStack(spacing: 14) {
            Button(action: { simulation.togglePause() }) {
                Image(systemName: simulation.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Speed")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                Slider(value: $simulation.timeScale, in: 100_000...10_000_000)
                    .frame(width: 140)
            }

            Text(simulation.elapsedTimeString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            Divider().frame(height: 20).background(Color.white.opacity(0.15))

            // Toggle buttons
            toggleButton(icon: "textformat", isOn: showLabels) { showLabels.toggle() }
            toggleButton(icon: "arrow.up.right", isOn: showForceVectors) { showForceVectors.toggle() }
            toggleButton(icon: "circle.dashed", isOn: showOrbits) { showOrbits.toggle() }

            if followingBody != nil {
                Button(action: { followingBody = nil }) {
                    Text("Unfollow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 20).background(Color.white.opacity(0.15))

            Button(action: {
                simulation.resetSimulation()
                launchState.deactivate()
                followingBody = nil
                if let sel = selectedPlanet, sel >= simulation.bodies.count {
                    selectedPlanet = nil
                }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.118, green: 0.106, blue: 0.090).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 12)
    }

    private func toggleButton(icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isOn ? Color(red: 0.30, green: 0.50, blue: 0.90) : .white.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private var statsOverlay: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(simulation.bodies.count) bodies")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(10)
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
    var onKeyPress: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> InputNSView {
        let view = InputNSView()
        view.onScroll = onScroll
        view.onDrag = onDrag
        view.onClick = onClick
        view.onDragStart = onDragStart
        view.onDragMove = onDragMove
        view.onDragEnd = onDragEnd
        view.onKeyPress = onKeyPress
        return view
    }

    func updateNSView(_ nsView: InputNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDrag = onDrag
        nsView.onClick = onClick
        nsView.onDragStart = onDragStart
        nsView.onDragMove = onDragMove
        nsView.onDragEnd = onDragEnd
        nsView.onKeyPress = onKeyPress
    }
}

class InputNSView: NSView {
    var onScroll: ((Double) -> Void)?
    var onDrag: ((Double, Double) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?
    var onKeyPress: ((String) -> Void)?

    private var isDragging = false
    private var dragStartedAbsolute = false
    private var lastDragPoint: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Double(event.scrollingDeltaY))
    }

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers {
            onKeyPress?(chars)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
            let startViewPoint = convert(lastDragPoint, from: nil)
            let startFlipped = CGPoint(x: startViewPoint.x, y: bounds.height - startViewPoint.y)
            onDragStart?(startFlipped)
            dragStartedAbsolute = true
        }

        let dx = Double(current.x - lastDragPoint.x)
        let dy = Double(current.y - lastDragPoint.y)
        lastDragPoint = current
        onDrag?(dx, -dy)

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
