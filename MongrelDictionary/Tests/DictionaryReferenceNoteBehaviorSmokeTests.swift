import XCTest
@testable import MongrelDictionaryCore

final class DictionaryReferenceNoteBehaviorSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .dailyNotes }
    override class var repositoryScopeKey: String { "daily.notes" }

    func testReferenceNotesSearchReturnsAdaptedCard() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "filibuster")

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("delaying tactic")
            }),
            "Expected a Mongrel-authored adapted note for a seeded American political term."
        )
    }

    func testReferenceNotesSearchReturnsScotsAndEtymologyCards() async {
        let repository = await makeRepository()

        let scotsCards = await repository.referenceNotesProbe(term: "drookit")
        XCTAssertTrue(
            scotsCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("soaked through")
            }),
            "Expected a Scots reference note card for 'drookit'."
        )

        let etymologyCards = await repository.referenceNotesProbe(term: "sarcasm")
        XCTAssertTrue(
            etymologyCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("tear flesh")
            }),
            "Expected a word-origin reference note card for 'sarcasm'."
        )
    }

    func testReferenceNotesVariantEntryGetsOwnDefinition() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "blethering")

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "blethering" &&
                $0.summary.localizedCaseInsensitiveContains("talking away at length")
            }),
            "Expected a real variant entry for 'blethering' rather than only a base-word redirect."
        )
    }

    func testReferenceNotesSynonymLookupCanReachAdaptedEntry() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "nosy")

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "nebbie"
            }),
            "Expected synonym lookup to reach the adapted Scots entry for 'nebbie'."
        )
    }

    func testReferenceNotesSurfaceDialectCounterpartEntries() async {
        let repository = await makeRepository()

        let truckCards = await repository.referenceNotesProbe(term: "truck")
        let truckReferenceTitles = truckCards
            .filter { $0.source == "Mongrel reference notes" }
            .map(\.title)

        XCTAssertTrue(truckReferenceTitles.contains("truck"))
        XCTAssertTrue(truckReferenceTitles.contains("lorry"))

        let colourCards = await repository.referenceNotesProbe(term: "colour")
        let colourReferenceTitles = colourCards
            .filter { $0.source == "Mongrel reference notes" }
            .map(\.title)

        XCTAssertTrue(colourReferenceTitles.contains("colour"))
        XCTAssertTrue(colourReferenceTitles.contains("color"))
    }

    func testReferenceNotesRankExactEntriesAheadOfCounterpartCompanions() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "truck")

        let referenceCards = cards.filter { $0.source == "Mongrel reference notes" }
        let referenceTitles = referenceCards.map(\.title)

        guard let truckIndex = referenceTitles.firstIndex(of: "truck"),
              let lorryIndex = referenceTitles.firstIndex(of: "lorry") else {
            XCTFail("Expected both 'truck' and its counterpart 'lorry' to be present in reference-note results.")
            return
        }

        XCTAssertLessThan(truckIndex, lorryIndex)
    }

    func testReferenceNoteCardsExposeDirectAndCompanionMatchLabels() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "holiday")

        let referenceCards = cards.filter { $0.source == "Mongrel reference notes" }
        let holidayCard = referenceCards.first { $0.title == "holiday" }
        let bachCard = referenceCards.first { $0.title == "bach" }

        XCTAssertNotNil(holidayCard)
        XCTAssertNotNil(bachCard)
        XCTAssertTrue(
            holidayCard?.chips.contains("direct note hit") == true &&
            holidayCard?.chips.contains("exact hit") == true
        )
        XCTAssertTrue(
            bachCard?.chips.contains("companion result") == true &&
            bachCard?.chips.contains("related companion") == true
        )
    }

    func testReferenceNotesHandleIntentionalPopAmbiguity() async {
        let repository = await makeRepository()
        let cards = await repository.referenceNotesProbe(term: "pop")

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "pop"
            })
        )
        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "pop music"
            })
        )
    }
}
