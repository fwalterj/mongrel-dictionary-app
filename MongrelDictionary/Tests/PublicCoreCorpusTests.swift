import XCTest
@testable import MongrelDictionaryCore

final class PublicCoreCorpusTests: XCTestCase {
    private func requireCoreCorpus() throws {
        guard DictionaryCorpusEdition.isPublicCore else {
            throw XCTSkip("Run separately with the prepared public-core corpus bundled.")
        }
    }

    func testEverydayDefinitionsAndSynonymsHaveRealSourceResults() async throws {
        try requireCoreCorpus()
        let repository = DictionaryRepository()
        let inventory = await repository.loadInventory()
        XCTAssertEqual(inventory.count, 2)
        XCTAssertTrue(inventory.allSatisfy { $0.name.contains("WordNet") })
        await repository.prewarm(profile: .interactiveSession)
        for (term, intent) in [("bank", QueryIntent.define), ("run", .define),
                               ("colour", .define), ("computer", .define),
                               ("happy", .synonyms), ("good", .synonyms)] {
            let cards = await repository.search(term: term, intent: intent, bypassCache: true)
            XCTAssertTrue(cards.contains { $0.source.contains("WordNet") && !$0.summary.isEmpty },
                          "\(term): \(cards.map { $0.source })")
        }
    }

    func testUnavailableModesExplainCoverageInsteadOfPretendingToTranslate() async throws {
        try requireCoreCorpus()
        XCTAssertEqual(DictionaryCorpusEdition.availableIntents, [.define, .synonyms])
        XCTAssertNotNil(DictionaryCorpusEdition.noticesURL)
        let repository = DictionaryRepository()
        for intent in [QueryIntent.translation, .slang] {
            let cards = await repository.search(term: "hello", intent: intent)
            XCTAssertEqual(cards.map(\.source), ["Edition coverage"])
            XCTAssertTrue(cards[0].summary.contains("not included"))
        }
    }

    func testPolysemousEntryIncludesEveryImportedDefinition() async throws {
        try requireCoreCorpus()
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "bank", intent: .define)
        let card = try XCTUnwrap(cards.first { $0.source.contains("2025") })
        XCTAssertTrue(card.summary.contains("18. "), "Bank must not advertise 18 senses while silently presenting only two or six.")
    }
}
