import XCTest
@testable import MongrelDictionaryCore

final class DictionaryPhraseBehaviorSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .dailyNotes }
    override class var repositoryScopeKey: String { "daily.notes" }

    func testPhraseLookupNormalizesWhitespaceAndSmartPunctuation() async {
        let repository = await makeRepository()

        let spacedCards = await repository.referenceNotesProbe(term: "read   between   the lines")
        XCTAssertTrue(
            spacedCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "read between the lines"
            }),
            "Expected phrase lookup to collapse repeated whitespace for Longman-derived entries."
        )

        let apostropheCards = await repository.referenceNotesProbe(term: "one’s cup of tea")
        XCTAssertTrue(
            apostropheCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "one's cup of tea"
            }),
            "Expected phrase lookup to normalize smart apostrophes for note titles."
        )
    }

    func testPhraseCoreLookupFindsNotesWhenFunctionWordsAreMissing() async {
        let repository = await makeRepository()

        let cupOfTeaCards = await repository.referenceNotesProbe(term: "cup of tea")
        XCTAssertTrue(
            cupOfTeaCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "one's cup of tea" &&
                $0.chips.contains("phrase-core hit")
            }),
            "Expected phrase-core lookup to reach 'one's cup of tea' when the placeholder wording is omitted."
        )

        let goodFaithCards = await repository.referenceNotesProbe(term: "good faith")
        XCTAssertTrue(
            goodFaithCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "in good faith" &&
                $0.chips.contains("phrase-core hit")
            }),
            "Expected phrase-core lookup to reach 'in good faith' when the leading preposition is omitted."
        )

        let faceMusicCards = await repository.referenceNotesProbe(term: "face music")
        XCTAssertTrue(
            faceMusicCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "face the music" &&
                $0.chips.contains("phrase-core hit")
            }),
            "Expected phrase-core lookup to reach 'face the music' when the article is omitted."
        )
    }
}
