import SwiftUI
import simd

struct SidebarView: View {
    @ObservedObject var simulation: GravitySimulation
    @Binding var selectedPlanet: Int?
    @ObservedObject var launchState: LaunchState
    @State private var searchText = ""
    @State private var expandedBody: Int? = nil

    private var filteredBodies: [(index: Int, body: CelestialBody)] {
        let indexed = simulation.bodies.enumerated().map { (index: $0.offset, body: $0.element) }
        if searchText.isEmpty { return indexed }
        return indexed.filter { $0.body.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("Solar ")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Color(red: 0.30, green: 0.50, blue: 0.90))
                    Text("System")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Color(red: 0.910, green: 0.894, blue: 0.863))
                }
                Text("Sim")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color(red: 0.910, green: 0.894, blue: 0.863))
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 24)

            HStack {
                Text("Objects")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    simulation.resetSimulation()
                    launchState.deactivate()
                    selectedPlanet = nil
                    expandedBody = nil
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            LaunchPanelView(launchState: launchState)

            Spacer().frame(height: 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredBodies, id: \.index) { item in
                        BodyRowView(
                            simulation: simulation,
                            index: item.index,
                            isSelected: selectedPlanet == item.index,
                            isExpanded: expandedBody == item.index,
                            onTap: {
                                selectedPlanet = item.index
                            },
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedBody = expandedBody == item.index ? nil : item.index
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 320)
        .background(
            Color(red: 0.118, green: 0.106, blue: 0.090).opacity(0.92)
        )
    }
}

// MARK: - Body Row

struct BodyRowView: View {
    @ObservedObject var simulation: GravitySimulation
    let index: Int
    let isSelected: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    private var body_: CelestialBody { simulation.bodies[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Circle()
                    .fill(Color(red: body_.color.r, green: body_.color.g, blue: body_.color.b))
                    .frame(width: 10, height: 10)

                Text(body_.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(String(format: "%.1f Mkm", body_.distanceMillionKm))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
                onToggleExpand()
            }

            // Expanded detail panel
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color.white.opacity(0.1))

                    // Name
                    propertyRow(label: "Name") {
                        TextField("Name", text: Binding(
                            get: { simulation.bodies[index].name },
                            set: { simulation.bodies[index].name = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                    }

                    // Mass (log slider)
                    let logMass = Binding<Double>(
                        get: { log10(simulation.bodies[index].mass) },
                        set: { simulation.bodies[index].mass = pow(10, $0) }
                    )
                    propertyRow(label: "Mass") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatMass(simulation.bodies[index].mass))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                            Slider(value: logMass, in: 15...31)
                        }
                    }

                    // Display size
                    propertyRow(label: "Size") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1f", simulation.bodies[index].displayRadius))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                            Slider(value: Binding(
                                get: { Double(simulation.bodies[index].displayRadius) },
                                set: { simulation.bodies[index].displayRadius = CGFloat($0) }
                            ), in: 1...25)
                        }
                    }

                    // Distance from origin
                    let distBinding = Binding<Double>(
                        get: { simulation.bodies[index].distanceMillionKm },
                        set: { newDist in
                            let pos = simulation.bodies[index].position
                            let currentDist = simd_length(pos)
                            guard currentDist > 0 else { return }
                            let targetDist = newDist * 1e9
                            let scale = targetDist / currentDist
                            simulation.bodies[index].position = pos * scale
                        }
                    )
                    propertyRow(label: "Distance") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1f Million km", simulation.bodies[index].distanceMillionKm))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                            Slider(value: distBinding, in: 0...600)
                        }
                    }

                    // Velocity magnitude
                    let speed = simd_length(simulation.bodies[index].velocity)
                    propertyRow(label: "Speed") {
                        Text(formatSpeed(speed))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Position
                    let pos = simulation.bodies[index].position
                    propertyRow(label: "Position") {
                        Text(String(format: "%.2e, %.2e, %.2e", pos.x, pos.y, pos.z))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(10)
        .background(
            (isSelected || isExpanded) ? Color.white.opacity(0.06) : Color.white.opacity(0.02)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func propertyRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(0.5)
            content()
        }
    }

    private func formatMass(_ mass: Double) -> String {
        let exp = log10(mass)
        let mantissa = mass / pow(10, floor(exp))
        return String(format: "%.2f x 10^%.0f kg", mantissa, floor(exp))
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed > 1000 {
            return String(format: "%.1f km/s", speed / 1000)
        }
        return String(format: "%.1f m/s", speed)
    }
}
