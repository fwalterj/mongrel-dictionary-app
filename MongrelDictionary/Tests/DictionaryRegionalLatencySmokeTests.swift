import XCTest
@testable import MongrelDictionaryCore

final class DictionaryRegionalLatencySmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .none }

    func testVariantDefineSearchAvoidsHeavyWordNetLoads() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "colour", intent: .define)
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Regional spelling note" &&
                $0.summary.localizedCaseInsensitiveContains("spelling variant of 'color'")
            }),
            "Expected a regional spelling card to explain the Commonwealth spelling 'colour'."
        )
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(diagnostics.loadedIndices.contains("Fast lookup"))
        XCTAssertTrue(diagnostics.loadedIndices.contains("Regional English"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet 2025"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet classic"))
    }
}
