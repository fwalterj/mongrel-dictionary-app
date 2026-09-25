import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLexicalBehaviorDeepSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .deepShared }
    override class var repositoryScopeKey: String { "deep.shared" }

    func testSynonymModePrefersThesaurusOrPivotSources() async {
        let repository = await makeRepository()
        let cards = await repository.synonymAvailabilityProbe(term: "bright")

        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Thesaurus availability probe" &&
                $0.summary.localizedCaseInsensitiveContains("thesaurus backing")
            }),
            "Expected a common lemma to have direct backing in the packaged thesaurus archives."
        )
    }
}
