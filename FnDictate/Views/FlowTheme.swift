import AppKit
import SwiftUI

// MARK: - Theme (adaptive light / dark)

enum FlowTheme {
    static let canvas = Color(nsColor: .flowCanvas)
    static let sidebar = Color(nsColor: .flowSidebar)
    static let card = Color(nsColor: .flowCard)
    static let cream = Color(nsColor: .flowCream)
    static let accent = Color(nsColor: .flowAccent)
    static let accentSoft = Color(nsColor: .flowAccentSoft)
    static let ink = Color(nsColor: .flowInk)
    static let muted = Color(nsColor: .flowMuted)
    static let hairline = Color(nsColor: .flowHairline)
    /// Filled CTA (black in light, off-white in dark).
    static let solid = Color(nsColor: .flowSolid)
    static let onSolid = Color(nsColor: .flowOnSolid)
    /// Text sitting on a white chip (always dark).
    static let onLightChip = Color(red: 0.11, green: 0.11, blue: 0.11)
    /// Wispr-style insight bars / heatmap (teal).
    static let insight = Color(nsColor: .flowInsight)
    static let insightMid = Color(nsColor: .flowInsightMid)
    static let insightSoft = Color(nsColor: .flowInsightSoft)

    static let warmGradient = LinearGradient(
        colors: [
            Color(red: 0.72, green: 0.52, blue: 0.35),
            Color(red: 0.55, green: 0.38, blue: 0.28),
            Color(red: 0.42, green: 0.30, blue: 0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension NSColor {
    static func flowDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let flowCanvas = flowDynamic(
        light: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.969, alpha: 1),
        dark: NSColor(srgbRed: 0.102, green: 0.100, blue: 0.094, alpha: 1) // #1A1918
    )
    static let flowSidebar = flowDynamic(
        light: NSColor(srgbRed: 0.957, green: 0.955, blue: 0.949, alpha: 1),
        dark: NSColor(srgbRed: 0.078, green: 0.076, blue: 0.071, alpha: 1) // #141311
    )
    static let flowCard = flowDynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.157, green: 0.153, blue: 0.145, alpha: 1) // #282724
    )
    static let flowCream = flowDynamic(
        light: NSColor(srgbRed: 0.953, green: 0.949, blue: 0.933, alpha: 1),
        dark: NSColor(srgbRed: 0.184, green: 0.176, blue: 0.165, alpha: 1) // #2F2D2A
    )
    static let flowAccent = flowDynamic(
        light: NSColor(srgbRed: 0.890, green: 0.839, blue: 0.757, alpha: 1),
        dark: NSColor(srgbRed: 0.420, green: 0.365, blue: 0.290, alpha: 1) // warm selected
    )
    static let flowAccentSoft = flowDynamic(
        light: NSColor(srgbRed: 0.925, green: 0.890, blue: 0.835, alpha: 1),
        dark: NSColor(srgbRed: 0.235, green: 0.210, blue: 0.175, alpha: 1)
    )
    static let flowInk = flowDynamic(
        light: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.110, alpha: 1),
        dark: NSColor(srgbRed: 0.953, green: 0.945, blue: 0.925, alpha: 1) // #F3F1EC
    )
    static let flowMuted = flowDynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.48)
    )
    static let flowHairline = flowDynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let flowSolid = flowDynamic(
        light: .black,
        dark: NSColor(srgbRed: 0.953, green: 0.945, blue: 0.925, alpha: 1)
    )
    static let flowOnSolid = flowDynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.110, alpha: 1)
    )
    static let flowInsight = flowDynamic(
        light: NSColor(srgbRed: 0.145, green: 0.412, blue: 0.373, alpha: 1),
        dark: NSColor(srgbRed: 0.353, green: 0.620, blue: 0.565, alpha: 1)
    )
    static let flowInsightMid = flowDynamic(
        light: NSColor(srgbRed: 0.420, green: 0.690, blue: 0.655, alpha: 1),
        dark: NSColor(srgbRed: 0.275, green: 0.490, blue: 0.450, alpha: 1)
    )
    static let flowInsightSoft = flowDynamic(
        light: NSColor(srgbRed: 0.780, green: 0.890, blue: 0.865, alpha: 1),
        dark: NSColor(srgbRed: 0.220, green: 0.330, blue: 0.310, alpha: 1)
    )
}
