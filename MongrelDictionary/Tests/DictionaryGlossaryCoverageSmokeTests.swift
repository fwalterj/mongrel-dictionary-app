import XCTest
@testable import MongrelDictionaryCore

final class DictionaryGlossaryCoverageSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .referenceNotes }

    func testReferenceNoteSummariesDoNotExposeUnderlyingSourceTitles() async {
        let repository = await makeRepository()

        let queries = ["acid test", "dab hand", "filibuster", "drookit", "salary", "colour", "robot", "Taoiseach"]
        let forbiddenPhrases = [
            "Adapted from",
            "Longman Modern English Dictionary",
            "Concise Oxford English Dictionary",
            "Dictionary of American Government and Politics",
            "Jamieson's Scottish Dictionary",
            "Scoor-oot",
            "Where Words Come From",
            "British English browser dictionary package",
            "ZA Mafoko",
            "regional English resources",
            "Moby lexical resources"
        ]

        for query in queries {
            let cards = await repository.search(term: query, intent: .define)
            let noteCards = cards.filter { $0.source == "Mongrel reference notes" }

            XCTAssertFalse(noteCards.isEmpty, "Expected a Mongrel reference note card for '\(query)'.")

            for card in noteCards {
                for phrase in forbiddenPhrases {
                    XCTAssertFalse(
                        card.summary.localizedCaseInsensitiveContains(phrase),
                        "Reference-note summaries should stay in Mongrel's own voice and not expose source-title language like '\(phrase)'."
                    )
                }
            }
        }
    }

    func testReferenceNotesCoverMediaManipulationFallaciesAndModernEngagementTerms() async {
        let repository = await makeRepository()

        let keywordSquattingCards = await repository.search(term: "keyword squatting", intent: .define)
        XCTAssertTrue(
            keywordSquattingCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("search term") &&
                $0.antonyms.contains("authoritative search coverage")
            }),
            "Expected a Mongrel-authored note for 'keyword squatting' with antonym support."
        )

        let adHominemCards = await repository.search(term: "ad hominem", intent: .define)
        XCTAssertTrue(
            adHominemCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("attacking the speaker") &&
                $0.antonyms.contains("argument on the merits")
            }),
            "Expected a Mongrel-authored logic note for 'ad hominem'."
        )

        let darkPatternCards = await repository.search(term: "dark pattern", intent: .define)
        XCTAssertTrue(
            darkPatternCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("interface trick") &&
                $0.antonyms.contains("user-respecting design")
            }),
            "Expected a Mongrel-authored modern-engagement note for 'dark pattern'."
        )
    }

    func testReferenceNotesCoverNewGenreCultureAndIdentityGlossaries() async {
        let repository = await makeRepository()

        let cyberpunkCards = await repository.search(term: "cyberpunk", intent: .define)
        XCTAssertTrue(
            cyberpunkCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("corporate dominance")
            }),
            "Expected a speculative-fiction note for 'cyberpunk'."
        )

        let angleCards = await repository.search(term: "180 degree rule", intent: .define)
        XCTAssertTrue(
            angleCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("imaginary axis of action")
            }),
            "Expected a film-language note for the 180-degree rule."
        )

        let mainCharacterCards = await repository.search(term: "main character energy", intent: .define)
        XCTAssertTrue(
            mainCharacterCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("protagonist-like presence")
            }),
            "Expected an internet-slang note for 'main character energy'."
        )

        let sovereigntyCards = await repository.search(term: "tribal sovereignty", intent: .define)
        XCTAssertTrue(
            sovereigntyCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("authority of Native Nations")
            }),
            "Expected a Native-governance note for 'tribal sovereignty'."
        )

        let adaptationCards = await repository.search(term: "adaptation", intent: .define)
        XCTAssertTrue(
            adaptationCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("heritable feature")
            }),
            "Expected an evolutionary-science note for 'adaptation'."
        )

        let aftercareCards = await repository.search(term: "aftercare", intent: .define)
        XCTAssertTrue(
            aftercareCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("intense sex") &&
                $0.summary.localizedCaseInsensitiveContains("BDSM")
            }),
            "Expected a sexuality note for 'aftercare'."
        )
    }
}
