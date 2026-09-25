import XCTest
@testable import MongrelDictionaryCore

final class DictionaryReferenceLatencySmokeTests: XCTestCase {
    func testExactPhraseLookupUsesReferenceStoreWithoutLoadingReferenceIndex() async {
        let repository = DictionaryRepository()
        let cards = await repository.referenceNotesProbe(term: "one's cup of tea")
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "one's cup of tea"
            }),
            "Expected direct phrase lookup to resolve through the packaged reference-note store."
        )
        XCTAssertTrue(diagnostics.loadedIndices.contains("Reference notes store"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Reference notes index"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Search lexicon"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Deep lookup lexicon"))
    }

    func testDeepRecoveryUsesStoreAndDeepLexiconWithoutLoadingReferenceIndex() async {
        let repository = DictionaryRepository()
        let cards = await repository.referenceNotesRecoveryProbe(term: "cofee break")
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "coffee break"
            }),
            "Expected deep recovery to repair the typo 'cofee break' through the packaged offline note stack."
        )
        XCTAssertTrue(diagnostics.loadedIndices.contains("Reference notes store"))
        XCTAssertTrue(diagnostics.loadedIndices.contains("Deep lookup lexicon"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Reference notes index"))
    }
}
