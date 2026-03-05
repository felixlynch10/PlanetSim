import Foundation
import simd
import Combine

@MainActor
final class GravitySimulation: ObservableObject {

    @Published var bodies: [CelestialBody]
    @Published var simulationTime: Date
    @Published var isRunning: Bool = true
    @Published var timeScale: Double = 1_000_000

    private let G = SolarSystemData.G
    private let c: Double = 299_792_458.0
    private let maxTrailLength = 800
    private var trailCounter = 0
    private let trailInterval = 2

    @Published var trailPoints3D: [[SIMD3<Double>]] = []

    private var startDate: Date

    struct CollisionEvent {
        let position: SIMD3<Double>
        let time: Date
    }
    @Published var recentCollisions: [CollisionEvent] = []

    init() {
        let now = Date()
        self.bodies = SolarSystemData.createSolarSystem()
        self.simulationTime = now
        self.startDate = now
        self.trailPoints3D = Array(repeating: [], count: bodies.count)
    }

    // MARK: - Elapsed Time

    var elapsedSeconds: Double {
        simulationTime.timeIntervalSince(startDate)
    }

    var elapsedTimeString: String {
        let totalDays = elapsedSeconds / 86400.0
        if totalDays < 1 {
            let hours = Int(elapsedSeconds / 3600)
            return "\(hours)h"
        }
        let years = Int(totalDays / 365.25)
        let days = Int(totalDays.truncatingRemainder(dividingBy: 365.25))
        if years > 0 {
            return "Year \(years), Day \(days)"
        }
        return "Day \(Int(totalDays))"
    }

    // MARK: - Physics Step

    func step(dt: Double) {
        guard isRunning else { return }

        let physicsDt = dt * timeScale

        let minDist = minimumPairwiseDistance()
        let maxMass = bodies.max(by: { $0.mass < $1.mass })?.mass ?? 1e30
        let orbitalTime = sqrt(minDist * minDist * minDist / (G * maxMass))
        let safeStep = max(60.0, 0.01 * orbitalTime)
        let subSteps = max(1, min(2000, Int(ceil(physicsDt / safeStep))))
        let subDt = physicsDt / Double(subSteps)

        for _ in 0..<subSteps {
            velocityVerletStep(dt: subDt)
        }

        simulationTime = simulationTime.addingTimeInterval(physicsDt)
        recordTrails()
        detectCollisions()
        cleanupCollisions()
    }

    private func minimumPairwiseDistance() -> Double {
        var minDist = Double.infinity
        let n = bodies.count
        for i in 0..<n {
            for j in (i+1)..<n {
                let d = simd_length(bodies[j].position - bodies[i].position)
                if d < minDist { minDist = d }
            }
        }
        return minDist
    }

    private func recordTrails() {
        trailCounter += 1
        if trailCounter >= trailInterval {
            trailCounter = 0
            // Ensure arrays are in sync
            while trailPoints3D.count < bodies.count { trailPoints3D.append([]) }
            while trailPoints3D.count > bodies.count { trailPoints3D.removeLast() }
            for i in 0..<bodies.count {
                trailPoints3D[i].append(bodies[i].position)
                if trailPoints3D[i].count > maxTrailLength {
                    trailPoints3D[i].removeFirst()
                }
            }
        }
    }

    private func velocityVerletStep(dt: Double) {
        let n = bodies.count
        var accelerations = computeAccelerations()
        computePostNewtonianCorrections(acc: &accelerations)

        let halfDtSq = 0.5 * dt * dt
        for i in 0..<n {
            let velTerm = bodies[i].velocity * dt
            let accTerm = accelerations[i] * halfDtSq
            bodies[i].position += velTerm + accTerm
        }

        // Process event horizons and wormholes (deferred removal)
        let removedIndices = processEventHorizons()
        processWormholeTransits(dt: dt)
        applyDeferredRemovals(removedIndices)

        var newAccelerations = computeAccelerations()
        computePostNewtonianCorrections(acc: &newAccelerations)

        let halfDt = 0.5 * dt
        for i in 0..<n where i < bodies.count {
            let oldAcc = i < accelerations.count ? accelerations[i] : .zero
            let newAcc = i < newAccelerations.count ? newAccelerations[i] : .zero
            let avgAcc = oldAcc + newAcc
            bodies[i].velocity += avgAcc * halfDt
        }
    }

    func computeAccelerations() -> [SIMD3<Double>] {
        let n = bodies.count
        var acc = Array(repeating: SIMD3<Double>(0, 0, 0), count: n)
        let defaultSoftening: Double = 1e12
        let bhSoftening: Double = 1e6

        for i in 0..<n {
            for j in (i+1)..<n {
                let rij = bodies[j].position - bodies[i].position
                let distSq = simd_length_squared(rij)

                // Use reduced softening for black hole pairs
                let softening: Double
                if bodies[i].bodyType == .blackHole || bodies[j].bodyType == .blackHole {
                    softening = bhSoftening
                } else {
                    softening = defaultSoftening
                }

                let dist = sqrt(distSq + softening)
                let invDist3 = G / (dist * dist * dist)

                let massJ = bodies[j].mass
                let massI = bodies[i].mass

                acc[i] += (invDist3 * massJ) * rij
                acc[j] -= (invDist3 * massI) * rij
            }
        }

        return acc
    }

    // MARK: - Post-Newtonian Corrections (EIH 1PN)

    private func computePostNewtonianCorrections(acc: inout [SIMD3<Double>]) {
        let n = bodies.count
        let c2 = c * c

        for i in 0..<n {
            for j in 0..<n where j != i {
                // Only apply from compact objects
                guard bodies[j].bodyType == .blackHole || bodies[j].bodyType == .neutronStar else { continue }

                let rij = bodies[j].position - bodies[i].position
                let dist = simd_length(rij)
                guard dist > 0 else { continue }

                let nHat = rij / dist
                let vi = bodies[i].velocity
                let vj = bodies[j].velocity
                let mi = bodies[i].mass
                let mj = bodies[j].mass
                let r = dist
                let r2 = r * r

                let vi2 = simd_length_squared(vi)
                let vj2 = simd_length_squared(vj)
                let viDotVj = simd_dot(vi, vj)
                let nDotVj = simd_dot(nHat, vj)

                // Scalar correction multiplied by n̂
                let scalarTerm = (vi2 + 2.0 * vj2 - 4.0 * viDotVj
                    - 1.5 * nDotVj * nDotVj
                    - 5.0 * G * mi / r
                    - 4.0 * G * mj / r) / c2

                // Velocity-dependent vector term
                let velFactor = simd_dot(nHat, 4.0 * vi - 3.0 * vj) / c2

                let baseMag = G * mj / r2
                let correction = baseMag * scalarTerm * nHat + baseMag * velFactor * (vi - vj)

                acc[i] += correction
            }
        }
    }

    // MARK: - Event Horizon Absorption

    private func processEventHorizons() -> Set<Int> {
        let n = bodies.count
        var toRemove = Set<Int>()

        for i in 0..<n {
            guard bodies[i].bodyType == .blackHole else { continue }
            let captureRadius = max(bodies[i].schwarzschildRadius, 1e9)

            for j in 0..<n where j != i {
                if toRemove.contains(j) { continue }
                if bodies[j].bodyType == .blackHole && bodies[j].mass > bodies[i].mass { continue }

                let dist = simd_length(bodies[j].position - bodies[i].position)
                if dist < captureRadius {
                    // Absorb: add mass to BH, conserve momentum
                    let totalMass = bodies[i].mass + bodies[j].mass
                    bodies[i].velocity = (bodies[i].velocity * bodies[i].mass + bodies[j].velocity * bodies[j].mass) / totalMass
                    bodies[i].mass = totalMass

                    recentCollisions.append(CollisionEvent(position: bodies[j].position, time: simulationTime))

                    // If absorbed body was a wormhole, orphan its partner
                    if bodies[j].bodyType == .wormhole, let linkedId = bodies[j].linkedWormholeId {
                        if let partnerIdx = bodies.firstIndex(where: { $0.id == linkedId }) {
                            bodies[partnerIdx].bodyType = .normal
                            bodies[partnerIdx].linkedWormholeId = nil
                        }
                    }

                    toRemove.insert(j)
                }
            }
        }

        return toRemove
    }

    // MARK: - Wormhole Transit

    private func processWormholeTransits(dt: Double) {
        let n = bodies.count

        // Decrement cooldowns
        for i in 0..<n {
            if bodies[i].wormholeCooldown > 0 {
                bodies[i].wormholeCooldown -= abs(dt)
                if bodies[i].wormholeCooldown < 0 { bodies[i].wormholeCooldown = 0 }
            }
        }

        for i in 0..<n {
            guard bodies[i].bodyType == .wormhole,
                  let linkedId = bodies[i].linkedWormholeId,
                  let exitIdx = bodies.firstIndex(where: { $0.id == linkedId })
            else { continue }

            let throatR = bodies[i].throatRadius

            for j in 0..<n {
                if j == i || j == exitIdx { continue }
                if bodies[j].bodyType == .wormhole { continue }
                if bodies[j].wormholeCooldown > 0 { continue }

                let dist = simd_length(bodies[j].position - bodies[i].position)
                if dist < throatR {
                    // Teleport: preserve velocity, offset from exit
                    let offset = bodies[j].position - bodies[i].position
                    bodies[j].position = bodies[exitIdx].position + offset
                    bodies[j].wormholeCooldown = 5.0 * timeScale // 5 sim-seconds worth

                    // Insert NaN trail marker for visual gap
                    if let trailIdx = bodies.firstIndex(where: { $0.id == bodies[j].id }) {
                        if trailIdx < trailPoints3D.count {
                            let nan = SIMD3<Double>(Double.nan, Double.nan, Double.nan)
                            trailPoints3D[trailIdx].append(nan)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Deferred Removal

    private func applyDeferredRemovals(_ indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        let sorted = indices.sorted(by: >)
        for idx in sorted {
            guard idx < bodies.count else { continue }
            bodies.remove(at: idx)
            if idx < trailPoints3D.count {
                trailPoints3D.remove(at: idx)
            }
        }
    }

    // MARK: - Collision Detection

    private func detectCollisions() {
        let n = bodies.count
        guard n > 1 else { return }

        let collisionScale: Double = 5e8

        var toRemove: Set<Int> = []
        var i = 0
        while i < bodies.count {
            if toRemove.contains(i) { i += 1; continue }
            var j = i + 1
            while j < bodies.count {
                if toRemove.contains(j) { j += 1; continue }
                let dist = simd_length(bodies[j].position - bodies[i].position)
                let threshold = (Double(bodies[i].displayRadius) + Double(bodies[j].displayRadius)) * collisionScale
                if dist < threshold {
                    let (keepIdx, removeIdx) = bodies[i].mass >= bodies[j].mass ? (i, j) : (j, i)
                    let keep = bodies[keepIdx]
                    let remove = bodies[removeIdx]

                    let totalMass = keep.mass + remove.mass
                    let newVel = (keep.velocity * keep.mass + remove.velocity * remove.mass) / totalMass
                    let newPos = (keep.position * keep.mass + remove.position * remove.mass) / totalMass

                    let rK = Double(keep.displayRadius)
                    let rR = Double(remove.displayRadius)
                    let newRadius = CGFloat(pow(rK * rK * rK + rR * rR * rR, 1.0 / 3.0))

                    bodies[keepIdx].mass = totalMass
                    bodies[keepIdx].velocity = newVel
                    bodies[keepIdx].position = newPos
                    bodies[keepIdx].displayRadius = newRadius

                    recentCollisions.append(CollisionEvent(position: newPos, time: simulationTime))
                    toRemove.insert(removeIdx)
                }
                j += 1
            }
            i += 1
        }

        if !toRemove.isEmpty {
            let sorted = toRemove.sorted(by: >)
            for idx in sorted {
                bodies.remove(at: idx)
                trailPoints3D.remove(at: idx)
            }
        }
    }

    private func cleanupCollisions() {
        let cutoff = simulationTime.addingTimeInterval(-2)
        recentCollisions.removeAll { $0.time < cutoff }
    }

    // MARK: - Energy & Orbit Analysis

    func kineticEnergy(index: Int) -> Double {
        let v = simd_length(bodies[index].velocity)
        return 0.5 * bodies[index].mass * v * v
    }

    func potentialEnergy(index: Int) -> Double {
        var pe: Double = 0
        for j in 0..<bodies.count where j != index {
            let r = simd_length(bodies[j].position - bodies[index].position)
            if r > 0 {
                pe -= G * bodies[index].mass * bodies[j].mass / r
            }
        }
        return pe
    }

    func totalEnergy(index: Int) -> Double {
        kineticEnergy(index: index) + potentialEnergy(index: index)
    }

    func isEscaping(index: Int) -> Bool {
        totalEnergy(index: index) >= 0
    }

    func orbitalPeriod(index: Int) -> Double? {
        guard index > 0, index < bodies.count else { return nil }
        let dominantIdx = bodies.indices.filter { $0 != index }.max(by: { bodies[$0].mass < bodies[$1].mass })
        guard let dIdx = dominantIdx else { return nil }

        let relPos = bodies[index].position - bodies[dIdx].position
        let relVel = bodies[index].velocity - bodies[dIdx].velocity
        let r = simd_length(relPos)
        let v = simd_length(relVel)
        let mu = G * (bodies[index].mass + bodies[dIdx].mass)

        let oneOverA = 2.0 / r - v * v / mu
        guard oneOverA > 0 else { return nil }
        let a = 1.0 / oneOverA

        return 2.0 * .pi * sqrt(a * a * a / mu)
    }

    func orbitalPeriodString(index: Int) -> String? {
        guard let period = orbitalPeriod(index: index) else { return nil }
        let days = period / 86400.0
        if days > 365.25 {
            return String(format: "%.1f years", days / 365.25)
        }
        return String(format: "%.0f days", days)
    }

    // MARK: - Predicted Orbit Path

    func predictOrbitPoints(index: Int, segments: Int = 120) -> [SIMD3<Double>]? {
        guard index > 0, index < bodies.count else { return nil }
        let dominantIdx = bodies.indices.filter { $0 != index }.max(by: { bodies[$0].mass < bodies[$1].mass })
        guard let dIdx = dominantIdx else { return nil }

        let relPos = bodies[index].position - bodies[dIdx].position
        let relVel = bodies[index].velocity - bodies[dIdx].velocity
        let r = simd_length(relPos)
        let v = simd_length(relVel)
        let mu = G * (bodies[index].mass + bodies[dIdx].mass)

        let oneOverA = 2.0 / r - v * v / mu
        guard oneOverA > 0 else { return nil }
        let a = 1.0 / oneOverA

        let h = simd_cross(relPos, relVel)
        let hMag = simd_length(h)
        guard hMag > 0 else { return nil }

        let eVec = simd_cross(relVel, h) / mu - simd_normalize(relPos)
        let e = simd_length(eVec)
        guard e < 1.0 else { return nil }

        let xAxis: SIMD3<Double>
        if e > 1e-8 {
            xAxis = simd_normalize(eVec)
        } else {
            xAxis = simd_normalize(relPos)
        }
        let zAxis = simd_normalize(h)
        let yAxis = simd_cross(zAxis, xAxis)

        let p = a * (1.0 - e * e)
        var points: [SIMD3<Double>] = []
        let starPos = bodies[dIdx].position

        for i in 0...segments {
            let theta = Double(i) / Double(segments) * 2.0 * .pi
            let radius = p / (1.0 + e * cos(theta))
            let localX = radius * cos(theta)
            let localY = radius * sin(theta)
            let worldPos = starPos + xAxis * localX + yAxis * localY
            points.append(worldPos)
        }

        return points
    }

    // MARK: - System Totals

    var totalSystemEnergy: Double {
        var total: Double = 0
        for i in 0..<bodies.count {
            let v = simd_length(bodies[i].velocity)
            total += 0.5 * bodies[i].mass * v * v
        }
        for i in 0..<bodies.count {
            for j in (i+1)..<bodies.count {
                let r = simd_length(bodies[j].position - bodies[i].position)
                if r > 0 {
                    total -= G * bodies[i].mass * bodies[j].mass / r
                }
            }
        }
        return total
    }

    // MARK: - Add / Reset / Load

    func addBody(_ body: CelestialBody) {
        bodies.append(body)
        trailPoints3D.append([])
    }

    func computeTrajectoryPreview(newBody: CelestialBody, steps: Int = 300, stepDt: Double = 86400) -> [SIMD3<Double>] {
        var simBodies = bodies.map { (position: $0.position, velocity: $0.velocity, mass: $0.mass) }
        simBodies.append((position: newBody.position, velocity: newBody.velocity, mass: newBody.mass))

        let n = simBodies.count
        let newIdx = n - 1
        let softening: Double = 1e12
        var positions: [SIMD3<Double>] = [newBody.position]

        let subSteps = 8
        let subDt = stepDt / Double(subSteps)

        func computeAccel() -> [SIMD3<Double>] {
            var acc = Array(repeating: SIMD3<Double>(0, 0, 0), count: n)
            for i in 0..<n {
                for j in (i+1)..<n {
                    let rij = simBodies[j].position - simBodies[i].position
                    let distSq = simd_length_squared(rij)
                    let dist = sqrt(distSq + softening)
                    let invDist3 = G / (dist * dist * dist)
                    acc[i] += (invDist3 * simBodies[j].mass) * rij
                    acc[j] -= (invDist3 * simBodies[i].mass) * rij
                }
            }
            return acc
        }

        for _ in 0..<steps {
            for _ in 0..<subSteps {
                let acc = computeAccel()
                let halfDtSq = 0.5 * subDt * subDt
                for i in 0..<n {
                    let velStep = simBodies[i].velocity * subDt
                    let accStep = acc[i] * halfDtSq
                    simBodies[i].position += velStep + accStep
                }
                let newAcc = computeAccel()
                let halfDt = 0.5 * subDt
                for i in 0..<n {
                    let avgAcc = acc[i] + newAcc[i]
                    simBodies[i].velocity += avgAcc * halfDt
                }
            }
            positions.append(simBodies[newIdx].position)
        }

        return positions
    }

    func wouldBeBound(position: SIMD3<Double>, velocity: SIMD3<Double>, mass: Double) -> Bool {
        let v = simd_length(velocity)
        let ke = 0.5 * mass * v * v
        var pe: Double = 0
        for body in bodies {
            let r = simd_length(body.position - position)
            if r > 0 {
                pe -= G * mass * body.mass / r
            }
        }
        return (ke + pe) < 0
    }

    func togglePause() {
        isRunning.toggle()
    }

    func resetSimulation() {
        loadBodies(SolarSystemData.createSolarSystem())
    }

    func loadBodies(_ newBodies: [CelestialBody]) {
        bodies = newBodies
        simulationTime = Date()
        startDate = simulationTime
        trailPoints3D = Array(repeating: [], count: bodies.count)
        recentCollisions = []
    }
}
