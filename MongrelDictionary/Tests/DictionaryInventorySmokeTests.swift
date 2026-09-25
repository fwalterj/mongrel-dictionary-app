import XCTest
@testable import MongrelDictionaryCore

final class DictionaryInventorySmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .none }

    func testInventoryIncludesBothWordNetSources() async {
        let repository = await makeRepository()
        let inventoryStatus = await repository.dailyInventoryStatus()

        XCTAssertTrue(inventoryStatus.hasWordNet2025)
        XCTAssertTrue(inventoryStatus.hasClassicWordNet)
    }

    func testClassicWordNetInventoryReportsCompleteDataSet() async {
        let repository = await makeRepository()
        let inventory = await repository.loadInventory()
        guard let classic = inventory.first(where: { $0.name == "WordNet 3.x (classic dict)" }) else {
            XCTFail("Missing classic WordNet inventory entry")
            return
        }

        XCTAssertTrue(
            classic.status.localizedCaseInsensitiveContains("present"),
            "Expected classic WordNet inventory status to report complete availability."
        )
        XCTAssertTrue(
            classic.status.localizedCaseInsensitiveContains("packaged archive")
                || classic.status.localizedCaseInsensitiveContains("4 data files"),
            "Expected a bundled runtime archive or the complete raw data set."
        )
    }

    func testPackagedInventoryDoesNotNeedDeveloperWorkbenchFiles() async {
        let repository = DictionaryRepository(workspaceRootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let inventory = await repository.loadInventory(detailLevel: .summary)
        for name in ["WordNet 2025 (OEWN XML)", "WordNet 3.x (classic dict)", "FreeDict",
                     "English (American) word list", "English (British) word list"] {
            let entry = inventory.first { $0.name == name }
            XCTAssertNotNil(entry, name)
            XCTAssertTrue(entry?.status.localizedCaseInsensitiveContains("present") == true, name)
        }
        XCTAssertTrue(inventory.allSatisfy { $0.status.localizedCaseInsensitiveContains("present") },
                      "Every source in the shipped inventory should be available without raw workbench files.")
        let status = await repository.dailyInventoryStatus()
        XCTAssertTrue(status.hasWordNet2025 && status.hasClassicWordNet)
        XCTAssertTrue(status.hasAmericanWordList && status.hasBritishWordList && status.hasSouthAfricanWordList)
        XCTAssertTrue(status.hasLongmanReference)
    }

    func testInventoryIncludesRegionalEnglishWordlists() async {
        let repository = await makeRepository()
        let inventoryStatus = await repository.dailyInventoryStatus()

        XCTAssertTrue(inventoryStatus.hasAmericanWordList)
        XCTAssertTrue(inventoryStatus.hasBritishWordList)
        XCTAssertTrue(inventoryStatus.hasSouthAfricanWordList)
        XCTAssertTrue(inventoryStatus.hasLongmanReference)
    }

    func testPackagedDefinitionsContainOnlyLookupResults() async {
        let repository = DictionaryRepository(workspaceRootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let cards = await repository.search(term: "palimpsest", intent: .define)
        XCTAssertTrue(cards.contains { $0.source.contains("WordNet") })
        XCTAssertFalse(cards.contains { $0.chips.contains("metadata only") || $0.chips.contains("pending ingest") })
    }

    func testDefineSearchUsesFastLookupBeforeHeavyWordNetLoads() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "dog", intent: .define)
        let diagnostics = await repository.diagnostics()

        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(
            cards.contains(where: { $0.source == "WordNet 2025 (Open English WordNet)" || $0.source == "WordNet 3.x (Princeton dict)" }),
            "Expected the packaged fast lookup to return a core English definition card for a common lemma."
        )
        XCTAssertTrue(diagnostics.loadedIndices.contains("Fast lookup"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet 2025"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet classic"))
    }

    func testSynonymSearchUsesFastLookupBeforeFullThesaurusLoads() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "bright", intent: .synonyms)
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Synonym digest" &&
                $0.summary.localizedCaseInsensitiveContains("brilliant")
            }),
            "Expected synonym mode to return a baked fast synonym card for a common lemma."
        )
        XCTAssertTrue(diagnostics.loadedIndices.contains("Synonym lookup"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("OpenOffice thesaurus"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Moby thesaurus"))
    }

    func testExactSynonymSearchSkipsStandardLookupCandidateExpansion() async {
        let repository = DictionaryRepository()
        _ = await repository.search(term: "bright", intent: .synonyms)
        let diagnostics = await repository.diagnostics()
        let standardLookupCacheCount = diagnostics.cacheEntries.first(where: { $0.name == "Standard lookup" })?.count

        XCTAssertEqual(
            standardLookupCacheCount,
            0,
            "An exact synonym digest hit should not build variant candidate lists before reading the fast store."
        )
    }

    func testTranslationSearchUsesFastLookupBeforeFullTranslationLoads() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "house", intent: .translation)
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Translation digest" &&
                $0.summary.contains(":")
            }),
            "Expected translation mode to return a baked fast translation card for a common lemma."
        )
        XCTAssertTrue(diagnostics.loadedIndices.contains("Translation lookup"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("FreeDict"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("ZA Mafoko"))
    }

    func testExactTranslationSearchSkipsStandardLookupCandidateExpansion() async {
        let repository = DictionaryRepository()
        _ = await repository.search(term: "house", intent: .translation)
        let diagnostics = await repository.diagnostics()
        let standardLookupCacheCount = diagnostics.cacheEntries.first(where: { $0.name == "Standard lookup" })?.count

        XCTAssertEqual(
            standardLookupCacheCount,
            0,
            "An exact translation digest hit should not build variant candidate lists before reading the fast store."
        )
    }

    func testSlangSearchUsesFastAustralianSourcesBeforeHeavyIndicesLoad() async {
        let repository = DictionaryRepository()
        let cards = await repository.search(term: "arvo", intent: .slang)
        let diagnostics = await repository.diagnostics()

        XCTAssertTrue(
            cards.contains(where: {
                $0.source == "Australian usage notes" &&
                $0.summary.localizedCaseInsensitiveContains("afternoon")
            }),
            "Expected slang mode to return the bundled Australian usage card for a common colloquial term."
        )
        XCTAssertFalse(diagnostics.loadedIndices.contains("Reference notes"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("Regional English"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet 2025"))
        XCTAssertFalse(diagnostics.loadedIndices.contains("WordNet classic"))
    }
}
