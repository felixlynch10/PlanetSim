import SwiftUI
import simd

struct SidebarView: View {
    @ObservedObject var simulation: GravitySimulation
    @Binding var selectedPlanet: Int?
    @ObservedObject var launchState: LaunchState
    @Binding var followingBody: Int?
    @State private var searchText = ""
    @State private var expandedBody: Int? = nil
    @State private var selectedScenario: Int = 0

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

            // Scenario picker
            VStack(alignment: .leading, spacing: 6) {
                Text("SCENARIO")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.5)

                Menu {
                    ForEach(ScenarioPresets.all.indices, id: \.self) { i in
                        Button(action: {
                            selectedScenario = i
                            let bodies = ScenarioPresets.all[i].builder()
                            simulation.loadBodies(bodies)
                            launchState.deactivate()
                            selectedPlanet = nil
                            followingBody = nil
                            expandedBody = nil
                        }) {
                            VStack(alignment: .leading) {
                                Text(ScenarioPresets.all[i].name)
                                Text(ScenarioPresets.all[i].description)
                                    .font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(ScenarioPresets.all[selectedScenario].name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 16)

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
                    selectedScenario = 0
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
                            },
                            followingBody: $followingBody
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
    var followingBody: Binding<Int?>? = nil

    private var body_: CelestialBody? {
        index < simulation.bodies.count ? simulation.bodies[index] : nil
    }

    private func safeBody(_ idx: Int) -> CelestialBody? {
        idx < simulation.bodies.count ? simulation.bodies[idx] : nil
    }

    var body: some View {
        if let body_ = body_ {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack {
                    Circle()
                        .fill(Color(red: body_.color.r, green: body_.color.g, blue: body_.color.b))
                        .frame(width: 10, height: 10)

                    Text(body_.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    if body_.bodyType != .normal {
                        Text(body_.bodyType.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(typeBadgeColor(body_.bodyType))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

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
                                get: { safeBody(index)?.name ?? "" },
                                set: { if index < simulation.bodies.count { simulation.bodies[index].name = $0 } }
                            ))
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                        }

                        // Mass (log slider)
                        let logMass = Binding<Double>(
                            get: { log10(safeBody(index)?.mass ?? 1e22) },
                            set: { if index < simulation.bodies.count { simulation.bodies[index].mass = pow(10, $0) } }
                        )
                        propertyRow(label: "Mass") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatMass(body_.mass))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                Slider(value: logMass, in: 15...38)
                            }
                        }

                        // Display size
                        propertyRow(label: "Size") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1f", body_.displayRadius))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                Slider(value: Binding(
                                    get: { Double(safeBody(index)?.displayRadius ?? 3) },
                                    set: { if index < simulation.bodies.count { simulation.bodies[index].displayRadius = CGFloat($0) } }
                                ), in: 1...25)
                            }
                        }

                        // Distance from origin
                        let distBinding = Binding<Double>(
                            get: { safeBody(index)?.distanceMillionKm ?? 0 },
                            set: { newDist in
                                guard index < simulation.bodies.count else { return }
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
                                Text(String(format: "%.1f Million km", body_.distanceMillionKm))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                Slider(value: distBinding, in: 0...600)
                            }
                        }

                        // Velocity magnitude
                        propertyRow(label: "Speed") {
                            Text(formatSpeed(simd_length(body_.velocity)))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        // Position
                        propertyRow(label: "Position") {
                            Text(String(format: "%.2e, %.2e, %.2e", body_.position.x, body_.position.y, body_.position.z))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }

                        // Orbital energy & status
                        if index > 0, index < simulation.bodies.count {
                            let escaping = simulation.isEscaping(index: index)
                            propertyRow(label: "Orbit") {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(escaping ? Color(red: 0.9, green: 0.3, blue: 0.2) : Color(red: 0.3, green: 0.8, blue: 0.4))
                                        .frame(width: 6, height: 6)
                                    Text(escaping ? "Escape trajectory" : "Bound orbit")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }

                            if let periodStr = simulation.orbitalPeriodString(index: index) {
                                propertyRow(label: "Period") {
                                    Text(periodStr)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }

                        // Follow button
                        if let followBinding = followingBody {
                            let isFollowing = followBinding.wrappedValue == index
                            Button(action: {
                                followBinding.wrappedValue = isFollowing ? nil : index
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isFollowing ? "location.fill" : "location")
                                        .font(.system(size: 10))
                                    Text(isFollowing ? "Following" : "Follow")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(isFollowing ? Color(red: 0.30, green: 0.50, blue: 0.90) : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(isFollowing ? Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.15) : Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        // Exotic object details
                        if body_.bodyType == .blackHole {
                            let rs = body_.schwarzschildRadius
                            propertyRow(label: "Schwarzschild Radius") {
                                Text(String(format: "%.2e m (%.1f km)", rs, rs / 1000.0))
                                    .font(.system(size: 11))
                                    .foregroundColor(.purple.opacity(0.8))
                            }
                        }

                        if body_.bodyType == .wormhole {
                            propertyRow(label: "Throat Radius") {
                                Text(String(format: "%.1f Mkm", body_.throatRadius / 1e9))
                                    .font(.system(size: 11))
                                    .foregroundColor(.cyan.opacity(0.8))
                            }
                            if let linkedId = body_.linkedWormholeId,
                               let partner = simulation.bodies.first(where: { $0.id == linkedId }) {
                                propertyRow(label: "Paired With") {
                                    Text(partner.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.cyan.opacity(0.8))
                                }
                            }
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

    private func typeBadgeColor(_ type: BodyType) -> Color {
        switch type {
        case .blackHole: return .purple.opacity(0.6)
        case .neutronStar: return .cyan.opacity(0.6)
        case .wormhole: return .blue.opacity(0.6)
        case .normal: return .clear
        }
    }
}
