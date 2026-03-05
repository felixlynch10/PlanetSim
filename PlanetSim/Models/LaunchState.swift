import Foundation
import SwiftUI
import simd

enum LaunchPhase {
    case inactive
    case ready
    case aiming(origin: CGPoint, current: CGPoint, worldOrigin: SIMD3<Double>)
}

enum WormholePlacementPhase: Equatable {
    case none
    case placingFirst
    case placingSecond(firstId: UUID, firstName: String)
}

@MainActor
final class LaunchState: ObservableObject {
    @Published var phase: LaunchPhase = .inactive
    @Published var objectName: String = "Asteroid 1"
    @Published var objectMass: Double = 1e22
    @Published var objectDisplayRadius: CGFloat = 3.0
    @Published var objectColor: PlanetColor = PlanetColor(r: 0.9, g: 0.9, b: 0.9)
    @Published var trajectoryPreview: [SIMD3<Double>] = []
    @Published var objectType: BodyType = .normal
    @Published var objectThroatRadius: Double = 5e9
    @Published var wormholePlacementPhase: WormholePlacementPhase = .none

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
        if objectType == .wormhole {
            wormholePlacementPhase = .placingFirst
        }
        phase = .ready
    }

    func deactivate() {
        phase = .inactive
        trajectoryPreview = []
        wormholePlacementPhase = .none
    }

    func beginAiming(origin: CGPoint, worldOrigin: SIMD3<Double>) {
        phase = .aiming(origin: origin, current: origin, worldOrigin: worldOrigin)
    }

    func updateAim(current: CGPoint) {
        if case .aiming(let origin, _, let worldOrigin) = phase {
            phase = .aiming(origin: origin, current: current, worldOrigin: worldOrigin)
        }
    }

    func completeLaunch(placedBodyId: UUID? = nil) {
        if objectType == .wormhole {
            if case .placingFirst = wormholePlacementPhase, let bodyId = placedBodyId {
                let firstName = objectName
                wormholePlacementPhase = .placingSecond(firstId: bodyId, firstName: firstName)
                objectName = "\(firstName) Exit"
                phase = .ready
                trajectoryPreview = []
                return
            } else if case .placingSecond = wormholePlacementPhase {
                wormholePlacementPhase = .none
            }
        }

        launchCounter += 1
        objectName = "Asteroid \(launchCounter)"
        objectType = .normal
        wormholePlacementPhase = .none
        phase = .inactive
        trajectoryPreview = []
        applyTypeDefaults()
    }

    func applyTypeDefaults() {
        switch objectType {
        case .normal:
            objectMass = 1e22
            objectDisplayRadius = 3.0
            objectColor = PlanetColor(r: 0.9, g: 0.9, b: 0.9)
            launchCounter += 1
            objectName = "Asteroid \(launchCounter)"
        case .blackHole:
            objectMass = 1e35
            objectDisplayRadius = 6.0
            objectColor = PlanetColor(r: 0.4, g: 0.1, b: 0.5)
            objectName = "Black Hole"
        case .neutronStar:
            objectMass = 3e30
            objectDisplayRadius = 2.0
            objectColor = PlanetColor(r: 0.7, g: 0.85, b: 1.0)
            objectName = "Neutron Star"
        case .wormhole:
            objectMass = 1e20
            objectDisplayRadius = 4.0
            objectColor = PlanetColor(r: 0.3, g: 0.5, b: 1.0)
            objectName = "Wormhole Entry"
        }
    }
}
