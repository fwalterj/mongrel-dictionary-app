import XCTest
@testable import MongrelDictionaryCore

final class DictionarySynonymFallbackLatencySmokeTests: XCTestCase {
    func testSynonymFallbackSkipsHeavyThesaurusLoadsWhenOnlyReferenceFallbacksCanRespond() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "lekker", intent: .synonyms)
        let diagnostics = await repository.diagnostics()

        XCTAssertFalse(cards.isEmpty, "Expected synonym mode to fall back to a local non-thesaurus result for 'lekker'.")
        XCTAssertFalse(
            diagnostics.loadedIndices.contains("OpenOffice thesaurus"),
            "A clear thesaurus miss should not load the full OpenOffice thesaurus archive."
        )
        XCTAssertFalse(
            diagnostics.loadedIndices.contains("Moby thesaurus"),
            "A clear thesaurus miss should not load the full Moby thesaurus archive."
        )
    }
}
