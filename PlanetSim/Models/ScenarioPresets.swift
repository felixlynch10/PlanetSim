import Foundation
import simd

struct ScenarioPresets {

    static let all: [(name: String, description: String, builder: () -> [CelestialBody])] = [
        ("Default", "6 planets orbiting Solara", { SolarSystemData.createSolarSystem() }),
        ("Binary Stars", "Two stars with shared planets", buildBinaryStars),
        ("Heavy Giant", "One planet at 100x mass", buildHeavyGiant),
        ("Rogue Flyby", "A massive intruder on a hyperbolic path", buildRogueFlyby),
        ("Inner System", "3 close planets for detailed observation", buildInnerSystem),
        ("Chaos", "12 equal-mass bodies in unstable orbits", buildChaos),
    ]

    private static func buildBinaryStars() -> [CelestialBody] {
        let AU = SolarSystemData.AU
        let G = SolarSystemData.G

        let m1 = 2.0e30
        let m2 = 1.5e30
        let sep = 0.15 * AU
        let mu = G * (m1 + m2)
        let orbVel = sqrt(mu / sep)

        let star1 = CelestialBody(
            id: UUID(), name: "Solara A", mass: m1, displayRadius: 14,
            position: SIMD3<Double>(-sep * m2 / (m1 + m2), 0, 0),
            velocity: SIMD3<Double>(0, -orbVel * m2 / (m1 + m2), 0),
            color: PlanetColor(r: 0.831, g: 0.678, b: 0.169),
            semiMajorAxis: 0, eccentricity: 0, inclination: 0, longitudeOfNode: 0
        )
        let star2 = CelestialBody(
            id: UUID(), name: "Solara B", mass: m2, displayRadius: 12,
            position: SIMD3<Double>(sep * m1 / (m1 + m2), 0, 0),
            velocity: SIMD3<Double>(0, orbVel * m1 / (m1 + m2), 0),
            color: PlanetColor(r: 0.9, g: 0.45, b: 0.2),
            semiMajorAxis: 0, eccentricity: 0, inclination: 0, longitudeOfNode: 0
        )

        let totalMass = m1 + m2
        func circularPlanet(name: String, mass: Double, radius: CGFloat, dist: Double, color: PlanetColor, angle: Double) -> CelestialBody {
            let v = sqrt(G * totalMass / dist)
            return CelestialBody(
                id: UUID(), name: name, mass: mass, displayRadius: radius,
                position: SIMD3<Double>(dist * cos(angle), dist * sin(angle), 0),
                velocity: SIMD3<Double>(-v * sin(angle), v * cos(angle), 0),
                color: color,
                semiMajorAxis: dist, eccentricity: 0, inclination: 0, longitudeOfNode: 0
            )
        }

        return [
            star1, star2,
            circularPlanet(name: "Vesta", mass: 5e24, radius: 5, dist: 0.6 * AU,
                          color: PlanetColor(r: 0.420, g: 0.502, b: 0.769), angle: 0.3),
            circularPlanet(name: "Krios", mass: 8e24, radius: 6, dist: 1.2 * AU,
                          color: PlanetColor(r: 0.800, g: 0.290, b: 0.165), angle: 2.1),
            circularPlanet(name: "Nyx", mass: 3e24, radius: 4, dist: 2.0 * AU,
                          color: PlanetColor(r: 0.235, g: 0.769, b: 0.706), angle: 4.5),
        ]
    }

    private static func buildHeavyGiant() -> [CelestialBody] {
        var bodies = SolarSystemData.createSolarSystem()
        // Make Auricos (index 5) 100x heavier
        if bodies.count > 5 {
            bodies[5].mass *= 100
            bodies[5].displayRadius = 12
            bodies[5].name = "Auricos Magnus"
        }
        return bodies
    }

    private static func buildRogueFlyby() -> [CelestialBody] {
        let AU = SolarSystemData.AU
        var bodies = SolarSystemData.createSolarSystem()
        let rogue = CelestialBody(
            id: UUID(), name: "Rogue", mass: 5e28, displayRadius: 9,
            position: SIMD3<Double>(5.0 * AU, -3.0 * AU, 0.2 * AU),
            velocity: SIMD3<Double>(-35000, 20000, 0),
            color: PlanetColor(r: 0.7, g: 0.3, b: 0.9),
            semiMajorAxis: 0, eccentricity: 0, inclination: 0, longitudeOfNode: 0
        )
        bodies.append(rogue)
        return bodies
    }

    private static func buildInnerSystem() -> [CelestialBody] {
        let AU = SolarSystemData.AU
        let G = SolarSystemData.G
        let starMass = 2.0e30

        let star = CelestialBody(
            id: UUID(), name: "Solara", mass: starMass, displayRadius: 16,
            position: .zero, velocity: .zero,
            color: PlanetColor(r: 0.831, g: 0.678, b: 0.169),
            semiMajorAxis: 0, eccentricity: 0, inclination: 0, longitudeOfNode: 0
        )

        func planet(name: String, mass: Double, radius: CGFloat, dist: Double, color: PlanetColor, angle: Double) -> CelestialBody {
            let v = sqrt(G * starMass / dist)
            return CelestialBody(
                id: UUID(), name: name, mass: mass, displayRadius: radius,
                position: SIMD3<Double>(dist * cos(angle), dist * sin(angle), 0),
                velocity: SIMD3<Double>(-v * sin(angle), v * cos(angle), 0),
                color: color,
                semiMajorAxis: dist, eccentricity: 0, inclination: 0, longitudeOfNode: 0
            )
        }

        return [
            star,
            planet(name: "Proxima", mass: 3.5e23, radius: 4, dist: 0.2 * AU,
                  color: PlanetColor(r: 0.690, g: 0.659, b: 0.596), angle: 0),
            planet(name: "Meridia", mass: 5.0e24, radius: 6, dist: 0.38 * AU,
                  color: PlanetColor(r: 0.420, g: 0.502, b: 0.769), angle: 2.2),
            planet(name: "Terranova", mass: 6.0e24, radius: 6, dist: 0.58 * AU,
                  color: PlanetColor(r: 0.3, g: 0.75, b: 0.45), angle: 4.0),
        ]
    }

    private static func buildChaos() -> [CelestialBody] {
        let AU = SolarSystemData.AU
        let G = SolarSystemData.G
        let starMass = 2.0e30

        let star = CelestialBody(
            id: UUID(), name: "Solara", mass: starMass, displayRadius: 16,
            position: .zero, velocity: .zero,
            color: PlanetColor(r: 0.831, g: 0.678, b: 0.169),
            semiMajorAxis: 0, eccentricity: 0, inclination: 0, longitudeOfNode: 0
        )

        let colors: [PlanetColor] = [
            PlanetColor(r: 0.9, g: 0.3, b: 0.2),
            PlanetColor(r: 0.9, g: 0.6, b: 0.2),
            PlanetColor(r: 0.3, g: 0.5, b: 0.9),
            PlanetColor(r: 0.3, g: 0.8, b: 0.4),
            PlanetColor(r: 0.7, g: 0.3, b: 0.9),
            PlanetColor(r: 0.235, g: 0.769, b: 0.706),
            PlanetColor(r: 0.690, g: 0.659, b: 0.596),
            PlanetColor(r: 0.784, g: 0.643, b: 0.196),
            PlanetColor(r: 0.800, g: 0.290, b: 0.165),
            PlanetColor(r: 0.420, g: 0.502, b: 0.769),
            PlanetColor(r: 0.9, g: 0.9, b: 0.9),
            PlanetColor(r: 0.6, g: 0.4, b: 0.3),
        ]

        var bodies: [CelestialBody] = [star]

        for i in 0..<12 {
            let angle = Double(i) * (2.0 * .pi / 12.0) + Double(i) * 0.15
            let dist = (0.4 + Double(i) * 0.22) * AU
            let v = sqrt(G * starMass / dist) * (0.85 + Double(i % 3) * 0.1)
            let body = CelestialBody(
                id: UUID(), name: "Body \(i + 1)", mass: 8e24, displayRadius: 5,
                position: SIMD3<Double>(dist * cos(angle), dist * sin(angle), 0),
                velocity: SIMD3<Double>(-v * sin(angle), v * cos(angle), 0),
                color: colors[i],
                semiMajorAxis: dist, eccentricity: 0, inclination: 0, longitudeOfNode: 0
            )
            bodies.append(body)
        }

        return bodies
    }
}
