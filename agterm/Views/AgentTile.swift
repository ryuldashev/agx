import agtermCore
import SwiftUI

/// An agent's tile: its manifest glyph on a tinted rounded square, the first letter of its name on grey
/// when the manifest declares none. Used by Settings ▸ Agents and the hooks-install result.
struct AgentTile: View {
    let profile: AgentProfile
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.gradient)
            Text(profile.icon?.glyph ?? String(profile.name.prefix(1)))
                .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        Color(nsColor: NSColor(agtermHex: profile.icon?.tint) ?? .systemGray)
    }
}
