import SwiftUI

struct LaunchPanelView: View {
    @ObservedObject var launchState: LaunchState

    private let colorPresets: [(String, PlanetColor)] = [
        ("White", PlanetColor(r: 0.9, g: 0.9, b: 0.9)),
        ("Red", PlanetColor(r: 0.9, g: 0.3, b: 0.2)),
        ("Orange", PlanetColor(r: 0.9, g: 0.6, b: 0.2)),
        ("Blue", PlanetColor(r: 0.3, g: 0.5, b: 0.9)),
        ("Green", PlanetColor(r: 0.3, g: 0.8, b: 0.4)),
        ("Purple", PlanetColor(r: 0.7, g: 0.3, b: 0.9)),
    ]

    private var logMass: Binding<Double> {
        Binding(
            get: { log10(launchState.objectMass) },
            set: { launchState.objectMass = pow(10, $0) }
        )
    }

    private var logThroat: Binding<Double> {
        Binding(
            get: { log10(launchState.objectThroatRadius) },
            set: { launchState.objectThroatRadius = pow(10, $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toggle button
            Button(action: {
                if launchState.isActive {
                    launchState.deactivate()
                } else {
                    launchState.activate()
                }
            }) {
                HStack {
                    Image(systemName: launchState.isActive ? "xmark.circle.fill" : "scope")
                    Text(launchState.isActive ? "Cancel Launch" : "Launch Object")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    launchState.isActive
                        ? Color.red.opacity(0.6)
                        : Color(red: 0.30, green: 0.50, blue: 0.90)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if launchState.isActive {
                // Body type picker
                Picker("Type", selection: $launchState.objectType) {
                    ForEach(BodyType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: launchState.objectType) { _ in
                    launchState.applyTypeDefaults()
                    if launchState.objectType == .wormhole {
                        launchState.wormholePlacementPhase = .placingFirst
                    } else {
                        launchState.wormholePlacementPhase = .none
                    }
                }

                // Name
                TextField("Name", text: $launchState.objectName)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Mass slider (extended range for black holes)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mass: \(massLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: logMass, in: 15...38, step: 0.5)
                }

                // Size slider
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size: \(String(format: "%.1f", launchState.objectDisplayRadius))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: $launchState.objectDisplayRadius, in: 1...10)
                }

                // Throat radius for wormholes
                if launchState.objectType == .wormhole {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Throat Radius: \(String(format: "%.0f Mkm", launchState.objectThroatRadius / 1e9))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        Slider(value: logThroat, in: 9...10.7, step: 0.1)
                    }
                }

                // Color presets
                HStack(spacing: 8) {
                    ForEach(colorPresets, id: \.0) { name, color in
                        Circle()
                            .fill(Color(red: color.r, green: color.g, blue: color.b))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(isSelectedColor(color) ? 0.8 : 0), lineWidth: 2)
                            )
                            .onTapGesture {
                                launchState.objectColor = color
                            }
                    }
                }

                // Instructions
                if launchState.objectType == .wormhole {
                    switch launchState.wormholePlacementPhase {
                    case .placingFirst:
                        Text("Click to place entry portal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.8))
                    case .placingSecond(_, let name):
                        Text("Now place exit portal for \(name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.8))
                    case .none:
                        EmptyView()
                    }
                } else {
                    Text("Click on canvas to place, drag to aim")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var massLabel: String {
        let exp = log10(launchState.objectMass)
        return String(format: "10^%.0f kg", exp)
    }

    private func isSelectedColor(_ color: PlanetColor) -> Bool {
        color.r == launchState.objectColor.r &&
        color.g == launchState.objectColor.g &&
        color.b == launchState.objectColor.b
    }
}
