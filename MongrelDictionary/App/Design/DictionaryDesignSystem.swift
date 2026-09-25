import MongrelDictionaryCore
import SwiftUI

/// The semantic palette for Mongrel Dictionary.
///
/// Every value is derived from the reader's active viewing mode rather than
/// fixed at compile time. Views ask for the *role* they need — a card surface,
/// secondary text, a selection cue — and the mode decides how that role looks.
///
/// Three rules govern the derivations:
///
/// 1. Contrast mode stays genuinely black and white. Surfaces do not drift into
///    fashionable charcoal; they remain the canvas colour and are separated by
///    borders instead of fills.
/// 2. Nothing may be communicated by colour alone, so `accent` collapses onto
///    the text colour outside Classic. Callers pair it with an icon, weight,
///    stripe, or position.
/// 3. Dimming is earned. Supporting text is only allowed to fade when the
///    active background and text pair has contrast to spare.
enum DesignTokens {
    private static var appearance: MongrelAppearancePreferences { .shared }
    private static var mode: MongrelAppearanceMode { appearance.mode }
    private static var backgroundValue: MongrelHSB { appearance.backgroundValue }
    private static var textValue: MongrelHSB { appearance.textValue }

    /// The Mongrel suite's signature deep indigo, used only by Classic.
    private static let energyHue: Double = 222 / 360

    // MARK: – Surfaces

    /// The window floor. Everything else sits on this.
    static var canvas: Color { Color(backgroundValue) }

    /// The darkest surface in the hierarchy: toolbars, sidebar floor.
    static var glassDeep: Color { canvas }

    /// Standard panels and sidebars.
    static var glassBase: Color { surface(elevation: 0.035) }

    /// Result cards and selectable rows.
    static var glassCard: Color { surface(elevation: 0.065) }

    /// Floating sheets, popovers, and inset controls, one clear step lifted.
    static var glassElevated: Color { surface(elevation: 0.10) }

    /// Surfaces are separated by borders rather than fills in Contrast, which is
    /// what keeps that mode a true 21:1 pairing everywhere text appears.
    private static func surface(elevation: Double) -> Color {
        switch mode {
        case .contrast:
            return canvas
        case .custom:
            return Color(backgroundValue.elevated(by: elevation))
        case .classic:
            return Color(
                light: MongrelHSB(hue: energyHue, saturation: 0.42, brightness: 0.94 - elevation),
                dark: MongrelHSB(hue: energyHue, saturation: 0.44, brightness: 0.07 + elevation)
            )
        }
    }

    // MARK: – Text

    /// Headwords, definitions, and anything the reader came here to read.
    static var textPrimary: Color { Color(textValue) }

    /// Interface chrome text. Shares the primary role; named separately so the
    /// two can diverge later without touching call sites.
    static var chromeText: Color { textPrimary }

    /// Pronunciation, part of speech, register, region, source, and date.
    static var textSecondary: Color { mutedText(0.90) }

    /// Supporting metadata: counts, latencies, captions.
    static var textMuted: Color { mutedText(0.74) }

    /// Unavailable controls. Still perceivable, because a control the reader
    /// cannot see is indistinguishable from one that is missing.
    static var textDisabled: Color { mutedText(0.45) }

    /// Text drawn on top of an `accent` fill.
    static var onAccent: Color { canvas }

    /// Dims the text colour only as far as the active pairing can afford.
    ///
    /// A flat 40%-grey-on-black caption looks elegant in Classic and disappears
    /// in Contrast. The floor here rises as headroom falls, and a pairing with
    /// no headroom left gets no dimming at all.
    static func mutedText(_ requestedOpacity: Double) -> Color {
        let requested = min(1, max(0, requestedOpacity))
        switch MongrelContrast.grade(appearance.contrastRatio) {
        case .enhanced:
            return textPrimary.opacity(max(0.72, requested))
        case .ordinary:
            return textPrimary.opacity(max(0.85, requested))
        case .largeTextOnly, .insufficient:
            return textPrimary
        }
    }

    // MARK: – Accent and selection

    /// Interactive emphasis. Outside Classic this is the text colour, so it can
    /// never be the only carrier of meaning.
    static var accent: Color {
        mode == .classic ? Color(hue: energyHue, saturation: 0.85, brightness: 0.88) : textPrimary
    }

    /// Accent at reduced intensity, for secondary interactive labels.
    static var accentDim: Color {
        mode == .classic
            ? Color(hue: energyHue, saturation: 0.70, brightness: 0.72)
            : mutedText(0.80)
    }

    /// Fill behind a selected search result or list row. Always paired with an
    /// accent stripe so selection survives for readers who cannot see the fill.
    static var selectionFill: Color {
        mode == .classic ? accent.opacity(0.20) : textPrimary.opacity(0.16)
    }

    /// Fill behind a hovered row or button.
    static var hoverBloom: Color {
        mode == .classic ? accent.opacity(0.16) : textPrimary.opacity(0.12)
    }

    /// The keyboard focus indicator. Kept distinct from hover and selection so
    /// keyboard users can always locate the current target.
    static var focusRing: Color { accent }

    /// Background behind a matched query term inside a definition.
    ///
    /// Never a fixed yellow or blue: a highlight has to be checked against the
    /// active pair, not against an assumption about the canvas.
    static var highlightFill: Color {
        mode == .classic ? accent.opacity(0.30) : textPrimary.opacity(0.20)
    }

    // MARK: – Borders and separators

    // Three weights, because Contrast mode separates surfaces with borders
    // rather than fills. A single weight either leaves panels invisible or
    // turns every inset row into a bright white cage.

    /// Hairline for capsules, badges, and inset controls.
    static var borderRim: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.34)
        case .custom: return textPrimary.opacity(0.26)
        case .classic: return Color(hue: energyHue, saturation: 0.90, brightness: 0.90, opacity: 0.16)
        }
    }

    /// Outline for panels and result cards — the structural boundaries a reader
    /// needs in order to tell one entry from the next.
    static var borderPanel: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.58)
        case .custom: return textPrimary.opacity(0.44)
        case .classic: return Color(hue: energyHue, saturation: 0.92, brightness: 0.92, opacity: 0.24)
        }
    }

    /// Focus, selection, and active state. The brightest rim in the system, and
    /// deliberately reserved so that brightness always means "this one".
    static var borderEmphasis: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.95)
        case .custom: return textPrimary.opacity(0.74)
        case .classic: return Color(hue: energyHue, saturation: 0.95, brightness: 0.98, opacity: 0.42)
        }
    }

    /// Dividers inside a panel.
    static var separator: Color {
        textPrimary.opacity(mode == .contrast ? 0.28 : 0.14)
    }

    // MARK: – Light-catch and glow
    //
    // These are the decorative layer. Classic may be atmospheric because the
    // reader asked for it; Contrast and Custom get a restrained white cue or
    // nothing at all.

    static var bloom: Color { textPrimary }

    static var specularCapture: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.85)
        case .custom: return textPrimary.opacity(0.55)
        case .classic: return Color(hue: energyHue, saturation: 0.45, brightness: 1.0, opacity: 0.50)
        }
    }

    static var glassEdgeCatch: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.42)
        case .custom: return textPrimary.opacity(0.30)
        case .classic: return Color(hue: energyHue, saturation: 0.65, brightness: 0.90, opacity: 0.26)
        }
    }

    static var glassHotSpot: Color {
        switch mode {
        case .contrast: return textPrimary.opacity(0.10)
        case .custom: return textPrimary.opacity(0.08)
        case .classic: return Color(hue: energyHue, saturation: 0.90, brightness: 0.78, opacity: 0.14)
        }
    }

    static var panelGlow: Color {
        mode == .classic
            ? Color(hue: energyHue, saturation: 0.88, brightness: 0.58, opacity: 0.28)
            : textPrimary.opacity(0.24)
    }

    static var activeCardGlow: Color {
        mode == .classic
            ? Color(hue: energyHue, saturation: 0.85, brightness: 0.70, opacity: 0.40)
            : textPrimary.opacity(0.34)
    }

    // MARK: – Geometry

    static let cornerRadius: CGFloat = 10
    static let cardRadius: CGFloat = 18
    static let panelRadius: CGFloat = 22
    static let borderWidth: CGFloat = 0.5
}

private extension Color {
    /// A colour that follows the system light/dark appearance. Only Classic uses
    /// this; Contrast and Custom are explicit by design and must not silently
    /// become pale glass because the Mac switched to light mode.
    init(light: MongrelHSB, dark: MongrelHSB) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                hue: value.hue,
                saturation: value.saturation,
                brightness: value.brightness,
                alpha: 1
            )
        }))
    }
}

// MARK: – Reading surface

/// Scales definition type and leading from the reader's own preference.
///
/// Only reading surfaces take this. Interface chrome keeps its fixed sizes so a
/// reader who needs 175% definitions does not get a sidebar that no longer fits.
struct ReadingTypeModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let basePointSize: Double
    let baseLineSpacing: Double
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let metrics = appearance.readingMetrics
        return content
            .font(.system(size: metrics.readingSize(basePointSize), weight: weight, design: design))
            .lineSpacing(metrics.readingLineSpacing(baseLineSpacing))
    }
}

extension View {
    /// Applies reader-scaled type to a definition, etymology, or citation.
    func readingType(
        size: Double,
        lineSpacing: Double = 0,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(
            ReadingTypeModifier(
                basePointSize: size,
                baseLineSpacing: lineSpacing,
                weight: weight,
                design: design
            )
        )
    }
}

/// Emphasis applied to headwords and definitions.
enum ReadingBloomRole {
    case title
    case reading

    var nearRadius: CGFloat {
        switch self {
        case .title: return 2.2
        case .reading: return 1.2
        }
    }

    var farRadius: CGFloat {
        switch self {
        case .title: return 8
        case .reading: return 4
        }
    }
}

/// A restrained halo behind reading text.
///
/// This is a focus and hierarchy cue for the words the reader is trying to
/// read, not a blur applied to every label. It disappears under Reduce
/// Transparency, when the reader turns it off, and on light palettes where a
/// halo reads as smear rather than emphasis.
struct ReadingBloomModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let role: ReadingBloomRole

    @ViewBuilder
    func body(content: Content) -> some View {
        if appearance.bloomIsActive && !reduceTransparency {
            content
                .shadow(color: DesignTokens.bloom.opacity(0.28), radius: role.nearRadius)
                .shadow(color: DesignTokens.bloom.opacity(0.12), radius: role.farRadius)
        } else {
            content
        }
    }
}

extension View {
    func readingBloom(_ role: ReadingBloomRole = .reading) -> some View {
        modifier(ReadingBloomModifier(role: role))
    }
}

// MARK: – Canvas

/// The window background for every Dictionary scene.
struct DictionaryCanvasBackground: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            DesignTokens.canvas

            if !reduceTransparency {
                if appearance.mode.allowsDecorativeTint {
                    RadialGradient(
                        colors: [DesignTokens.glassHotSpot, .clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 460
                    )
                    RadialGradient(
                        colors: [DesignTokens.accent.opacity(0.06), .clear],
                        center: .bottomTrailing,
                        startRadius: 20,
                        endRadius: 520
                    )
                } else if appearance.bloomIsActive {
                    // A single soft top light, so the reading column sits in a
                    // shallow pool rather than an undifferentiated void.
                    RadialGradient(
                        colors: [
                            DesignTokens.bloom.opacity(0.055),
                            DesignTokens.bloom.opacity(0.014),
                            .clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: 420
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: – Panels and cards

/// The panel and card chrome used across the Reference Desk.
struct GlassChromeBackground: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum Style {
        /// Standard panel or sidebar surface.
        case base
        /// Toolbars and the sidebar floor.
        case deep
        /// Result cards and selectable rows.
        case card
        /// Floating sheets, popovers, and inset controls.
        case elevated
    }

    let style: Style
    let cornerRadius: CGFloat
    let glowShadow: Bool
    let isEmphasised: Bool

    func body(content: Content) -> some View {
        content
            .background(glassStack)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isEmphasised ? 1.2 : DesignTokens.borderWidth)
            )
            .shadow(
                color: glowShadow && !reduceTransparency ? DesignTokens.panelGlow : .clear,
                radius: 18,
                x: 0,
                y: 6
            )
    }

    private var glassStack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)

            if !reduceTransparency && appearance.mode.allowsDecorativeTint {
                RadialGradient(
                    colors: [DesignTokens.glassHotSpot, .clear],
                    center: .init(x: 0.28, y: 0.02),
                    startRadius: 0,
                    endRadius: style == .card ? 120 : 200
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                VStack(spacing: 0) {
                    DesignTokens.specularCapture.frame(height: 1)
                    LinearGradient(
                        colors: [DesignTokens.glassEdgeCatch, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 12)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private var fillColor: Color {
        switch style {
        case .base: return DesignTokens.glassBase
        case .deep: return DesignTokens.glassDeep
        case .card: return DesignTokens.glassCard
        case .elevated: return DesignTokens.glassElevated
        }
    }

    private var borderColor: Color {
        if isEmphasised { return DesignTokens.borderEmphasis }
        // Inset controls take the hairline; panels and cards take the
        // structural weight that makes them findable in Contrast mode.
        return style == .elevated ? DesignTokens.borderRim : DesignTokens.borderPanel
    }
}

extension View {
    func glassChromeBackground(
        style: GlassChromeBackground.Style = .base,
        cornerRadius: CGFloat = DesignTokens.cornerRadius,
        glowShadow: Bool = false,
        isEmphasised: Bool = false
    ) -> some View {
        modifier(
            GlassChromeBackground(
                style: style,
                cornerRadius: cornerRadius,
                glowShadow: glowShadow,
                isEmphasised: isEmphasised
            )
        )
    }
}

/// Selection chrome for a result card or list row.
///
/// Selection is carried by three independent cues — a leading accent stripe, a
/// brighter rim, and a changed fill — so it survives if the reader cannot
/// distinguish the fill from its neighbour.
struct SelectedSurfaceModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(DesignTokens.selectionFill)
                }
            }
            // The stripe and the rim are overlays rather than background
            // layers, so they stay visible when the modifier is applied to a
            // surface that already paints an opaque fill of its own.
            .overlay(alignment: .leading) {
                if isSelected {
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(DesignTokens.accent)
                    .frame(width: 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignTokens.borderEmphasis : .clear,
                        lineWidth: isSelected ? 1.4 : 0
                    )
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
    }
}

extension View {
    func selectedSurface(isSelected: Bool, cornerRadius: CGFloat = DesignTokens.cardRadius) -> some View {
        modifier(SelectedSurfaceModifier(isSelected: isSelected, cornerRadius: cornerRadius))
    }

    /// Result-card chrome from the suite handoff: a glass fill, a selection
    /// stripe, and a restrained lift. Contrast keeps the fill at canvas black
    /// and relies on the stripe plus rim.
    func glassCard(isSelected: Bool = false, cornerRadius: CGFloat = DesignTokens.cardRadius) -> some View {
        glassChromeBackground(style: .card, cornerRadius: cornerRadius, isEmphasised: isSelected)
            .selectedSurface(isSelected: isSelected, cornerRadius: cornerRadius)
            .hoverBloom(cornerRadius: cornerRadius)
    }
}

/// Pointer feedback for rows and buttons. Motion is a clarification of state,
/// so it is dropped entirely under Reduce Motion rather than merely shortened.
struct HoverBloomModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? DesignTokens.hoverBloom : .clear)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverBloom(cornerRadius: CGFloat = 7) -> some View {
        modifier(HoverBloomModifier(cornerRadius: cornerRadius))
    }
}

// MARK: – Query highlighting

enum DictionaryTextHighlighter {
    /// Marks every occurrence of `term` inside `text`.
    ///
    /// The mark is a palette-derived fill plus an underline: two cues, neither
    /// of them a fixed hue, so a match stays findable in Contrast, on Warm
    /// Paper, and inside a badly chosen custom pair. A fixed yellow would be
    /// invisible on one of those three.
    static func highlight(_ text: String, matching term: String) -> AttributedString {
        var attributed = AttributedString(text)
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2, text.count <= 4_000 else { return attributed }

        var marker = AttributeContainer()
        marker.swiftUI.backgroundColor = DesignTokens.highlightFill
        marker.swiftUI.underlineStyle = .single

        var searchRange = attributed.startIndex..<attributed.endIndex
        var matchCount = 0
        while matchCount < 64,
              let found = attributed[searchRange].range(of: needle, options: [.caseInsensitive]) {
            attributed[found].mergeAttributes(marker)
            guard found.upperBound < attributed.endIndex else { break }
            searchRange = found.upperBound..<attributed.endIndex
            matchCount += 1
        }

        return attributed
    }
}
