import Foundation
import SwiftUI
import simd

enum LaunchPhase {
    case inactive
    case ready
    case aiming(origin: CGPoint, current: CGPoint, worldOrigin: SIMD3<Double>)
}

@MainActor
final class LaunchState: ObservableObject {
    @Published var phase: LaunchPhase = .inactive
    @Published var objectName: String = "Asteroid 1"
    @Published var objectMass: Double = 1e22
    @Published var objectDisplayRadius: CGFloat = 3.0
    @Published var objectColor: PlanetColor = PlanetColor(r: 0.9, g: 0.9, b: 0.9)
    @Published var trajectoryPreview: [SIMD3<Double>] = []

    private var launchCounter: Int = 1

    var isActive: Bool {
        switch phase {
        case .inactive: return false
        default: return true
        }
    }

    var isAiming: Bool {
        switch phase {
        case .aiming: return true
        default: return false
        }
    }

    func activate() {
        phase = .ready
    }

    func deactivate() {
        phase = .inactive
        trajectoryPreview = []
    }

    func beginAiming(origin: CGPoint, worldOrigin: SIMD3<Double>) {
        phase = .aiming(origin: origin, current: origin, worldOrigin: worldOrigin)
    }

    func updateAim(current: CGPoint) {
        if case .aiming(let origin, _, let worldOrigin) = phase {
            phase = .aiming(origin: origin, current: current, worldOrigin: worldOrigin)
        }
    }

    func completeLaunch() {
        launchCounter += 1
        objectName = "Asteroid \(launchCounter)"
        phase = .inactive
        trajectoryPreview = []
    }

}
