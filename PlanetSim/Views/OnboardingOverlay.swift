import SwiftUI

struct OnboardingOverlay: View {
    let onDismiss: () -> Void

    private let hints: [(icon: String, text: String)] = [
        ("scroll", "Scroll to zoom in and out"),
        ("cursorarrow.motionlines", "Drag to rotate the view"),
        ("hand.point.up.left", "Click a planet to inspect it"),
        ("scope", "Use Launch Object to add new bodies"),
        ("keyboard", "Space = pause, L = labels, V = forces, O = orbits"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to PlanetSim")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(hints, id: \.text) { hint in
                    HStack(spacing: 10) {
                        Image(systemName: hint.icon)
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.30, green: 0.50, blue: 0.90))
                            .frame(width: 20)
                        Text(hint.text)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.30, green: 0.50, blue: 0.90))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .background(Color(red: 0.118, green: 0.106, blue: 0.090).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
