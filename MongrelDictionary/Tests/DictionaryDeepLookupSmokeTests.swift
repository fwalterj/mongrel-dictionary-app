import XCTest
@testable import MongrelDictionaryCore

final class DictionaryDeepLookupSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .deepShared }
    override class var repositoryScopeKey: String { "deep.shared" }

    func testDefineSearchHandlesLikelyTyposForReferenceNotesAndRegionalWords() async {
        let repository = await makeRepository()

        let lorryTypoCards = await repository.referenceNotesRecoveryProbe(term: "lorrry")
        XCTAssertTrue(
            lorryTypoCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "lorry"
            }),
            "Expected typo-tolerant lookup to recover the reference-note entry for 'lorry'."
        )

        let coffeeTypoCards = await repository.referenceNotesRecoveryProbe(term: "cofee break")
        XCTAssertTrue(
            coffeeTypoCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "coffee break"
            }),
            "Expected typo-tolerant lookup to recover the Longman-derived entry for 'coffee break'."
        )
    }

    func testDidYouMeanSuggestsGlobalEnglishCorrections() async {
        let repository = await makeRepository()

        let lorrySuggestions = await repository.didYouMeanDeepProbe(term: "lorrry")
        XCTAssertTrue(
            lorrySuggestions.contains("lorry"),
            "Expected English-wide 'did you mean' hints to suggest 'lorry' for a repeated-letter typo."
        )

        let coffeeSuggestions = await repository.didYouMeanDeepProbe(term: "cofee break")
        XCTAssertTrue(
            coffeeSuggestions.contains("coffee break"),
            "Expected English-wide 'did you mean' hints to suggest 'coffee break' for a missing-letter typo."
        )
    }

    func testReferenceNotesExposeTopicMeshLinks() async {
        let repository = await makeRepository()

        let taoiseachCards = await repository.referenceNotesProbe(term: "Taoiseach")
        XCTAssertTrue(
            taoiseachCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.topicTerms.contains("checks and balances")
            }),
            "Expected topic-mesh links from 'Taoiseach' into other government-system notes even without explicit seeAlso links."
        )

        let bansheeCards = await repository.referenceNotesProbe(term: "banshee")
        XCTAssertTrue(
            bansheeCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.topicTerms.contains("nightmare")
            }),
            "Expected folklore-based topic-mesh links from 'banshee' to related etymology notes."
        )
    }

    func testRegionalSpellingNoteExplainsCommonwealthVariant() async {
        let repository = await makeRepository()
        let cards = await repository.regionalSpellingLightProbe(term: "colour")

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Regional spelling note" &&
                $0.summary.localizedCaseInsensitiveContains("spelling variant of 'color'")
            }),
            "Expected a regional spelling card to explain the Commonwealth spelling 'colour'."
        )
    }

    func testDerivedHeuristicProbeBuildsPlainEnglishDefinitionForDoomy() async {
        let repository = await makeRepository()
        let derivedCards = await repository.derivedEnglishHeuristicProbe(term: "doomy")

        XCTAssertFalse(derivedCards.isEmpty)
        XCTAssertTrue(
            derivedCards.contains(where: {
                $0.source == "English word-family inference" &&
                $0.summary.localizedCaseInsensitiveContains("characterized by, suggestive of, or full of doom")
            }),
            "Expected a derivation-aware heuristic definition for 'doomy'."
        )
        XCTAssertTrue(
            derivedCards.contains(where: {
                $0.source == "English word-family inference" &&
                $0.summary.localizedCaseInsensitiveContains("British")
            }),
            "Expected the heuristic derived-word card for 'doomy' to preserve British regional attestation."
        )
    }
}
