import XCTest
@testable import MongrelDictionaryCore

final class DictionaryTranslationFallbackLatencySmokeTests: XCTestCase {
    func testTranslationFallbackSkipsHeavyBilingualLoadsWhenDigestMisses() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "lekker", intent: .translation)
        let diagnostics = await repository.diagnostics()
        let sourceNames = diagnostics.lastSearchProfile?.sourceTimings.map(\.name) ?? []

        XCTAssertFalse(cards.isEmpty, "Expected translation mode to fall back to local context for 'lekker'.")
        XCTAssertFalse(
            diagnostics.loadedIndices.contains("FreeDict"),
            "A translation digest miss should not load the full FreeDict payload when the packaged bilingual digest is available."
        )
        XCTAssertFalse(
            diagnostics.loadedIndices.contains("ZA Mafoko"),
            "A translation digest miss should not load the full ZA Mafoko payload when the packaged bilingual digest is available."
        )
        XCTAssertFalse(
            sourceNames.contains("Regional English wordlists"),
            "A translation digest miss should stay on the lightweight context path instead of loading the bulky regional wordlist index."
        )
        XCTAssertFalse(
            sourceNames.contains("WordNet 2025"),
            "A translation digest miss should not fall back to the heavyweight WordNet 2025 index when lightweight local context is available."
        )
        XCTAssertFalse(
            sourceNames.contains("WordNet classic"),
            "A translation digest miss should not fall back to the heavyweight classic WordNet index when lightweight local context is available."
        )
    }
}
