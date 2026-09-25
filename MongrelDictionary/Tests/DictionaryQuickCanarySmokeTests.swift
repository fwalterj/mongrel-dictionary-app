import XCTest
@testable import MongrelDictionaryCore

final class DictionaryQuickCanarySmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .referenceNotes }

    func testQuickCanariesCoverInventoryDefineAndPhraseLookup() async {
        let repository = await makeRepository()

        let canaryStatus = await repository.quickCanaryStatus()
        XCTAssertTrue(
            canaryStatus.hasWordNet2025,
            "Expected the quick canary pass to confirm WordNet 2025 resource availability."
        )
        XCTAssertTrue(
            canaryStatus.hasClassicWordNet,
            "Expected the quick canary pass to confirm classic WordNet availability."
        )

        let phraseCards = await repository.referenceNotesProbe(term: "one’s cup of tea")
        XCTAssertTrue(
            phraseCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "one's cup of tea"
            }),
            "Expected the quick canary pass to confirm compiled reference-note lookup and smart-apostrophe normalization."
        )
    }
}
