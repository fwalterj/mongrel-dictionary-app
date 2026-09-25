import Foundation

/// A colour expressed as hue, saturation, and brightness, each normalised to `0...1`.
///
/// The appearance system stores colours this way rather than as `Color` so the
/// palette, its persisted form, and its contrast arithmetic can all live in the
/// framework and be tested without a running SwiftUI hierarchy.
public struct MongrelHSB: Hashable, Sendable {
    public let hue: Double
    public let saturation: Double
    public let brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.clamped(hue)
        self.saturation = Self.clamped(saturation)
        self.brightness = Self.clamped(brightness)
    }

    /// Convenience initialiser for palettes written in degrees.
    public init(degrees: Double, saturation: Double, brightness: Double) {
        self.init(hue: degrees / 360, saturation: saturation, brightness: brightness)
    }

    public static let black = MongrelHSB(hue: 0, saturation: 0, brightness: 0)
    public static let white = MongrelHSB(hue: 0, saturation: 0, brightness: 1)

    /// Straight sRGB components in `0...1`, before any transfer-function work.
    public var rgb: (red: Double, green: Double, blue: Double) {
        let sector = Int(hue * 6) % 6
        let offset = hue * 6 - Double(Int(hue * 6))
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - offset * saturation)
        let rising = brightness * (1 - (1 - offset) * saturation)

        switch sector {
        case 0: return (brightness, rising, low)
        case 1: return (falling, brightness, low)
        case 2: return (low, brightness, rising)
        case 3: return (low, falling, brightness)
        case 4: return (rising, low, brightness)
        default: return (brightness, low, falling)
        }
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linearise(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let components = rgb
        return 0.2126 * linearise(components.red)
            + 0.7152 * linearise(components.green)
            + 0.0722 * linearise(components.blue)
    }

    /// A copy with brightness nudged toward white, used to lift elevated surfaces.
    public func lightened(by amount: Double) -> MongrelHSB {
        MongrelHSB(hue: hue, saturation: saturation, brightness: brightness + amount)
    }

    /// A copy with brightness pulled toward black.
    public func darkened(by amount: Double) -> MongrelHSB {
        MongrelHSB(hue: hue, saturation: saturation, brightness: brightness - amount)
    }

    /// Moves a surface away from the canvas in whichever direction stays visible.
    ///
    /// Light palettes must get *darker* to read as elevated; dark palettes must
    /// get lighter. Elevation that always adds brightness disappears on paper.
    public func elevated(by amount: Double) -> MongrelHSB {
        relativeLuminance > 0.45 ? darkened(by: amount) : lightened(by: amount)
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

/// WCAG contrast arithmetic, kept separate from any presentation type.
public enum MongrelContrast {
    /// WCAG 2.x contrast ratio between two colours, from `1` to `21`.
    public static func ratio(background: MongrelHSB, text: MongrelHSB) -> Double {
        let a = background.relativeLuminance
        let b = text.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// How a ratio should be described to somebody choosing their own colours.
    public enum Grade: Sendable {
        /// 7:1 or better. Comfortable for dense definitions and long sessions.
        case enhanced
        /// 4.5:1 or better. Fine for ordinary interface text.
        case ordinary
        /// 3:1 or better. Large text and prominent controls only.
        case largeTextOnly
        /// Below 3:1. Not usable.
        case insufficient

        public var summary: String {
            switch self {
            case .enhanced: return "Enhanced contrast, comfortable for long definitions."
            case .ordinary: return "Readable contrast for ordinary text."
            case .largeTextOnly: return "Suitable only for large text and prominent controls."
            case .insufficient: return "Low contrast. Move the two colours further apart."
            }
        }

        /// Whether supporting text may be dimmed at all under this pairing.
        public var allowsDimmedText: Bool {
            self == .enhanced || self == .ordinary
        }
    }

    public static func grade(_ ratio: Double) -> Grade {
        if ratio >= 7 { return .enhanced }
        if ratio >= 4.5 { return .ordinary }
        if ratio >= 3 { return .largeTextOnly }
        return .insufficient
    }
}

/// The three viewing modes shared across the Mongrel suite.
public enum MongrelAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    /// True black with white type and cues. The default.
    case contrast
    /// The original Mongrel deep-blue glass identity.
    case classic
    /// A background and text pair chosen by the reader.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .contrast: return "Contrast"
        case .classic: return "Classic"
        case .custom: return "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .contrast:
            return "Black or White surfaces with opposite type and cues, at the maximum 21:1 ratio."
        case .classic:
            return "The original Mongrel deep-blue glass palette."
        case .custom:
            return "Choose a readable preset or build your own background and text pair."
        }
    }

    /// The fixed background for the modes that define one. `nil` for `custom`.
    public var fixedBackground: MongrelHSB? {
        switch self {
        case .contrast: return .black
        case .classic: return MongrelHSB(degrees: 222, saturation: 0.42, brightness: 0.05)
        case .custom: return nil
        }
    }

    /// The fixed text colour for the modes that define one. `nil` for `custom`.
    public var fixedText: MongrelHSB? {
        switch self {
        case .contrast: return .white
        case .classic: return MongrelHSB(degrees: 222, saturation: 0.10, brightness: 0.88)
        case .custom: return nil
        }
    }

    /// Whether decorative tint, chromatic glow, and translucency are permitted.
    public var allowsDecorativeTint: Bool {
        self == .classic
    }

    /// Resolves a persisted value, tolerating names used earlier in development.
    ///
    /// A missing preference means a clean install, which must open in Contrast.
    public static func storedValue(_ rawValue: String?) -> Self {
        guard let rawValue else { return .contrast }
        // "standard" shipped briefly while the mode was still being named.
        if rawValue == "standard" { return .classic }
        return Self(rawValue: rawValue) ?? .contrast
    }
}

public enum MongrelContrastPage: String, CaseIterable, Identifiable, Sendable {
    case black, white
    public var id: String { rawValue }
    public var title: String { self == .black ? "Black" : "White" }
    public var background: MongrelHSB { self == .black ? .black : .white }
    public var text: MongrelHSB { self == .black ? .white : .black }
    public static func storedValue(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .black
    }
}

/// Dictionary's earlier two-theme preference, kept only so existing installs
/// carry their bloom choice into the suite-wide three-mode system.
public enum MongrelLegacyDictionaryTheme {
    public static let storageKey = "mongrel.visual-theme"

    /// Both legacy themes were maximum-contrast palettes; they differed only in
    /// whether reading text glowed. That maps to Contrast plus a bloom flag.
    public static func migrate(_ rawValue: String?) -> (mode: MongrelAppearanceMode, bloomEnabled: Bool)? {
        switch rawValue {
        case "deep-black-bloom": return (.contrast, true)
        case "deep-black-crisp": return (.contrast, false)
        default: return nil
        }
    }
}

/// A named background and text pair offered in Custom mode.
///
/// Every bundled preset is expected to clear 4.5:1; `AppearanceContrastTests`
/// enforces that so a shipped preset can never make the app unreadable.
public struct MongrelColorPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Short note on who the pairing is for, so the choice is not colour-only.
    public let detail: String
    public let background: MongrelHSB
    public let text: MongrelHSB

    public var contrastRatio: Double {
        MongrelContrast.ratio(background: background, text: text)
    }

    public static let all: [Self] = [
        .init(
            id: "midnight-ink",
            title: "Midnight Ink",
            detail: "Near-black blue with white type.",
            background: MongrelHSB(degrees: 222, saturation: 0.45, brightness: 0.05),
            text: MongrelHSB(degrees: 215, saturation: 0.03, brightness: 1.0)
        ),
        .init(
            id: "warm-paper",
            title: "Warm Paper",
            detail: "Light page with dark ink, for daylight reading.",
            background: MongrelHSB(degrees: 42, saturation: 0.12, brightness: 0.96),
            text: MongrelHSB(degrees: 24, saturation: 0.25, brightness: 0.12)
        ),
        .init(
            id: "slate",
            title: "Slate",
            detail: "Neutral grey-blue with warm white type.",
            background: MongrelHSB(degrees: 210, saturation: 0.20, brightness: 0.14),
            text: MongrelHSB(degrees: 45, saturation: 0.05, brightness: 0.96)
        ),
        .init(
            id: "forest",
            title: "Forest",
            detail: "Deep green with pale green type.",
            background: MongrelHSB(degrees: 145, saturation: 0.40, brightness: 0.10),
            text: MongrelHSB(degrees: 95, saturation: 0.12, brightness: 0.95)
        ),
        .init(
            id: "amber-terminal",
            title: "Amber Terminal",
            detail: "Black with amber type, for glare-sensitive readers.",
            background: .black,
            text: MongrelHSB(degrees: 40, saturation: 1.0, brightness: 1.0)
        ),
        .init(
            id: "quiet-sepia",
            title: "Quiet Sepia",
            detail: "Muted cream page with brown-black ink.",
            background: MongrelHSB(degrees: 36, saturation: 0.18, brightness: 0.90),
            text: MongrelHSB(degrees: 28, saturation: 0.40, brightness: 0.16)
        )
    ]
}

/// Reader-controlled type size and line spacing for definition text.
///
/// This is deliberately independent of the palette. Somebody who wants larger
/// definitions should not have to accept a different colour scheme to get them,
/// and somebody in Contrast mode should still be able to loosen line spacing.
public struct DictionaryReadingMetrics: Hashable, Sendable {
    public static let textScaleRange: ClosedRange<Double> = 0.9...1.75
    public static let lineSpacingScaleRange: ClosedRange<Double> = 0.85...2.0
    public static let standard = DictionaryReadingMetrics(textScale: 1, lineSpacingScale: 1)

    /// Multiplier applied to reading type sizes.
    public let textScale: Double
    /// Multiplier applied to the space between lines of reading type.
    public let lineSpacingScale: Double

    public init(textScale: Double, lineSpacingScale: Double) {
        self.textScale = min(Self.textScaleRange.upperBound, max(Self.textScaleRange.lowerBound, textScale))
        self.lineSpacingScale = min(
            Self.lineSpacingScaleRange.upperBound,
            max(Self.lineSpacingScaleRange.lowerBound, lineSpacingScale)
        )
    }

    /// Scales a reading-surface point size. Interface chrome is left alone so
    /// larger definitions do not push the toolbar and sidebar out of shape.
    public func readingSize(_ basePointSize: Double) -> Double {
        (basePointSize * textScale).rounded(toNearest: 0.5)
    }

    /// Scales inter-line space, growing slightly faster than type size because
    /// long definitions need looser leading before they become comfortable.
    public func readingLineSpacing(_ baseSpacing: Double) -> Double {
        (baseSpacing * textScale * lineSpacingScale).rounded(toNearest: 0.5)
    }

    public var textScaleLabel: String {
        "\(Int((textScale * 100).rounded()))%"
    }

    public var lineSpacingLabel: String {
        "\(Int((lineSpacingScale * 100).rounded()))%"
    }

    /// Whether the reader has moved away from the shipped defaults.
    public var isCustomised: Bool {
        self != .standard
    }
}

private extension Double {
    func rounded(toNearest increment: Double) -> Double {
        guard increment > 0 else { return self }
        return (self / increment).rounded() * increment
    }
}
