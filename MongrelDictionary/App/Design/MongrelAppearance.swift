import AppKit
import MongrelDictionaryCore
import SwiftUI

extension Color {
    init(_ value: MongrelHSB) {
        self.init(hue: value.hue, saturation: value.saturation, brightness: value.brightness)
    }
}

/// The persisted appearance and reading state for the whole application.
///
/// Marked `@unchecked Sendable` on purpose: `DesignTokens` reads this store from
/// nonisolated static properties so views can ask for a semantic colour without
/// threading an environment value through every layer. All mutation happens from
/// the settings and menu surfaces, which are main-actor bound.
final class MongrelAppearancePreferences: ObservableObject, @unchecked Sendable {
    static let shared = MongrelAppearancePreferences()

    static let modeKey = "mongrelAppearanceMode"
    static let contrastPageKey = "mongrelContrastPage"
    static let bloomKey = "mongrelReadingBloomEnabled"
    static let backgroundHueKey = "mongrelCustomBackgroundHue"
    static let backgroundSaturationKey = "mongrelCustomBackgroundSaturation"
    static let backgroundBrightnessKey = "mongrelCustomBackgroundBrightness"
    static let textHueKey = "mongrelCustomTextHue"
    static let textSaturationKey = "mongrelCustomTextSaturation"
    static let textBrightnessKey = "mongrelCustomTextBrightness"
    static let readingTextScaleKey = "mongrelReadingTextScale"
    static let readingLineSpacingScaleKey = "mongrelReadingLineSpacingScale"

    static let allKeys = [
        modeKey,
        contrastPageKey,
        bloomKey,
        backgroundHueKey,
        backgroundSaturationKey,
        backgroundBrightnessKey,
        textHueKey,
        textSaturationKey,
        textBrightnessKey,
        readingTextScaleKey,
        readingLineSpacingScaleKey
    ]

    private let defaults: UserDefaults

    @Published var mode: MongrelAppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }

    @Published var contrastPage: MongrelContrastPage {
        didSet { defaults.set(contrastPage.rawValue, forKey: Self.contrastPageKey) }
    }

    /// A restrained halo on headwords and definitions. It is a focus cue, not a
    /// blur applied to every label, and readers who see glow as halation can
    /// switch it off without leaving their palette.
    @Published var bloomEnabled: Bool {
        didSet { defaults.set(bloomEnabled, forKey: Self.bloomKey) }
    }

    @Published var backgroundHue: Double {
        didSet { defaults.set(backgroundHue, forKey: Self.backgroundHueKey) }
    }

    @Published var backgroundSaturation: Double {
        didSet { defaults.set(backgroundSaturation, forKey: Self.backgroundSaturationKey) }
    }

    @Published var backgroundBrightness: Double {
        didSet { defaults.set(backgroundBrightness, forKey: Self.backgroundBrightnessKey) }
    }

    @Published var textHue: Double {
        didSet { defaults.set(textHue, forKey: Self.textHueKey) }
    }

    @Published var textSaturation: Double {
        didSet { defaults.set(textSaturation, forKey: Self.textSaturationKey) }
    }

    @Published var textBrightness: Double {
        didSet { defaults.set(textBrightness, forKey: Self.textBrightnessKey) }
    }

    @Published var readingTextScale: Double {
        didSet { defaults.set(readingTextScale, forKey: Self.readingTextScaleKey) }
    }

    @Published var readingLineSpacingScale: Double {
        didSet { defaults.set(readingLineSpacingScale, forKey: Self.readingLineSpacingScaleKey) }
    }

    private init(defaults: UserDefaults = DictionaryPreferences.current) {
        self.defaults = defaults

        let legacy = MongrelLegacyDictionaryTheme.migrate(
            defaults.string(forKey: MongrelLegacyDictionaryTheme.storageKey)
        )
        let storedMode = defaults.string(forKey: Self.modeKey)

        mode = storedMode == nil ? (legacy?.mode ?? .contrast) : MongrelAppearanceMode.storedValue(storedMode)
        contrastPage = .storedValue(defaults.string(forKey: Self.contrastPageKey))
        bloomEnabled = defaults.object(forKey: Self.bloomKey) as? Bool ?? legacy?.bloomEnabled ?? true

        let fallbackCustom = MongrelColorPreset.all[0]
        backgroundHue = defaults.object(forKey: Self.backgroundHueKey) as? Double ?? fallbackCustom.background.hue
        backgroundSaturation = defaults.object(forKey: Self.backgroundSaturationKey) as? Double
            ?? fallbackCustom.background.saturation
        backgroundBrightness = defaults.object(forKey: Self.backgroundBrightnessKey) as? Double
            ?? fallbackCustom.background.brightness
        textHue = defaults.object(forKey: Self.textHueKey) as? Double ?? fallbackCustom.text.hue
        textSaturation = defaults.object(forKey: Self.textSaturationKey) as? Double ?? fallbackCustom.text.saturation
        textBrightness = defaults.object(forKey: Self.textBrightnessKey) as? Double ?? fallbackCustom.text.brightness

        readingTextScale = defaults.object(forKey: Self.readingTextScaleKey) as? Double ?? 1
        readingLineSpacingScale = defaults.object(forKey: Self.readingLineSpacingScaleKey) as? Double ?? 1
    }

    // MARK: – Resolved palette

    var backgroundValue: MongrelHSB {
        if mode == .contrast { return contrastPage.background }
        return mode.fixedBackground ?? MongrelHSB(
            hue: backgroundHue,
            saturation: backgroundSaturation,
            brightness: backgroundBrightness
        )
    }

    var textValue: MongrelHSB {
        if mode == .contrast { return contrastPage.text }
        return mode.fixedText ?? MongrelHSB(hue: textHue, saturation: textSaturation, brightness: textBrightness)
    }

    var background: Color { Color(backgroundValue) }
    var text: Color { Color(textValue) }

    var contrastRatio: Double {
        MongrelContrast.ratio(background: backgroundValue, text: textValue)
    }

    var contrastGrade: MongrelContrast.Grade {
        MongrelContrast.grade(contrastRatio)
    }

    /// Whether the active palette is a light page. Drives `preferredColorScheme`
    /// so system controls stop drawing dark chrome on a Warm Paper background.
    var prefersLightChrome: Bool {
        backgroundValue.relativeLuminance > 0.45
    }

    var preferredColorScheme: ColorScheme {
        prefersLightChrome ? .light : .dark
    }

    /// Bloom is only meaningful where the text is near-monochrome against a dark
    /// canvas. On a light page a halo turns into smear, so it is suppressed.
    var bloomIsActive: Bool {
        bloomEnabled && !prefersLightChrome
    }

    var readingMetrics: DictionaryReadingMetrics {
        DictionaryReadingMetrics(textScale: readingTextScale, lineSpacingScale: readingLineSpacingScale)
    }

    /// A stable identity for the whole appearance. AppKit-backed surfaces and
    /// any cached drawing can include this in their update identity to know
    /// when a repaint is genuinely required.
    var themeRevisionToken: String {
        String(
            format: "%@-%@-%.4f-%.4f-%.4f-%.4f-%.4f-%.4f-%.3f-%.3f",
            mode.rawValue,
            bloomEnabled ? "bloom" : "crisp",
            backgroundValue.hue, backgroundValue.saturation, backgroundValue.brightness,
            textValue.hue, textValue.saturation, textValue.brightness,
            readingTextScale, readingLineSpacingScale
        )
    }

    // MARK: – Mutation

    func apply(_ preset: MongrelColorPreset) {
        backgroundHue = preset.background.hue
        backgroundSaturation = preset.background.saturation
        backgroundBrightness = preset.background.brightness
        textHue = preset.text.hue
        textSaturation = preset.text.saturation
        textBrightness = preset.text.brightness
        mode = .custom
    }

    /// One-click recovery from a custom pair the reader can no longer read.
    func useMaximumContrast() {
        backgroundHue = 0
        backgroundSaturation = 0
        backgroundBrightness = 0
        textHue = 0
        textSaturation = 0
        textBrightness = 1
        mode = .custom
    }

    func resetReadingMetrics() {
        readingTextScale = 1
        readingLineSpacingScale = 1
    }

    func reset() {
        Self.allKeys.forEach { defaults.removeObject(forKey: $0) }
        let fallback = MongrelColorPreset.all[0]
        backgroundHue = fallback.background.hue
        backgroundSaturation = fallback.background.saturation
        backgroundBrightness = fallback.background.brightness
        textHue = fallback.text.hue
        textSaturation = fallback.text.saturation
        textBrightness = fallback.text.brightness
        readingTextScale = 1
        readingLineSpacingScale = 1
        bloomEnabled = true
        contrastPage = .black
        mode = .contrast
    }

    func adjustReadingTextScale(by delta: Double) {
        let range = DictionaryReadingMetrics.textScaleRange
        readingTextScale = min(range.upperBound, max(range.lowerBound, readingTextScale + delta))
    }

    func updateBackground(from color: Color) {
        guard let components = Self.hsb(from: color) else { return }
        backgroundHue = components.hue
        backgroundSaturation = components.saturation
        backgroundBrightness = components.brightness
        mode = .custom
    }

    func updateText(from color: Color) {
        guard let components = Self.hsb(from: color) else { return }
        textHue = components.hue
        textSaturation = components.saturation
        textBrightness = components.brightness
        mode = .custom
    }

    private static func hsb(from color: Color) -> MongrelHSB? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return MongrelHSB(hue: hue, saturation: saturation, brightness: brightness)
    }
}

// MARK: – Environment

private struct ThemeRevisionKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// Changes whenever any appearance or reading preference changes.
    ///
    /// SwiftUI colours alone will not update AppKit-backed text, WebKit
    /// content, or custom drawing. Those surfaces should include this in their
    /// update identity and repaint from the semantic tokens when it changes.
    var mongrelThemeRevision: String {
        get { self[ThemeRevisionKey.self] }
        set { self[ThemeRevisionKey.self] = newValue }
    }
}

// MARK: – Root modifier

private struct MongrelAppearanceModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    func body(content: Content) -> some View {
        content
            .background(DesignTokens.canvas.ignoresSafeArea())
            .tint(DesignTokens.accent)
            .preferredColorScheme(appearance.preferredColorScheme)
            .environment(\.mongrelThemeRevision, appearance.themeRevisionToken)
            .onAppear(perform: paintWindows)
            .onChange(of: appearance.themeRevisionToken) { _, _ in
                paintWindows()
            }
    }

    /// AppKit windows do not follow SwiftUI canvas colours on their own.
    /// Painting the titlebar and window floor keeps Contrast, Classic, and
    /// Custom from leaking the system chrome around the reading surface.
    private func paintWindows() {
        let background = NSColor(appearance.background)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.backgroundColor = background
                window.titlebarAppearsTransparent = true
                window.isOpaque = appearance.mode != .classic
            }
        }
    }
}

extension View {
    /// Applies the suite appearance contract. Every top-level window, settings
    /// scene, and auxiliary window must carry this.
    func mongrelAppearance() -> some View {
        modifier(MongrelAppearanceModifier())
    }
}
