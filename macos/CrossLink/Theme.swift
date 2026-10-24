import SwiftUI
import AppKit

/// Design tokens of replai-admin (src/styles/globals.css): white page, graphite text and main
/// buttons, neutral grey fills, thin borders, flat cards, pill buttons, a dark grainy brand surface.
/// The one difference is the brand colour: CrossLink's logo blue instead of replai orange.
/// Same values as android/.../ui/Theme.kt.
enum Tokens {
    static let background = dynamic(0xFFFFFF, 0x151413)      // 0 0% 100% / 30 5% 8%
    static let foreground = dynamic(0x1C1A17, 0xECE9E4)      // 30 8% 10% / 40 16% 91%
    static let card = dynamic(0xFFFFFF, 0x201F1D)            // card: 30 4% 12% in dark
    static let muted = dynamic(0xF5F5F5, 0x2D2B2A)           // 0 0% 96% / 30 4% 17%
    static let accent = dynamic(0xF2F2F2, 0x2D2B2A)          // hover fill
    static let mutedForeground = dynamic(0x6B6661, 0xB1ACA5) // 30 5% 40% / 35 7% 67%
    static let border = dynamic(0xE3E3E3, 0x2D2B2A)          // 0 0% 89%
    static let input = dynamic(0xD9D9D9, 0x3A3836)           // 0 0% 85%
    /// The logo colour; also the accent for states and focus (--brand / --primary).
    static let brand = Color(hex: 0x3552F5)
    /// Text on a brand-tinted fill (--primary-strong).
    static let brandStrong = dynamic(0x2338B0, 0x9DABFF)
    static let destructive = dynamic(0x931A2A, 0x9D2535)     // 352 70% 34% / 352 62% 38%
    static let destructiveText = dynamic(0x931A2A, 0xF0919C)

    /// The brand panel looks the same in both themes, as replai's --brand-ink.
    static let ink = Color(hex: 0x1B1A18)
    static let pink = Color(hex: 0xFF4D8D)
    static let cyan = Color(hex: 0x22D3EE)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

/// Radius scale: four steps, then only capsules. Buttons are always capsules.
enum Radius {
    static let field: CGFloat = 8
    static let control: CGFloat = 12
    static let pop: CGFloat = 20
    static let card: CGFloat = 24
}

/// Motion scale of replai (transitions.dev). Pick by meaning: closing is shorter than opening.
enum Motion {
    static func smoothOut(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static let quick = smoothOut(0.15)
    static let fast = smoothOut(0.25)
    static let medium = smoothOut(0.35)
    static let slow = smoothOut(0.4)
    static let verySlow = smoothOut(0.5)
}

/// Inter from replai, bundled in Fonts/ (ATSApplicationFontsPath).
enum Typo {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold, .heavy, .black: "Inter-Bold"
        default: "Inter-Regular"
        }
        return .custom(name, size: size)
    }
    static func display(_ size: CGFloat) -> Font { .custom("InterDisplay-SemiBold", size: size) }
    static let body = inter(13)
    static let title = inter(14, .semibold)
    static let caption = inter(11)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The only button shape: a capsule means "pressable", a rounded rectangle means "type here".
/// Primary is graphite (foreground on background), as in replai; the brand colour marks states.
struct Pill: ButtonStyle {
    enum Kind { case primary, secondary, outline, ghost, inverse, glass, danger }
    var kind: Kind = .primary
    var height: CGFloat = 32
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, height: height, fullWidth: fullWidth)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let height: CGFloat
        let fullWidth: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typo.inter(13, .medium))
                .labelStyle(PillLabel())
                .lineLimit(1)
                .foregroundStyle(ink)
                .padding(.horizontal, height < 30 ? 10 : 14)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
                .contentShape(Capsule())
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.quick, value: configuration.isPressed)
                .animation(Motion.quick, value: hovering)
                .onHover { hovering = $0 && enabled }
        }

        private var ink: Color {
            switch kind {
            case .primary: Tokens.background
            case .secondary, .outline: Tokens.foreground
            case .ghost: hovering ? Tokens.foreground : Tokens.mutedForeground
            case .inverse: Tokens.ink
            case .glass: .white
            case .danger: Tokens.destructiveText
            }
        }

        private var fill: Color {
            switch kind {
            case .primary: Tokens.foreground.opacity(hovering ? 0.88 : 1)
            case .secondary: hovering ? Tokens.border : Tokens.muted
            case .outline, .ghost, .danger: hovering ? Tokens.accent : .clear
            case .inverse: .white.opacity(hovering ? 0.9 : 1)
            case .glass: .white.opacity(hovering ? 0.16 : 0.10)
            }
        }

        private var edge: Color {
            switch kind {
            case .outline: Tokens.border
            case .glass: .white.opacity(0.16)
            default: .clear
            }
        }
    }

    private struct PillLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.font(.system(size: 12, weight: .semibold))
                configuration.title
            }
        }
    }
}

/// Text field look: rounded-control, input border, brand focus ring (--shadow-focus).
struct FieldLook: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Typo.body)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Tokens.background))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(focused ? Tokens.brand : Tokens.input, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .fill(Tokens.brand.opacity(focused ? 0.2 : 0)).padding(-3))
            .animation(Motion.quick, value: focused)
    }
}

/// A flat card with a hairline border, like replai's inline cards.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Tokens.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Tokens.border, lineWidth: 1))
    }
}

/// replai's dark grainy brand surface, lit by the logo's blue and pink glows.
/// [glow] 0...1 brightens the blue light, so a live link visibly "switches on" the panel.
struct BrandSurface<Content: View>: View {
    var glow: Double
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                GeometryReader { box in
                    let w = box.size.width
                    let h = box.size.height
                    ZStack {
                        Tokens.ink
                        RadialGradient(colors: [Tokens.brand.opacity(0.30 + 0.35 * glow), .clear],
                                       center: UnitPoint(x: 0.92, y: -0.05), startRadius: 0, endRadius: w * 0.85)
                        RadialGradient(colors: [Tokens.pink.opacity(0.16 + 0.10 * glow), .clear],
                                       center: UnitPoint(x: 0.02, y: 1.08), startRadius: 0, endRadius: w * 0.7)
                        RadialGradient(colors: [Tokens.cyan.opacity(0.10 * glow), .clear],
                                       center: UnitPoint(x: 0.55, y: 0.55), startRadius: 0, endRadius: max(w, h) * 0.45)
                        Image(nsImage: Grain.tile).resizable(resizingMode: .tile)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

/// A tile of white specks with random alpha: the film grain of the brand surface.
private enum Grain {
    static let tile: NSImage = {
        let side = 160
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32),
              let pixels = rep.bitmapData else { return NSImage() }
        var generator = SplitMix(seed: 7)
        for index in 0..<(side * side) {
            // Premultiplied white: every channel equals the alpha
            let alpha = UInt8(generator.next() % 26)
            pixels[index * 4] = alpha
            pixels[index * 4 + 1] = alpha
            pixels[index * 4 + 2] = alpha
            pixels[index * 4 + 3] = alpha
        }
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        image.addRepresentation(rep)
        return image
    }()

    /// Seeded, so the grain is the same on every launch.
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}

/// Connection dot; a live link breathes with a soft halo.
struct StatusDot: View {
    var live: Bool
    var color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            if live {
                Circle().fill(color.opacity(pulse ? 0 : 0.55)).frame(width: 8, height: 8).scaleEffect(pulse ? 2.6 : 1)
            }
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Thin capsule progress bar in the brand colour.
struct ProgressLine: View {
    var value: Double
    var body: some View {
        GeometryReader { box in
            Capsule().fill(Tokens.muted)
                .overlay(alignment: .leading) {
                    Capsule().fill(Tokens.brand).frame(width: box.size.width * min(max(value, 0), 1))
                }
        }
        .frame(height: 4)
        .animation(Motion.slow, value: value)
    }
}

/// Symbol on a neutral rounded square (rounded-control), as replai's icon boxes.
struct IconBox: View {
    var symbol: String
    var tint: Color = Tokens.foreground
    var fill: Color = Tokens.muted
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control - 2, style: .continuous).fill(fill))
    }
}
