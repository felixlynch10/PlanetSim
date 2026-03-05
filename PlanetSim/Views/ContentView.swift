import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = GravitySimulation()
    @StateObject private var launchState = LaunchState()
    @State private var selectedPlanet: Int? = nil
    @State private var followingBody: Int? = nil
    @AppStorage("showLabels") private var showLabels: Bool = true
    @AppStorage("showForceVectors") private var showForceVectors: Bool = false
    @AppStorage("showOrbits") private var showOrbits: Bool = false
    @State private var showOnboarding: Bool = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    private let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                simulation: simulation,
                selectedPlanet: $selectedPlanet,
                launchState: launchState,
                followingBody: $followingBody
            )

            ZStack {
                OrbitCanvasView(
                    simulation: simulation,
                    selectedPlanet: $selectedPlanet,
                    launchState: launchState,
                    followingBody: $followingBody,
                    showLabels: $showLabels,
                    showForceVectors: $showForceVectors,
                    showOrbits: $showOrbits
                )

                if showOnboarding {
                    OnboardingOverlay(onDismiss: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showOnboarding = false
                            hasSeenOnboarding = true
                        }
                    })
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.102, green: 0.090, blue: 0.078))
        .onReceive(timer) { _ in
            simulation.step(dt: 1.0/60.0)
            // Clean up follow/selection if body was removed
            if let f = followingBody, f >= simulation.bodies.count {
                followingBody = nil
            }
            if let s = selectedPlanet, s >= simulation.bodies.count {
                selectedPlanet = nil
            }
        }
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
    }
}
