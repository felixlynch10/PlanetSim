import Foundation
import simd

struct CelestialBody: Identifiable {
    let id: UUID
    var name: String
    var mass: Double
    var displayRadius: CGFloat
    var position: SIMD3<Double>
    var velocity: SIMD3<Double>
    var color: PlanetColor

    let semiMajorAxis: Double     // meters (initial orbit, for reference)
    let eccentricity: Double
    let inclination: Double
    let longitudeOfNode: Double

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
