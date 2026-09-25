import MongrelDictionaryCore
import SwiftUI

struct DictionarySettingsView: View {
    var body: some View {
        TabView {
            DictionaryAppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

            DictionaryReadingSettingsView()
                .tabItem {
                    Label("Reading", systemImage: "textformat.size")
                }
        }
        .frame(width: 540, height: 620)
    }
}

// MARK: – Appearance

struct DictionaryAppearanceSettingsView: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some View {
        Form {
            Section("Viewing mode") {
                Picker("Viewing mode", selection: $appearance.mode) {
                    ForEach(MongrelAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(appearance.mode.detail)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appearance.mode == .contrast {
                Section("Contrast page") {
                    Picker("Page", selection: $appearance.contrastPage) {
                        ForEach(MongrelContrastPage.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Black is the default. White uses black type on a white page.")
                }
            }

            Section("Reading emphasis") {
                Toggle("Halo behind headwords and definitions", isOn: $appearance.bloomEnabled)
                Text(bloomExplanation)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appearance.mode == .custom {
                Section("Readable palettes") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(MongrelColorPreset.all) { preset in
                            presetButton(preset)
                        }
                    }
                }

                Section("Colours") {
                    ColorPicker("Background", selection: backgroundBinding, supportsOpacity: false)
                    ColorPicker("Text and cues", selection: textBinding, supportsOpacity: false)

                    DisclosureGroup("Fine tune") {
                        colorControls(
                            title: "Background",
                            hue: $appearance.backgroundHue,
                            saturation: $appearance.backgroundSaturation,
                            brightness: $appearance.backgroundBrightness,
                            preview: appearance.background
                        )
                        Divider()
                        colorControls(
                            title: "Text and cues",
                            hue: $appearance.textHue,
                            saturation: $appearance.textSaturation,
                            brightness: $appearance.textBrightness,
                            preview: appearance.text
                        )
                    }
                }
            }

            Section("Preview") {
                DictionaryAppearancePreview()

                LabeledContent("Contrast ratio") {
                    Text(String(format: "%.1f:1", appearance.contrastRatio))
                        .monospacedDigit()
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(
                        appearance.contrastGrade.summary,
                        systemImage: contrastStatusSymbol
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if appearance.contrastRatio < 7 {
                        Button("Maximum contrast") {
                            appearance.useMaximumContrast()
                        }
                        .controlSize(.small)
                        .help("Switch to pure white text on a pure black background.")
                    }
                }
            }

            Section {
                Button("Restore suite defaults") {
                    appearance.reset()
                }
                .help("Return to Contrast mode with the shipped reading sizes.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .mongrelAppearance()
    }

    private var bloomExplanation: String {
        if appearance.prefersLightChrome {
            return "A halo would read as smear on a light page, so it stays off while this palette is active."
        }
        return "A restrained glow marks the words you are reading. Turn it off if glow reads as halation."
    }

    /// The grade carries a symbol as well as wording, so the assessment is not
    /// delivered by colour alone.
    private var contrastStatusSymbol: String {
        switch appearance.contrastGrade {
        case .enhanced: return "checkmark.circle.fill"
        case .ordinary: return "checkmark.circle"
        case .largeTextOnly: return "exclamationmark.triangle"
        case .insufficient: return "xmark.octagon"
        }
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { appearance.background },
            set: { appearance.updateBackground(from: $0) }
        )
    }

    private var textBinding: Binding<Color> {
        Binding(
            get: { appearance.text },
            set: { appearance.updateText(from: $0) }
        )
    }

    private func presetButton(_ preset: MongrelColorPreset) -> some View {
        Button {
            appearance.apply(preset)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Color(preset.background))
                    Text("A")
                        .font(.caption.bold())
                        .foregroundStyle(Color(preset.text))
                }
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(DesignTokens.borderRim))

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .lineLimit(1)
                    Text(String(format: "%.0f:1", preset.contrastRatio))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.textMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
            .glassChromeBackground(style: .card, cornerRadius: 8, isEmphasised: isActive(preset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title) palette. \(preset.detail)")
        .accessibilityValue(String(format: "%.0f to 1 contrast", preset.contrastRatio))
        .help(preset.detail)
    }

    private func isActive(_ preset: MongrelColorPreset) -> Bool {
        appearance.mode == .custom
            && appearance.backgroundValue == preset.background
            && appearance.textValue == preset.text
    }

    private func colorControls(
        title: String,
        hue: Binding<Double>,
        saturation: Binding<Double>,
        brightness: Binding<Double>,
        preview: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LabeledContent(title) {
                Circle()
                    .fill(preview)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(DesignTokens.borderRim))
            }
            AppearanceSlider(
                title: "Hue",
                value: hue,
                gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red])
            )
            AppearanceSlider(
                title: "Saturation",
                value: saturation,
                gradient: Gradient(colors: [.gray, preview])
            )
            AppearanceSlider(
                title: "Brightness",
                value: brightness,
                gradient: Gradient(colors: [.black, preview, .white])
            )
        }
        .padding(.vertical, 5)
    }
}

private struct AppearanceSlider: View {
    let title: String
    @Binding var value: Double
    var gradient: Gradient?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textMuted)
            }
            .font(.caption)

            Slider(value: $value, in: 0...1)
                .tint(gradient?.stops.last?.color ?? DesignTokens.accent)
                .background {
                    if let gradient {
                        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                            .clipShape(Capsule())
                            .opacity(0.55)
                            .padding(.vertical, 6)
                    }
                }
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value * 100)) percent")
        }
    }
}

/// Shows the active palette against the roles Dictionary actually uses, so the
/// reader is judging headwords and definitions rather than an abstract swatch.
private struct DictionaryAppearancePreview: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("lacuna")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(DesignTokens.textPrimary)
                .readingBloom(.title)

            HStack(spacing: 8) {
                Label("noun", systemImage: "text.book.closed")
                Label("Core English", systemImage: "building.columns")
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)

            Text(DictionaryTextHighlighter.highlight(
                "An unfilled space or interval; a gap. A missing portion in a manuscript, leaving a lacuna in the argument.",
                matching: "lacuna"
            ))
            .readingType(size: 14, lineSpacing: 4)
            .foregroundStyle(DesignTokens.textPrimary)
            .readingBloom(.reading)
            .fixedSize(horizontal: false, vertical: true)

            Text("Selected result")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .selectedSurface(isSelected: true, cornerRadius: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.borderRim))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette preview")
    }
}

// MARK: – Reading

struct DictionaryReadingSettingsView: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some View {
        Form {
            Section("Definition type") {
                stepperRow(
                    title: "Text size",
                    value: appearance.readingMetrics.textScaleLabel,
                    binding: $appearance.readingTextScale,
                    range: DictionaryReadingMetrics.textScaleRange,
                    step: 0.05
                )

                stepperRow(
                    title: "Line spacing",
                    value: appearance.readingMetrics.lineSpacingLabel,
                    binding: $appearance.readingLineSpacingScale,
                    range: DictionaryReadingMetrics.lineSpacingScaleRange,
                    step: 0.05
                )

                Text("These apply to headwords, definitions, and citations only. The sidebar, badges, and toolbar keep their sizes so the window stays usable at large reading sizes.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("palimpsest")
                        .readingType(size: 30, weight: .semibold, design: .serif)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .readingBloom(.title)

                    Text("Something reused or altered but still bearing visible traces of its earlier form. A manuscript page from which earlier writing has been scraped away to make room for later writing.")
                        .readingType(size: 15.5, lineSpacing: 5)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .readingBloom(.reading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassChromeBackground(style: .card, cornerRadius: DesignTokens.cardRadius)
            }

            Section {
                Button("Restore shipped reading sizes") {
                    appearance.resetReadingMetrics()
                }
                .disabled(!appearance.readingMetrics.isCustomised)
            } footer: {
                Text("Command-Plus and Command-Minus adjust reading size from any window.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textMuted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .mongrelAppearance()
    }

    private func stepperRow(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            HStack(spacing: 10) {
                Slider(value: binding, in: range, step: step)
                    .accessibilityLabel(title)
                    .accessibilityValue(value)

                Stepper(title, value: binding, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}
