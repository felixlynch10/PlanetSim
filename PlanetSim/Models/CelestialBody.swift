import Foundation
import simd

enum BodyType: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case blackHole = "Black Hole"
    case neutronStar = "Neutron Star"
    case wormhole = "Wormhole"

    var id: String { rawValue }
}

struct CelestialBody: Identifiable {
    let id: UUID
    var name: String
    var mass: Double
    var displayRadius: CGFloat
    var position: SIMD3<Double>
    var velocity: SIMD3<Double>
    var color: PlanetColor

    let semiMajorAxis: Double
    let eccentricity: Double
    let inclination: Double
    let longitudeOfNode: Double

    var bodyType: BodyType = .normal
    var linkedWormholeId: UUID? = nil
    var throatRadius: Double = 5e9
    var wormholeCooldown: Double = 0

    private static let c: Double = 299_792_458.0
    private static let G: Double = 6.67430e-11

    var schwarzschildRadius: Double {
        2.0 * CelestialBody.G * mass / (CelestialBody.c * CelestialBody.c)
    }

    var distanceFromOrigin: Double {
        simd_length(position)
    }

    var distanceMillionKm: Double {
        distanceFromOrigin / 1e9
    }
}

struct PlanetColor {
    let r: Double
    let g: Double
    let b: Double
}
