import XCTest
@testable import MongrelDictionaryCore

/// Guards the appearance contract described in `ACCESSIBILITY.md`.
///
/// These are not decorative assertions. Each one corresponds to a way the
/// application could quietly become unreadable: a preset shipped below the
/// ordinary-text threshold, Contrast mode drifting into charcoal, or a clean
/// install opening in the brand palette instead of the accessible default.
final class AppearanceContrastTests: XCTestCase {
    func testContrastPageDefaultsAndRoundTrips() {
        XCTAssertEqual(MongrelContrastPage.storedValue(nil), .black)
        XCTAssertEqual(MongrelContrastPage.storedValue("unknown"), .black)
        for page in MongrelContrastPage.allCases {
            XCTAssertEqual(MongrelContrastPage.storedValue(page.rawValue), page)
            XCTAssertEqual(MongrelContrast.ratio(background: page.background, text: page.text), 21, accuracy: 0.001)
        }
        XCTAssertEqual(MongrelContrastPage.white.background, .white)
        XCTAssertEqual(MongrelContrastPage.white.text, .black)
    }

    // MARK: – Contrast arithmetic

    func testMaximumContrastIsTwentyOneToOne() {
        let ratio = MongrelContrast.ratio(background: .black, text: .white)
        XCTAssertEqual(ratio, 21, accuracy: 0.001)
    }

    func testIdenticalColoursHaveNoContrast() {
        let colour = MongrelHSB(degrees: 210, saturation: 0.4, brightness: 0.5)
        XCTAssertEqual(MongrelContrast.ratio(background: colour, text: colour), 1, accuracy: 0.001)
    }

    func testRatioIsSymmetric() {
        let page = MongrelHSB(degrees: 42, saturation: 0.12, brightness: 0.96)
        let ink = MongrelHSB(degrees: 24, saturation: 0.25, brightness: 0.12)

        XCTAssertEqual(
            MongrelContrast.ratio(background: page, text: ink),
            MongrelContrast.ratio(background: ink, text: page),
            accuracy: 0.001
        )
    }

    func testGradeBoundariesMatchTheAccessibilityContract() {
        XCTAssertEqual(MongrelContrast.grade(21), .enhanced)
        XCTAssertEqual(MongrelContrast.grade(7), .enhanced)
        XCTAssertEqual(MongrelContrast.grade(6.9), .ordinary)
        XCTAssertEqual(MongrelContrast.grade(4.5), .ordinary)
        XCTAssertEqual(MongrelContrast.grade(4.4), .largeTextOnly)
        XCTAssertEqual(MongrelContrast.grade(3), .largeTextOnly)
        XCTAssertEqual(MongrelContrast.grade(2.9), .insufficient)
        XCTAssertEqual(MongrelContrast.grade(1), .insufficient)
    }

    /// Supporting text may only be dimmed where the pairing has headroom.
    func testOnlyReadablePairingsPermitDimmedSupportingText() {
        XCTAssertTrue(MongrelContrast.grade(21).allowsDimmedText)
        XCTAssertTrue(MongrelContrast.grade(4.5).allowsDimmedText)
        XCTAssertFalse(MongrelContrast.grade(3.5).allowsDimmedText)
        XCTAssertFalse(MongrelContrast.grade(1.2).allowsDimmedText)
    }

    // MARK: – Modes

    func testContrastModeIsGenuinelyBlackAndWhite() throws {
        let background = try XCTUnwrap(MongrelAppearanceMode.contrast.fixedBackground)
        let text = try XCTUnwrap(MongrelAppearanceMode.contrast.fixedText)

        XCTAssertEqual(background, .black)
        XCTAssertEqual(text, .white)
        XCTAssertEqual(MongrelContrast.ratio(background: background, text: text), 21, accuracy: 0.001)
    }

    func testClassicModeStaysReadableDespiteCarryingTheBrandPalette() throws {
        let background = try XCTUnwrap(MongrelAppearanceMode.classic.fixedBackground)
        let text = try XCTUnwrap(MongrelAppearanceMode.classic.fixedText)

        XCTAssertGreaterThanOrEqual(
            MongrelContrast.ratio(background: background, text: text),
            7,
            "Classic is optional branding, but it is still a reading surface."
        )
    }

    func testCustomModeDefinesNoFixedPalette() {
        XCTAssertNil(MongrelAppearanceMode.custom.fixedBackground)
        XCTAssertNil(MongrelAppearanceMode.custom.fixedText)
    }

    func testOnlyClassicPermitsDecorativeTint() {
        XCTAssertTrue(MongrelAppearanceMode.classic.allowsDecorativeTint)
        XCTAssertFalse(MongrelAppearanceMode.contrast.allowsDecorativeTint)
        XCTAssertFalse(MongrelAppearanceMode.custom.allowsDecorativeTint)
    }

    func testMissingModeDefaultsToContrast() {
        XCTAssertEqual(MongrelAppearanceMode.storedValue(nil), .contrast)
    }

    func testUnrecognisedModeFallsBackToContrast() {
        XCTAssertEqual(MongrelAppearanceMode.storedValue("chartreuse"), .contrast)
    }

    func testLegacyStandardModeMigratesToClassic() {
        XCTAssertEqual(MongrelAppearanceMode.storedValue("standard"), .classic)
    }

    func testEveryModeRoundTripsThroughItsStoredValue() {
        for mode in MongrelAppearanceMode.allCases {
            XCTAssertEqual(MongrelAppearanceMode.storedValue(mode.rawValue), mode)
        }
    }

    // MARK: – Migration from Dictionary's two-theme preference

    func testLegacyBloomThemeBecomesContrastWithHalo() throws {
        let migrated = try XCTUnwrap(MongrelLegacyDictionaryTheme.migrate("deep-black-bloom"))
        XCTAssertEqual(migrated.mode, .contrast)
        XCTAssertTrue(migrated.bloomEnabled)
    }

    func testLegacyCrispThemeBecomesContrastWithoutHalo() throws {
        let migrated = try XCTUnwrap(MongrelLegacyDictionaryTheme.migrate("deep-black-crisp"))
        XCTAssertEqual(migrated.mode, .contrast)
        XCTAssertFalse(migrated.bloomEnabled)
    }

    func testCleanInstallHasNothingToMigrate() {
        XCTAssertNil(MongrelLegacyDictionaryTheme.migrate(nil))
        XCTAssertNil(MongrelLegacyDictionaryTheme.migrate("deep-black-unknown"))
    }

    // MARK: – Bundled presets

    func testEveryPresetMeetsOrdinaryTextContrast() {
        for preset in MongrelColorPreset.all {
            XCTAssertGreaterThanOrEqual(
                preset.contrastRatio,
                4.5,
                "\(preset.title) ships below the ordinary-text threshold."
            )
        }
    }

    func testPresetIdentifiersAndTitlesAreUnique() {
        XCTAssertEqual(Set(MongrelColorPreset.all.map(\.id)).count, MongrelColorPreset.all.count)
        XCTAssertEqual(Set(MongrelColorPreset.all.map(\.title)).count, MongrelColorPreset.all.count)
    }

    /// Somebody reading in daylight needs a light page, and somebody reading at
    /// night needs a dark one. Shipping only one of those is not a choice.
    func testPresetsCoverBothLightAndDarkPages() {
        let luminances = MongrelColorPreset.all.map(\.background.relativeLuminance)
        XCTAssertTrue(luminances.contains { $0 > 0.45 }, "No light-page preset is bundled.")
        XCTAssertTrue(luminances.contains { $0 < 0.1 }, "No dark-page preset is bundled.")
    }

    func testEveryPresetExplainsItselfInWords() {
        for preset in MongrelColorPreset.all {
            XCTAssertFalse(
                preset.detail.isEmpty,
                "\(preset.title) offers no non-colour description."
            )
        }
    }

    // MARK: – Surface derivation

    /// Elevation has to move away from the canvas, not always toward white.
    /// Brightening a Warm Paper surface makes it vanish into the page.
    func testElevationMovesAwayFromTheCanvasInBothDirections() {
        let darkCanvas = MongrelHSB(degrees: 222, saturation: 0.42, brightness: 0.05)
        let lightCanvas = MongrelHSB(degrees: 42, saturation: 0.12, brightness: 0.96)

        XCTAssertGreaterThan(darkCanvas.elevated(by: 0.1).brightness, darkCanvas.brightness)
        XCTAssertLessThan(lightCanvas.elevated(by: 0.1).brightness, lightCanvas.brightness)
    }

    func testComponentsStayInsideTheUnitRange() {
        XCTAssertEqual(MongrelHSB(hue: 2, saturation: -1, brightness: 5).hue, 1)
        XCTAssertEqual(MongrelHSB(hue: 2, saturation: -1, brightness: 5).saturation, 0)
        XCTAssertEqual(MongrelHSB(hue: 2, saturation: -1, brightness: 5).brightness, 1)
        XCTAssertEqual(MongrelHSB.white.lightened(by: 0.5).brightness, 1)
        XCTAssertEqual(MongrelHSB.black.darkened(by: 0.5).brightness, 0)
    }

    func testGreyscaleLuminanceIsMonotonic() throws {
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map {
            MongrelHSB(hue: 0, saturation: 0, brightness: $0).relativeLuminance
        }
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(try XCTUnwrap(steps.first), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(steps.last), 1, accuracy: 0.0001)
    }
}

/// Reader-controlled type size is independent of the palette, so it gets its
/// own coverage: a reader who needs 175% definitions must not be pushed into a
/// different colour scheme to obtain them.
final class ReadingMetricsTests: XCTestCase {

    func testStandardMetricsLeaveTypeUntouched() {
        let metrics = DictionaryReadingMetrics.standard
        XCTAssertEqual(metrics.readingSize(15.5), 15.5, accuracy: 0.001)
        XCTAssertEqual(metrics.readingLineSpacing(5), 5, accuracy: 0.001)
        XCTAssertFalse(metrics.isCustomised)
    }

    func testTextScaleGrowsReadingType() {
        let metrics = DictionaryReadingMetrics(textScale: 1.5, lineSpacingScale: 1)
        XCTAssertEqual(metrics.readingSize(16), 24, accuracy: 0.001)
        XCTAssertTrue(metrics.isCustomised)
    }

    /// Leading compounds with type size, because large type on tight leading is
    /// harder to read than the same type at its original size.
    func testLineSpacingCompoundsWithTextScale() {
        let metrics = DictionaryReadingMetrics(textScale: 1.5, lineSpacingScale: 1.5)
        XCTAssertEqual(metrics.readingLineSpacing(4), 9, accuracy: 0.001)
    }

    func testScalesAreClampedToSupportedRange() {
        let tooSmall = DictionaryReadingMetrics(textScale: 0.1, lineSpacingScale: 0.1)
        XCTAssertEqual(tooSmall.textScale, DictionaryReadingMetrics.textScaleRange.lowerBound)
        XCTAssertEqual(tooSmall.lineSpacingScale, DictionaryReadingMetrics.lineSpacingScaleRange.lowerBound)

        let tooLarge = DictionaryReadingMetrics(textScale: 9, lineSpacingScale: 9)
        XCTAssertEqual(tooLarge.textScale, DictionaryReadingMetrics.textScaleRange.upperBound)
        XCTAssertEqual(tooLarge.lineSpacingScale, DictionaryReadingMetrics.lineSpacingScaleRange.upperBound)
    }

    func testSupportedRangeReachesAtLeastOneAndAHalfTimesNormal() {
        XCTAssertGreaterThanOrEqual(DictionaryReadingMetrics.textScaleRange.upperBound, 1.5)
        XCTAssertLessThanOrEqual(DictionaryReadingMetrics.textScaleRange.lowerBound, 1)
    }

    func testLabelsReportWholePercentages() {
        let metrics = DictionaryReadingMetrics(textScale: 1.25, lineSpacingScale: 1.4)
        XCTAssertEqual(metrics.textScaleLabel, "125%")
        XCTAssertEqual(metrics.lineSpacingLabel, "140%")
    }
}
