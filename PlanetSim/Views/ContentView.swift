import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = GravitySimulation()
    @StateObject private var launchState = LaunchState()
    @State private var selectedPlanet: Int? = nil

    // Timer drives the simulation at 60fps
    private let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(simulation: simulation, selectedPlanet: $selectedPlanet, launchState: launchState)

            ZStack {
                OrbitCanvasView(simulation: simulation, selectedPlanet: $selectedPlanet, launchState: launchState)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.102, green: 0.090, blue: 0.078))
        .onReceive(timer) { _ in
            simulation.step(dt: 1.0/60.0)
        }
    }
}
