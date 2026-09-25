import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLexicalIngestionDeepSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .deepShared }
    override class var repositoryScopeKey: String { "deep.shared" }

    func testClassicWordNetProbeReturnsCommonLemmaCard() async {
        let repository = await makeRepository()
        let cards = await repository.wordNetClassicProbe(term: "dog")

        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(
            cards.contains(where: { $0.source == "WordNet 3.x (Princeton dict)" }),
            "Expected a classic WordNet card for a common lemma to verify classic dict ingestion."
        )
    }
}
