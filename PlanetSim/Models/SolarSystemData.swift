import Foundation
import simd

struct SolarSystemData {

    static let G: Double = 6.67430e-11
    static let AU: Double = 1.496e11

    /// Place a planet on an inclined elliptical orbit at a given true anomaly.
    /// Returns (position, velocity) in 3D.
    private static func orbitalState(
        starMass: Double, a: Double, e: Double,
        inc: Double, node: Double, trueAnomaly: Double
    ) -> (SIMD3<Double>, SIMD3<Double>) {
        // Distance at this true anomaly
        let r = a * (1 - e * e) / (1 + e * cos(trueAnomaly))

        // Position and velocity in the orbital plane (2D)
        let posX = r * cos(trueAnomaly)
        let posY = r * sin(trueAnomaly)

        let mu = G * starMass
        let p = a * (1 - e * e)
        let h = sqrt(mu * p)

        let velX = -mu / h * sin(trueAnomaly)
        let velY = mu / h * (e + cos(trueAnomaly))

        // Rotate by longitude of ascending node (around Z)
        // Then tilt by inclination (around X)
        func rotate(x: Double, y: Double, z: Double) -> SIMD3<Double> {
            // Rotate around Z by node angle
            let cosN = cos(node)
            let sinN = sin(node)
            let x1 = x * cosN - y * sinN
            let y1 = x * sinN + y * cosN
            let z1 = z

            // Rotate around X by inclination
            let cosI = cos(inc)
            let sinI = sin(inc)
            let y2 = y1 * cosI - z1 * sinI
            let z2 = y1 * sinI + z1 * cosI

            return SIMD3<Double>(x1, y2, z2)
        }

        let pos = rotate(x: posX, y: posY, z: 0)
        let vel = rotate(x: velX, y: velY, z: 0)

        return (pos, vel)
    }

    static func createSolarSystem() -> [CelestialBody] {
        let starMass = 2.0e30

        let star = CelestialBody(
            id: UUID(), name: "Solara", mass: starMass,
            displayRadius: 16,
            position: SIMD3<Double>(0, 0, 0),
            velocity: SIMD3<Double>(0, 0, 0),
            color: PlanetColor(r: 0.831, g: 0.678, b: 0.169),
            semiMajorAxis: 0, eccentricity: 0,
            inclination: 0, longitudeOfNode: 0
        )

        // Planet 1: Ashara — warm grey, slight eccentricity, small inclination
        let (pos1, vel1) = orbitalState(
            starMass: starMass, a: 0.32 * AU, e: 0.12,
            inc: 0.08, node: 0.4, trueAnomaly: .pi * 1.55
        )
        let p1 = CelestialBody(
            id: UUID(), name: "Ashara", mass: 4.2e23,
            displayRadius: 5, position: pos1, velocity: vel1,
            color: PlanetColor(r: 0.690, g: 0.659, b: 0.596),
            semiMajorAxis: 0.32 * AU, eccentricity: 0.12,
            inclination: 0.08, longitudeOfNode: 0.4
        )

        // Planet 2: Pyralis — golden, moderate eccentricity, different inclination
        let (pos2, vel2) = orbitalState(
            starMass: starMass, a: 0.50 * AU, e: 0.18,
            inc: -0.12, node: 1.8, trueAnomaly: .pi * 0.62
        )
        let p2 = CelestialBody(
            id: UUID(), name: "Pyralis", mass: 5.8e24,
            displayRadius: 5, position: pos2, velocity: vel2,
            color: PlanetColor(r: 0.784, g: 0.643, b: 0.196),
            semiMajorAxis: 0.50 * AU, eccentricity: 0.18,
            inclination: -0.12, longitudeOfNode: 1.8
        )

        // Planet 3: Cerulea — blue, low eccentricity, steeper inclination
        let (pos3, vel3) = orbitalState(
            starMass: starMass, a: 0.78 * AU, e: 0.06,
            inc: 0.20, node: 3.5, trueAnomaly: .pi * 1.12
        )
        let p3 = CelestialBody(
            id: UUID(), name: "Cerulea", mass: 6.5e24,
            displayRadius: 6, position: pos3, velocity: vel3,
            color: PlanetColor(r: 0.420, g: 0.502, b: 0.769),
            semiMajorAxis: 0.78 * AU, eccentricity: 0.06,
            inclination: 0.20, longitudeOfNode: 3.5
        )

        // Planet 4: Embera — red, notable eccentricity, negative inclination
        let (pos4, vel4) = orbitalState(
            starMass: starMass, a: 1.15 * AU, e: 0.22,
            inc: -0.15, node: 5.2, trueAnomaly: .pi * 0.02
        )
        let p4 = CelestialBody(
            id: UUID(), name: "Embera", mass: 8.0e24,
            displayRadius: 7, position: pos4, velocity: vel4,
            color: PlanetColor(r: 0.800, g: 0.290, b: 0.165),
            semiMajorAxis: 1.15 * AU, eccentricity: 0.22,
            inclination: -0.15, longitudeOfNode: 5.2
        )

        // Planet 5: Auricos — golden outer, moderate eccentricity
        let (pos5, vel5) = orbitalState(
            starMass: starMass, a: 1.95 * AU, e: 0.14,
            inc: 0.10, node: 2.3, trueAnomaly: .pi * 1.72
        )
        let p5 = CelestialBody(
            id: UUID(), name: "Auricos", mass: 2.5e26,
            displayRadius: 6, position: pos5, velocity: vel5,
            color: PlanetColor(r: 0.784, g: 0.643, b: 0.196),
            semiMajorAxis: 1.95 * AU, eccentricity: 0.14,
            inclination: 0.10, longitudeOfNode: 2.3
        )

        // Planet 6: Thalassa — teal, high inclination for dramatic tilt
        let (pos6, vel6) = orbitalState(
            starMass: starMass, a: 3.0 * AU, e: 0.10,
            inc: -0.25, node: 4.0, trueAnomaly: .pi * 0.85
        )
        let p6 = CelestialBody(
            id: UUID(), name: "Thalassa", mass: 1.2e26,
            displayRadius: 5, position: pos6, velocity: vel6,
            color: PlanetColor(r: 0.235, g: 0.769, b: 0.706),
            semiMajorAxis: 3.0 * AU, eccentricity: 0.10,
            inclination: -0.25, longitudeOfNode: 4.0
        )

        return [star, p1, p2, p3, p4, p5, p6]
    }
}
