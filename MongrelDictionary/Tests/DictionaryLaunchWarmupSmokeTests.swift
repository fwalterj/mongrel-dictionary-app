import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLaunchWarmupSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .launchSearch }

    func testLaunchSearchPrewarmWarmsOnlyInstantLookupLanes() async {
        let repository = await makeRepository()
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(diagnostics.loadedIndices.contains("Fast lookup"))
        XCTAssertTrue(diagnostics.loadedIndices.contains("Synonym lookup"))
        XCTAssertTrue(diagnostics.loadedIndices.contains("Translation lookup"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Reference notes store"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Search lexicon"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Regional English"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Aussie dictionary"))

        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet 2025"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet classic"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("FreeDict"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("ZA Mafoko"))
    }
}
