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
    private let maxTrailLength = 800
    private var trailCounter = 0
    private let trailInterval = 2

    // Store 3D trail points for proper projection
    @Published var trailPoints3D: [[SIMD3<Double>]] = []

    init() {
        self.bodies = SolarSystemData.createSolarSystem()
        self.simulationTime = Date()
        self.trailPoints3D = Array(repeating: [], count: bodies.count)
    }

    func step(dt: Double) {
        guard isRunning else { return }

        let physicsDt = dt * timeScale

        // Adaptive substeps: use closest pair distance to pick a safe time step.
        // Orbital timescale at distance r from mass M: T ~ sqrt(r^3 / (G*M))
        // Safe step = 1% of that, so close encounters get tiny steps automatically.
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
        let accelerations = computeAccelerations()
        let halfDtSq = 0.5 * dt * dt

        for i in 0..<n {
            let velTerm = bodies[i].velocity * dt
            let accTerm = accelerations[i] * halfDtSq
            bodies[i].position += velTerm + accTerm
        }

        let newAccelerations = computeAccelerations()

        let halfDt = 0.5 * dt
        for i in 0..<n {
            let avgAcc = accelerations[i] + newAccelerations[i]
            bodies[i].velocity += avgAcc * halfDt
        }
    }

    private func computeAccelerations() -> [SIMD3<Double>] {
        let n = bodies.count
        var acc = Array(repeating: SIMD3<Double>(0, 0, 0), count: n)
        let softening: Double = 1e12

        for i in 0..<n {
            for j in (i+1)..<n {
                let rij = bodies[j].position - bodies[i].position
                let distSq = simd_length_squared(rij)
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

        // Use Velocity Verlet with substeps for accuracy
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

    func togglePause() {
        isRunning.toggle()
    }

    func resetSimulation() {
        bodies = SolarSystemData.createSolarSystem()
        simulationTime = Date()
        trailPoints3D = Array(repeating: [], count: bodies.count)
    }
}
