import Foundation
import XCTest
@testable import MongrelDictionaryCore

private actor SessionRepositoryDouble: DictionarySessionRepository {
    private let summaryInventoryResult: [DictionaryRepository.SourceInventory]
    private let inventoryResult: [DictionaryRepository.SourceInventory]
    private let searchResults: [DictionaryRepository.SearchCard]
    private let searchResultsByTerm: [String: [DictionaryRepository.SearchCard]]
    private let suggestionsResult: [String]
    private let didYouMeanResult: [String]
    private let searchProfileAfterSearch: DictionaryRepository.SearchProfile?
    private var diagnosticsSnapshot: DictionaryRepository.Diagnostics
    private var blockSummaryInventoryLoad = false
    private var blockInventoryLoad = false
    private var blockSearch = false
    private var blockDidYouMean = false
    private var blockSuggestions = false
    private var summaryInventoryContinuation: CheckedContinuation<[DictionaryRepository.SourceInventory], Never>?
    private var inventoryContinuation: CheckedContinuation<[DictionaryRepository.SourceInventory], Never>?
    private var searchContinuation: CheckedContinuation<Void, Never>?
    private var didYouMeanContinuation: CheckedContinuation<[String], Never>?
    private var suggestionsContinuation: CheckedContinuation<[String], Never>?
    private var searchCount = 0
    private var lastSearchIntent: QueryIntent?

    init(
        summaryInventoryResult: [DictionaryRepository.SourceInventory]? = nil,
        inventoryResult: [DictionaryRepository.SourceInventory] = [],
        searchResults: [DictionaryRepository.SearchCard] = [],
        searchResultsByTerm: [String: [DictionaryRepository.SearchCard]] = [:],
        suggestionsResult: [String] = [],
        didYouMeanResult: [String] = [],
        loadedIndices: [String] = [],
        searchProfileAfterSearch: DictionaryRepository.SearchProfile? = nil
    ) {
        self.summaryInventoryResult = summaryInventoryResult ?? inventoryResult
        self.inventoryResult = inventoryResult
        self.searchResults = searchResults
        self.searchResultsByTerm = searchResultsByTerm
        self.suggestionsResult = suggestionsResult
        self.didYouMeanResult = didYouMeanResult
        self.searchProfileAfterSearch = searchProfileAfterSearch
        diagnosticsSnapshot = DictionaryRepository.Diagnostics(
            loadedIndices: loadedIndices,
            inventoryCached: false,
            cacheEntries: [],
            lastSearchProfile: nil
        )
    }

    func setBlockSummaryInventoryLoad(_ shouldBlock: Bool) {
        blockSummaryInventoryLoad = shouldBlock
    }

    func setBlockInventoryLoad(_ shouldBlock: Bool) {
        blockInventoryLoad = shouldBlock
    }

    func setBlockSearch(_ shouldBlock: Bool) {
        blockSearch = shouldBlock
    }

    func setBlockDidYouMean(_ shouldBlock: Bool) {
        blockDidYouMean = shouldBlock
    }

    func setBlockSuggestions(_ shouldBlock: Bool) {
        blockSuggestions = shouldBlock
    }

    func prewarm(profile: DictionaryRepository.PrewarmProfile) async {}

    func loadInventorySummary() async -> [DictionaryRepository.SourceInventory] {
        guard blockSummaryInventoryLoad else {
            return summaryInventoryResult
        }
        return await withCheckedContinuation { continuation in
            summaryInventoryContinuation = continuation
        }
    }

    func loadInventory() async -> [DictionaryRepository.SourceInventory] {
        guard blockInventoryLoad else {
            return inventoryResult
        }
        return await withCheckedContinuation { continuation in
            inventoryContinuation = continuation
        }
    }

    func diagnostics() async -> DictionaryRepository.Diagnostics {
        diagnosticsSnapshot
    }

    func lastSearchProfile() async -> DictionaryRepository.SearchProfile? {
        diagnosticsSnapshot.lastSearchProfile
    }

    func recordedSearchCount() -> Int { searchCount }

    func hasPendingSuggestions() -> Bool { suggestionsContinuation != nil }

    func recordedLastSearchIntent() -> QueryIntent? { lastSearchIntent }

    func search(term: String, intent: QueryIntent, bypassCache: Bool, allowBackgroundEnrichment: Bool) async -> [DictionaryRepository.SearchCard] {
        _ = bypassCache
        _ = allowBackgroundEnrichment
        if Task.isCancelled { return [] }
        searchCount += 1
        lastSearchIntent = intent
        if blockSearch {
            await withCheckedContinuation { continuation in
                searchContinuation = continuation
            }
        }
        if Task.isCancelled { return [] }
        if let searchProfileAfterSearch {
            diagnosticsSnapshot = DictionaryRepository.Diagnostics(
                loadedIndices: diagnosticsSnapshot.loadedIndices,
                inventoryCached: diagnosticsSnapshot.inventoryCached,
                cacheEntries: diagnosticsSnapshot.cacheEntries,
                lastSearchProfile: searchProfileAfterSearch
            )
        }
        return searchResultsByTerm[term] ?? searchResults
    }

    func suggestedTerms(prefix: String) async -> [String] {
        if Task.isCancelled { return [] }
        if blockSuggestions {
            return await withCheckedContinuation { continuation in
                suggestionsContinuation = continuation
            }
        }
        return suggestionsResult
    }

    func didYouMean(term: String) async -> [String] {
        if Task.isCancelled { return [] }
        if blockDidYouMean {
            return await withCheckedContinuation { continuation in
                didYouMeanContinuation = continuation
            }
        }
        return didYouMeanResult
    }

    func releaseSummaryInventoryLoad() {
        blockSummaryInventoryLoad = false
        guard let summaryInventoryContinuation else { return }
        self.summaryInventoryContinuation = nil
        summaryInventoryContinuation.resume(returning: summaryInventoryResult)
    }

    func releaseInventoryLoad() {
        blockInventoryLoad = false
        guard let inventoryContinuation else { return }
        self.inventoryContinuation = nil
        inventoryContinuation.resume(returning: inventoryResult)
    }

    func releaseSearch() {
        blockSearch = false
        guard let searchContinuation else { return }
        self.searchContinuation = nil
        searchContinuation.resume()
    }

    func releaseDidYouMean() {
        blockDidYouMean = false
        guard let didYouMeanContinuation else { return }
        self.didYouMeanContinuation = nil
        didYouMeanContinuation.resume(returning: didYouMeanResult)
    }

    func releaseSuggestions() {
        blockSuggestions = false
        guard let suggestionsContinuation else { return }
        self.suggestionsContinuation = nil
        suggestionsContinuation.resume(returning: suggestionsResult)
    }
}

@MainActor
final class DictionarySessionStartupTests: XCTestCase {
    func testTerminationFlushPersistsTheFinalQueryAndSearchCount() async throws {
        let (suite, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults,
                                        restoreLastLookupOnReady: false)
        session.selectTerm("harbor")
        await waitUntil("lookup completes before quitting") { session.isLookupSettled }
        session.query = "café"
        session.queryDidChange()
        session.flushPendingPersistence()
        let data = try XCTUnwrap(defaults.data(forKey: "mongrel.dictionary.searchFreq"))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data)["harbor"], 1)
        let restored = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults,
                                         restoreLastLookupOnReady: false)
        XCTAssertEqual(restored.query, "café")
        XCTAssertEqual(restored.recentTerms.first, "harbor")
    }

    func testClearingDeskRejectsSuggestionsThatIgnoreCancellation() async {
        let (suite, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = SessionRepositoryDouble(suggestionsResult: ["harbor", "harbour"])
        await repository.setBlockSuggestions(true)
        let session = DictionarySession(repository: repository, userDefaults: defaults,
                                        suggestionDebounceNanoseconds: 0,
                                        liveSearchDebounceNanoseconds: 0,
                                        restoreLastLookupOnReady: false)
        session.query = "har"
        session.queryDidChange()
        for _ in 0..<100 {
            if await repository.hasPendingSuggestions() { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let pending = await repository.hasPendingSuggestions()
        XCTAssertTrue(pending)
        session.clearQuery()
        await repository.releaseSuggestions()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.didYouMean.isEmpty)
        XCTAssertFalse(session.hasSearched)
        XCTAssertEqual(defaults.string(forKey: "mongrel.dictionary.lastQuery") ?? "", "")
    }

    func testProgrammaticSelectionSupersedesPendingQueryPersistence() async {
        let (suite, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults,
                                        liveSearchDebounceNanoseconds: 0,
                                        restoreLastLookupOnReady: false)
        session.query = "unfinished"
        session.queryDidChange()
        session.selectTerm("café", searchImmediately: false)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(defaults.string(forKey: "mongrel.dictionary.lastQuery"), "café")
    }

    func testStartupUsesCachedInventorySnapshotUntilLiveInventoryArrives() async throws {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let cachedStats = [
            DictionarySession.SourceStat(name: "WordNet classic", detail: "Legacy English index", status: "ready"),
            DictionarySession.SourceStat(name: "Regional English", detail: "Comparative variants", status: "partial")
        ]
        let cachedData = try XCTUnwrap(try? JSONEncoder().encode(cachedStats))
        userDefaults.set(cachedData, forKey: "mongrel.dictionary.cachedSourceStats")

        let repository = SessionRepositoryDouble(
            summaryInventoryResult: [
                DictionaryRepository.SourceInventory(name: "WordNet classic", detail: "Legacy English index", status: "ready"),
                DictionaryRepository.SourceInventory(name: "Regional English", detail: "Comparative variants", status: "ready"),
                DictionaryRepository.SourceInventory(name: "Reference notes", detail: "Authoring-backed notes", status: "ready")
            ],
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "WordNet classic", detail: "Legacy English index", status: "4 data files present"),
                DictionaryRepository.SourceInventory(name: "Regional English", detail: "Comparative variants", status: "140000 headwords present"),
                DictionaryRepository.SourceInventory(name: "Reference notes", detail: "Authoring-backed notes", status: "320 notes / 910 searchable entries present")
            ],
            loadedIndices: ["Fast lookup", "Search lexicon"]
        )
        await repository.setBlockSummaryInventoryLoad(true)
        await repository.setBlockInventoryLoad(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches inventory sync") {
            session.startup.phase == .syncingInventory
        }

        XCTAssertEqual(session.inventorySnapshotState, .cached)
        XCTAssertTrue(session.isUsingCachedInventorySnapshot)
        XCTAssertEqual(session.sourceStats.map(\.name), cachedStats.map(\.name))
        XCTAssertEqual(
            session.sourceInventorySummary,
            .init(totalCount: 2, availableCount: 1, partialCount: 1, missingCount: 0)
        )
        XCTAssertEqual(session.sourceHealthHeadline, "1 ready, 1 partial (last known)")

        await repository.releaseSummaryInventoryLoad()

        await waitUntil("summary inventory replaces cached snapshot") {
            session.startup.phase == .ready && session.inventorySnapshotState == .liveSummary
        }

        XCTAssertFalse(session.isUsingCachedInventorySnapshot)
        XCTAssertEqual(
            session.sourceStats.map(\.name),
            ["WordNet classic", "Regional English", "Reference notes"]
        )
        XCTAssertEqual(
            session.sourceStats.map(\.status),
            ["ready", "ready", "ready"]
        )
        XCTAssertEqual(
            session.sourceInventorySummary,
            .init(totalCount: 3, availableCount: 3, partialCount: 0, missingCount: 0)
        )
        XCTAssertEqual(session.sourceHealthHeadline, "3 sources ready (details syncing)")

        await repository.releaseInventoryLoad()

        await waitUntil("detailed inventory replaces summary snapshot") {
            session.inventorySnapshotState == .live
        }

        XCTAssertEqual(
            session.sourceStats.map(\.status),
            ["4 data files present", "140000 headwords present", "320 notes / 910 searchable entries present"]
        )
        XCTAssertEqual(
            session.sourceInventorySummary,
            .init(totalCount: 3, availableCount: 3, partialCount: 0, missingCount: 0)
        )
        XCTAssertEqual(session.sourceHealthHeadline, "3 sources ready")
    }

    func testStartupReachesReadyBeforeDetailedInventoryHydrationFinishes() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            summaryInventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready"),
                DictionaryRepository.SourceInventory(name: "Regional English", detail: "Comparative variants", status: "ready")
            ],
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready"),
                DictionaryRepository.SourceInventory(name: "Regional English", detail: "Comparative variants", status: "140000 headwords present")
            ],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockInventoryLoad(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready from summary inventory") {
            session.startup.phase == .ready && session.inventorySnapshotState == .liveSummary
        }

        XCTAssertFalse(session.isUsingCachedInventorySnapshot)
        XCTAssertTrue(session.isHydratingInventoryDetails)
        XCTAssertEqual(
            session.sourceStats.map(\.status),
            ["ready", "ready"]
        )
        XCTAssertEqual(session.sourceHealthHeadline, "2 sources ready (details syncing)")

        await repository.releaseInventoryLoad()

        await waitUntil("detailed inventory finishes hydrating") {
            session.inventorySnapshotState == .live
        }

        XCTAssertFalse(session.isHydratingInventoryDetails)
        XCTAssertEqual(
            session.sourceStats.map(\.status),
            ["ready", "140000 headwords present"]
        )
        XCTAssertEqual(session.sourceHealthHeadline, "2 sources ready")
    }

    func testLiveInventorySnapshotPersistsForNextLaunch() async throws {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let inventory = [
            DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready"),
            DictionaryRepository.SourceInventory(name: "Regional English", detail: "Comparative variants", status: "partial"),
            DictionaryRepository.SourceInventory(name: "ZA Mafoko", detail: "Bilingual archive", status: "missing")
        ]
        let repository = SessionRepositoryDouble(
            inventoryResult: inventory,
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches detailed inventory ready state") {
            session.startup.phase == .ready && session.inventorySnapshotState == .live
        }

        let data = try XCTUnwrap(userDefaults.data(forKey: "mongrel.dictionary.cachedSourceStats"))
        let persistedStats = try XCTUnwrap(try? JSONDecoder().decode([DictionarySession.SourceStat].self, from: data))

        XCTAssertEqual(session.inventorySnapshotState, .live)
        XCTAssertEqual(persistedStats.map(\.name), inventory.map(\.name))
        XCTAssertEqual(persistedStats.map(\.status), inventory.map(\.status))
        XCTAssertEqual(
            session.sourceInventorySummary,
            .init(totalCount: 3, availableCount: 1, partialCount: 1, missingCount: 1)
        )
        XCTAssertEqual(session.sourceHealthHeadline, "1 ready, 1 partial, 1 missing")
    }

    func testSearchUsesRepositoryMeasuredLatencyForDisplayedTiming() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let searchProfile = DictionaryRepository.SearchProfile(
            term: "harbor",
            intent: .define,
            cacheHit: false,
            totalElapsedMS: 7,
            sourceTimings: [
                DictionaryRepository.SearchProfile.SourceTiming(
                    name: "Fast lookup",
                    elapsedMS: 7,
                    resultCount: 1
                )
            ]
        )
        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"],
            searchProfileAfterSearch: searchProfile
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before search") {
            session.startup.phase == .ready
        }

        session.selectTerm("harbor")

        await waitUntil("search publishes measured latency") {
            session.lastSearchedTerm == "harbor" &&
            session.lastResultCount == 1 &&
            !session.isSearching
        }

        XCTAssertEqual(session.lastSearchDurationMS, 7)
        XCTAssertEqual(session.diagnostics.lastSearchProfile?.totalElapsedMS, 7)
        XCTAssertEqual(session.resultCards.map(\.title), ["Harbor"])
    }

    func testQuerySuggestionsPublishBeforeDidYouMeanHintsFinish() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            suggestionsResult: ["colour", "column", "cold"],
            didYouMeanResult: ["colour"],
            loadedIndices: ["Fast lookup", "Search lexicon"]
        )
        await repository.setBlockDidYouMean(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 0,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before suggestion test") {
            session.startup.phase == .ready
        }

        session.query = "colur"
        session.queryDidChange()

        await waitUntil("suggestions publish before did-you-mean") {
            session.suggestions == ["colour", "column", "cold"]
        }

        XCTAssertTrue(session.didYouMean.isEmpty)

        await repository.releaseDidYouMean()

        await waitUntil("did-you-mean follows after suggestions") {
            session.didYouMean == ["colour"]
        }
    }

    func testLiveSearchRunsAfterAPauseWithoutSubmit() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            suggestionsResult: ["harbor", "harbour", "hard"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 20_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before live search") {
            session.startup.phase == .ready
        }

        session.query = "har"
        session.queryDidChange()

        await waitUntil("live search fills results without submit") {
            session.hasSearched &&
            session.lastSearchedTerm == "har" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Harbor"]
        }

        XCTAssertTrue(session.recentTerms.isEmpty, "Live previews must not fill Recents.")
        XCTAssertEqual(session.suggestions, ["harbor", "harbour", "hard"])
        XCTAssertFalse(session.isLookupSettled)

        session.previewSearch()

        XCTAssertEqual(session.recentTerms, ["har"])
        XCTAssertTrue(session.isLookupSettled)
        XCTAssertEqual(session.resultCards.map(\.title), ["Harbor"])
    }

    func testShortQueriesDoNotLiveSearch() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Able",
                    source: "Fast lookup",
                    summary: "Having the power or means to do something.",
                    chips: ["exact hit"]
                )
            ],
            suggestionsResult: ["able", "about"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 20_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before short-query check") {
            session.startup.phase == .ready
        }

        session.query = "ab"
        session.queryDidChange()

        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(session.hasSearched)
        XCTAssertTrue(session.resultCards.isEmpty)
        XCTAssertEqual(session.suggestions, ["able", "about"])
    }

    func testExactSuggestionMatchLooksUpImmediately() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Colour",
                    source: "Fast lookup",
                    summary: "A visual perception produced by light.",
                    chips: ["exact hit", "noun"]
                )
            ],
            suggestionsResult: ["colour", "column", "cold"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before exact-headword search") {
            session.startup.phase == .ready
        }

        session.query = "colour"
        session.queryDidChange()

        await waitUntil("exact suggestion match searches without waiting for live debounce") {
            session.hasSearched &&
            session.lastSearchedTerm == "colour" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Colour"]
        }

        XCTAssertEqual(session.recentTerms, ["colour"])
        XCTAssertTrue(session.isLookupSettled)
    }

    func testLaunchRestoresTheLastTypedLookup() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set("harbor", forKey: "mongrel.dictionary.lastQuery")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 0,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("restored query is looked up after search becomes ready") {
            session.hasSearched &&
            session.lastSearchedTerm == "harbor" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Harbor"]
        }

        XCTAssertTrue(session.recentTerms.isEmpty, "Restored lookups should not inflate Recents.")
    }

    func testChangingIntentForTheSameTermRunsANewSearch() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before intent-switch search") {
            session.startup.phase == .ready
        }

        session.selectTerm("harbor")

        await waitUntil("define search applies") {
            session.lastSearchedTerm == "harbor" &&
            session.lastSearchedIntent == .define &&
            !session.isSearching
        }

        let defineCount = await repository.recordedSearchCount()
        XCTAssertEqual(defineCount, 1)

        session.selectIntent(.synonyms)

        await waitUntil("synonym search applies for the same headword") {
            session.lastSearchedTerm == "harbor" &&
            session.lastSearchedIntent == .synonyms &&
            !session.isSearching
        }

        let synonymCount = await repository.recordedSearchCount()
        let lastIntent = await repository.recordedLastSearchIntent()
        XCTAssertEqual(synonymCount, 2)
        XCTAssertEqual(lastIntent, .synonyms)
    }

    func testStaleSearchDoesNotReplaceANewerQuery() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockSearch(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before stale-search test") {
            session.startup.phase == .ready
        }

        session.selectTerm("harbor")

        await waitUntil("harbor search is in flight") {
            session.isSearching && session.inFlightTerm == "harbor"
        }

        session.query = "xy"
        await repository.releaseSearch()

        await waitUntil("abandoned search leaves the desk empty") {
            !session.isSearching && session.inFlightTerm.isEmpty
        }

        XCTAssertFalse(session.hasSearched)
        XCTAssertTrue(session.resultCards.isEmpty)
        XCTAssertEqual(session.lastSearchedTerm, "")
    }

    func testCancelledSearchKeepsPreviousResults() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before cancel test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog search applies") {
            session.lastSearchedTerm == "dog" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        await repository.setBlockSearch(true)
        session.selectTerm("cat")

        await waitUntil("cat search is in flight") {
            session.isSearching && session.inFlightTerm == "cat"
        }

        session.cancelSearch()
        await repository.releaseSearch()

        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(session.lastSearchedTerm, "dog")
        XCTAssertEqual(session.resultCards.map(\.title), ["Dog"])
        XCTAssertFalse(session.isSearching)
        XCTAssertEqual(session.inFlightTerm, "")
    }

    func testRestoreDoesNotOverrideAnEditedQuery() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set("harbor", forKey: "mongrel.dictionary.lastQuery")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 0,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        session.query = "zz"

        await waitUntil("startup reaches ready after the field was edited") {
            session.startup.phase == .ready
        }

        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertNotEqual(session.lastSearchedTerm, "harbor")
        XCTAssertTrue(session.resultCards.isEmpty)
    }

    func testSearchKeepsVisibleResultsUntilReplacementCardsArrive() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before replacement search test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog search resolves") {
            session.lastSearchedTerm == "dog" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        await repository.setBlockSearch(true)
        session.selectTerm("cat")

        await waitUntil("cat search enters in-flight state") {
            session.inFlightTerm == "cat" && session.isSearching
        }

        XCTAssertEqual(session.lastSearchedTerm, "dog")
        XCTAssertEqual(session.resultCards.map(\.title), ["Dog"])

        await repository.releaseSearch()

        await waitUntil("cat search replaces visible cards") {
            !session.isSearching && session.resultCards.map(\.title) == ["Cat"]
        }
    }

    func testInventoryBootstrapWaitsForInFlightSearchBeforeReadyState() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let searchProfile = DictionaryRepository.SearchProfile(
            term: "harbor",
            intent: .define,
            cacheHit: false,
            totalElapsedMS: 9,
            sourceTimings: [
                DictionaryRepository.SearchProfile.SourceTiming(
                    name: "Fast lookup",
                    elapsedMS: 9,
                    resultCount: 1
                )
            ]
        )
        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"],
            searchProfileAfterSearch: searchProfile
        )
        await repository.setBlockSearch(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 50_000_000,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches search-ready before blocked search") {
            session.startup.phase == .syncingInventory
        }

        session.selectTerm("harbor")

        await waitUntil("search enters blocked in-flight state") {
            session.isSearching && session.inFlightTerm == "harbor"
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(
            session.startup.phase,
            .syncingInventory,
            "Inventory bootstrap should stay in the background until the in-flight search settles."
        )

        await repository.releaseSearch()

        await waitUntil("inventory bootstrap completes after search settles") {
            session.startup.phase == .ready && !session.isSearching
        }

        XCTAssertEqual(session.lastSearchDurationMS, 9)
        XCTAssertEqual(session.resultCards.map(\.title), ["Harbor"])
    }

    func testReturnDuringInFlightLiveSearchDoesNotRestartTheLookup() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockSearch(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 20_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before in-flight commit test") {
            session.startup.phase == .ready
        }

        session.query = "harbor"
        session.queryDidChange()

        await waitUntil("live search is in flight") {
            session.isSearching && session.inFlightTerm == "harbor"
        }

        session.previewSearch()

        let searchCount = await repository.recordedSearchCount()
        XCTAssertEqual(searchCount, 1, "Return should pin the in-flight live search instead of restarting it.")
        XCTAssertTrue(session.recentTerms.isEmpty, "Recents must wait until the lookup actually applies.")

        await repository.releaseSearch()

        await waitUntil("promoted live search commits after it applies") {
            session.hasSearched &&
            session.lastSearchedTerm == "harbor" &&
            !session.isSearching &&
            session.isLookupSettled
        }

        XCTAssertEqual(session.recentTerms, ["harbor"])
        XCTAssertEqual(session.resultCards.map(\.title), ["Harbor"])
        let finalCount = await repository.recordedSearchCount()
        XCTAssertEqual(finalCount, 1)
    }

    func testAbandonedCommittedSearchDoesNotFillRecents() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockSearch(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before abandoned-commit test") {
            session.startup.phase == .ready
        }

        session.selectTerm("harbor")

        await waitUntil("committed search is in flight") {
            session.isSearching && session.inFlightTerm == "harbor"
        }

        XCTAssertTrue(session.recentTerms.isEmpty)

        session.query = "xy"
        await repository.releaseSearch()

        await waitUntil("abandoned search settles without applying cards") {
            !session.isSearching && session.inFlightTerm.isEmpty
        }

        XCTAssertTrue(session.recentTerms.isEmpty)
        XCTAssertFalse(session.hasSearched)
        XCTAssertTrue(session.resultCards.isEmpty)
    }

    func testExactSuggestionMatchCommitsAnExistingLivePreview() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Colour",
                    source: "Fast lookup",
                    summary: "A visual perception produced by light.",
                    chips: ["exact hit", "noun"]
                )
            ],
            suggestionsResult: ["colour", "column", "cold"],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockSuggestions(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 20_000_000,
            liveSearchDebounceNanoseconds: 20_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before live-preview commit test") {
            session.startup.phase == .ready
        }

        session.query = "colour"
        session.queryDidChange()

        await waitUntil("live preview applies before suggestions arrive") {
            session.hasSearched &&
            session.lastSearchedTerm == "colour" &&
            !session.isSearching &&
            !session.isLookupSettled
        }

        XCTAssertTrue(session.recentTerms.isEmpty)

        await repository.releaseSuggestions()

        await waitUntil("exact headword match commits the visible live preview") {
            session.isLookupSettled && session.recentTerms == ["colour"]
        }

        let searchCount = await repository.recordedSearchCount()
        XCTAssertEqual(searchCount, 1, "Committing a visible live preview must not run the lookup again.")
        XCTAssertEqual(session.resultCards.map(\.title), ["Colour"])
    }

    func testInlineCompletionAndLastLookupHints() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            suggestionsResult: ["harbor", "harbour", "hard"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before completion hints") {
            session.startup.phase == .ready
        }

        session.query = "har"
        session.queryDidChange()

        await waitUntil("prefix suggestions publish a completion") {
            session.suggestions == ["harbor", "harbour", "hard"]
        }

        XCTAssertEqual(session.inlineCompletion, "harbor")

        session.selectTerm("harbor")

        await waitUntil("committed harbor lookup applies") {
            session.lastSearchedTerm == "harbor" &&
            session.isLookupSettled &&
            !session.resultCards.isEmpty
        }

        session.clearSearchField()
        XCTAssertTrue(session.isShowingLastLookupWithoutQuery)
        XCTAssertEqual(session.lastSearchedTerm, "harbor")
        XCTAssertEqual(session.resultCards.map(\.title), ["Harbor"])
        XCTAssertNil(session.inlineCompletion)

        session.query = "xy"
        session.restoreDisplayedQuery()
        XCTAssertEqual(session.query, "harbor")
        XCTAssertFalse(session.isShowingLastLookupWithoutQuery)

        session.forgetRecent("harbor")
        XCTAssertTrue(session.recentTerms.isEmpty)

        session.toggleFavorite(term: "harbor")
        XCTAssertTrue(session.isFavorite("harbor"))
        session.removeFavorite("harbor")
        XCTAssertFalse(session.isFavorite("harbor"))
    }

    func testLocalSuggestionsAppearImmediatelyFromRecents() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(["harbor", "harbour"], forKey: "mongrel.dictionary.recentTerms")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            suggestionsResult: ["harmony", "harsh"],
            loadedIndices: ["Fast lookup"]
        )
        await repository.setBlockSuggestions(true)

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 20_000_000,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before local suggestion test") {
            session.startup.phase == .ready
        }

        session.query = "har"
        session.queryDidChange()

        XCTAssertEqual(session.suggestions, ["harbor", "harbour"])
        XCTAssertEqual(session.inlineCompletion, "harbor")

        await repository.releaseSuggestions()

        await waitUntil("lexicon suggestions merge after local seeds") {
            session.suggestions == ["harbor", "harbour", "harmony", "harsh"]
        }
    }

    func testKnownRecentTermLooksUpWithoutLiveDebounce() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(["harbor"], forKey: "mongrel.dictionary.recentTerms")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before known-term lookup") {
            session.startup.phase == .ready
        }

        session.query = "harbor"
        session.queryDidChange()

        await waitUntil("recent headword looks up without waiting for live debounce") {
            session.hasSearched &&
            session.lastSearchedTerm == "harbor" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Harbor"]
        }

        XCTAssertTrue(session.recentTerms.contains("harbor"))
        XCTAssertFalse(session.isLookupSettled, "Typing a known recent should preview, not commit, until Return.")
    }

    func testOversizedQueryIsCappedBeforeLookupWorkBegins() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before oversized-query test") {
            session.startup.phase == .ready
        }

        session.query = String(repeating: "a", count: 800)
        session.queryDidChange()

        XCTAssertEqual(session.query.count, DictionarySession.maxQueryLength)
        XCTAssertEqual(session.query.count, DictionaryLookupRequest.maximumTermLength)
    }

    func testOversizedResultSetIsCappedForTheReadingColumn() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manyCards = (0..<80).map { index in
            DictionaryRepository.SearchCard(
                title: "Term \(index)",
                source: "Fast lookup",
                summary: "Definition \(index).",
                chips: ["exact hit"]
            )
        }
        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: manyCards,
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0
        )

        await waitUntil("startup reaches ready before oversized-result test") {
            session.startup.phase == .ready
        }

        session.selectTerm("flood")

        await waitUntil("oversized search applies a capped reading set") {
            session.hasSearched &&
            !session.isSearching &&
            session.lastResultCount == 80
        }

        XCTAssertEqual(session.resultCards.count, DictionarySession.maxVisibleResultCards)
        XCTAssertEqual(session.hiddenResultCount, 80 - DictionarySession.maxVisibleResultCards)
    }

    func testHungSearchTimesOutAndKeepsPreviousResults() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            searchWatchdogNanoseconds: 40_000_000
        )

        await waitUntil("startup reaches ready before hung-search test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog search applies before the hung lookup") {
            session.lastSearchedTerm == "dog" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        await repository.setBlockSearch(true)
        session.selectTerm("cat")

        await waitUntil("hung cat search is cancelled by the watchdog") {
            session.lastSearchTimedOut && !session.isSearching
        }

        XCTAssertEqual(session.lastSearchedTerm, "dog")
        XCTAssertEqual(session.resultCards.map(\.title), ["Dog"])
        XCTAssertEqual(session.inFlightTerm, "")
        XCTAssertEqual(session.lastTimedOutTerm, "cat")
        XCTAssertTrue(session.canRetryLookup)

        await repository.setBlockSearch(false)
        await repository.releaseSearch()
        session.retryCurrentLookup()

        await waitUntil("retry reruns the timed-out lookup") {
            session.lastSearchedTerm == "cat" &&
            !session.isSearching &&
            !session.lastSearchTimedOut &&
            session.resultCards.map(\.title) == ["Cat"]
        }

        XCTAssertEqual(session.lastTimedOutTerm, "")
    }

    func testRapidBackToBackLookupsKeepOnlyTheLatestResults() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "apple": [
                    DictionaryRepository.SearchCard(
                        title: "Apple",
                        source: "Fast lookup",
                        summary: "A fruit.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "berry": [
                    DictionaryRepository.SearchCard(
                        title: "Berry",
                        source: "Fast lookup",
                        summary: "A small fruit.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cedar": [
                    DictionaryRepository.SearchCard(
                        title: "Cedar",
                        source: "Fast lookup",
                        summary: "A tree.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "delta": [
                    DictionaryRepository.SearchCard(
                        title: "Delta",
                        source: "Fast lookup",
                        summary: "A river mouth.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "ember": [
                    DictionaryRepository.SearchCard(
                        title: "Ember",
                        source: "Fast lookup",
                        summary: "A glowing coal.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before burst lookup test") {
            session.startup.phase == .ready
        }

        await repository.setBlockSearch(true)
        session.selectTerm("apple")
        session.selectTerm("berry")
        session.selectTerm("cedar")
        session.selectTerm("delta")
        session.selectTerm("ember")

        await waitUntil("latest burst lookup is the in-flight term") {
            session.isSearching && session.inFlightTerm == "ember"
        }

        XCTAssertTrue(session.resultCards.isEmpty)
        await repository.releaseSearch()

        await waitUntil("burst lookup settles on the last requested term") {
            session.lastSearchedTerm == "ember" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Ember"]
        }

        XCTAssertEqual(session.recentTerms, ["ember"])
        XCTAssertEqual(session.query, "ember")
        XCTAssertTrue(session.isLookupSettled)
    }

    func testRapidLivePreviewsKeepOnlyTheLatestCards() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "alpha": [
                    DictionaryRepository.SearchCard(
                        title: "Alpha",
                        source: "Fast lookup",
                        summary: "The first letter.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "bravo": [
                    DictionaryRepository.SearchCard(
                        title: "Bravo",
                        source: "Fast lookup",
                        summary: "A well done.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "charlie": [
                    DictionaryRepository.SearchCard(
                        title: "Charlie",
                        source: "Fast lookup",
                        summary: "A given name.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before live burst test") {
            session.startup.phase == .ready
        }

        await repository.setBlockSearch(true)
        session.query = "alpha"
        session.previewSearch(commit: false)
        session.query = "bravo"
        session.previewSearch(commit: false)
        session.query = "charlie"
        session.previewSearch(commit: false)

        await waitUntil("latest live preview is the in-flight term") {
            session.isSearching && session.inFlightTerm == "charlie"
        }

        await repository.releaseSearch()

        await waitUntil("live burst settles on the last typed term") {
            session.lastSearchedTerm == "charlie" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Charlie"]
        }

        XCTAssertTrue(session.recentTerms.isEmpty)
        XCTAssertFalse(session.isLookupSettled)
    }

    func testReturnOnEmptyFieldKeepsVisibleCards() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Dog",
                    source: "Fast lookup",
                    summary: "A domesticated canine.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before empty-return test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog lookup applies before empty return") {
            session.lastSearchedTerm == "dog" &&
            session.isLookupSettled &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        session.clearSearchField()
        XCTAssertTrue(session.isShowingLastLookupWithoutQuery)

        session.previewSearch()

        XCTAssertEqual(session.lastSearchedTerm, "dog")
        XCTAssertEqual(session.resultCards.map(\.title), ["Dog"])
        XCTAssertTrue(session.isShowingLastLookupWithoutQuery)
        XCTAssertFalse(session.isSearching)
    }

    func testLivePreviewWithNoMatchDoesNotClearPriorCards() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before empty live-preview test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog lookup applies before the unmatched preview") {
            session.lastSearchedTerm == "dog" &&
            session.isLookupSettled &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        session.query = "xyzzy"
        session.previewSearch(commit: false)

        await waitUntil("unmatched live preview finishes without replacing the desk") {
            !session.isSearching &&
            session.query == "xyzzy" &&
            session.lastSearchedTerm == "dog" &&
            session.resultCards.map(\.title) == ["Dog"]
        }

        XCTAssertFalse(session.isLookupSettled)
        XCTAssertEqual(session.recentTerms, ["dog"])
        let searchCount = await repository.recordedSearchCount()
        XCTAssertGreaterThanOrEqual(searchCount, 2)
    }

    func testSearchFrequencyNormalizesCase() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "Cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before frequency test") {
            session.startup.phase == .ready
        }

        session.selectTerm("Cat")

        await waitUntil("first cased lookup commits") {
            session.lastSearchedTerm == "Cat" && session.isLookupSettled
        }

        session.selectTerm("dog")

        await waitUntil("intervening lookup commits") {
            session.lastSearchedTerm == "dog" && session.isLookupSettled
        }

        session.selectTerm("cat")

        await waitUntil("second cased lookup commits") {
            session.lastSearchedTerm == "cat" &&
            session.isLookupSettled &&
            session.recentTerms.first == "cat"
        }

        XCTAssertEqual(
            session.topSearches.first { $0.term.compare("cat", options: .caseInsensitive) == .orderedSame }?.count,
            2
        )
    }

    func testLaunchMergesCasedSearchFrequency() async throws {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let encoded = try JSONEncoder().encode(["Harbor": 3, "harbor": 2, "Colour": 1])
        userDefaults.set(encoded, forKey: "mongrel.dictionary.searchFreq")
        userDefaults.set(["Harbor"], forKey: "mongrel.dictionary.recentTerms")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        XCTAssertEqual(
            session.topSearches.first { $0.term.compare("harbor", options: .caseInsensitive) == .orderedSame }?.count,
            5
        )
        XCTAssertEqual(
            session.topSearches.first { $0.term.compare("harbor", options: .caseInsensitive) == .orderedSame }?.term,
            "Harbor"
        )
        XCTAssertEqual(
            session.topSearches.first { $0.term.compare("colour", options: .caseInsensitive) == .orderedSame }?.count,
            1
        )
    }

    func testExactHeadwordPrefixDoesNotCommitWhileLongerSuggestionExists() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "catalog": [
                    DictionaryRepository.SearchCard(
                        title: "Catalog",
                        source: "Fast lookup",
                        summary: "A complete list of items.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            suggestionsResult: ["cat", "catalog", "catch"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before prefix-headword test") {
            session.startup.phase == .ready
        }

        session.query = "cat"
        session.queryDidChange()

        await waitUntil("cat previews while catalog is still a longer suggestion") {
            session.hasSearched &&
            session.lastSearchedTerm == "cat" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Cat"]
        }

        XCTAssertTrue(session.recentTerms.isEmpty)
        XCTAssertFalse(session.isLookupSettled)

        session.query = "catalog"
        session.queryDidChange()

        await waitUntil("finished headword commits once no longer completion remains") {
            session.lastSearchedTerm == "catalog" &&
            session.isLookupSettled &&
            session.recentTerms == ["catalog"]
        }

        XCTAssertEqual(session.resultCards.map(\.title), ["Catalog"])
    }

    func testSelectIntentWithEmptyFieldReusesDisplayedTerm() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Dog",
                    source: "Fast lookup",
                    summary: "A domesticated canine.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before empty-field intent test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")

        await waitUntil("dog lookup applies before the empty-field intent change") {
            session.lastSearchedTerm == "dog" && session.isLookupSettled
        }

        session.clearSearchField()
        session.selectIntent(.synonyms)

        await waitUntil("empty-field intent change restores and searches the displayed term") {
            session.query == "dog" &&
            session.lastSearchedTerm == "dog" &&
            session.lastSearchedIntent == .synonyms &&
            !session.isSearching
        }

        let intent = await repository.recordedLastSearchIntent()
        XCTAssertEqual(intent, .synonyms)
    }

    func testToggleFavoriteWhileComposingUsesDisplayedTerm() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Harbor",
                    source: "Fast lookup",
                    summary: "A sheltered body of water where ships may anchor.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before composing-favorite test") {
            session.startup.phase == .ready
        }

        session.selectTerm("harbor")

        await waitUntil("harbor lookup applies before composing") {
            session.lastSearchedTerm == "harbor" && session.isLookupSettled
        }

        session.query = "har"
        XCTAssertEqual(session.focusedTerm, "harbor")

        session.toggleFavorite()
        XCTAssertTrue(session.isFavorite("harbor"))
        XCTAssertFalse(session.isFavorite("har"))
        XCTAssertTrue(session.currentTermIsFavorite)
    }

    func testRetypingASettledTermClearsStaleDidYouMean() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Colour",
                    source: "Fast lookup",
                    summary: "A visual perception produced by light.",
                    chips: ["exact hit", "noun"]
                )
            ],
            suggestionsResult: ["colour", "column", "cold"],
            didYouMeanResult: ["colour"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 20_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before stale hint test") {
            session.startup.phase == .ready
        }

        session.selectTerm("colour")

        await waitUntil("colour lookup settles") {
            session.lastSearchedTerm == "colour" && session.isLookupSettled
        }

        // Keep the committed card displayed while the typo preview is in flight.
        // Otherwise the preview can apply and clear its hints before this test observes them.
        await repository.setBlockSearch(true)

        session.query = "colur"
        session.queryDidChange()

        await waitUntil("typo preview is pending with did-you-mean hints") {
            session.isSearching && session.inFlightTerm == "colur"
                && session.didYouMean == ["colour"]
        }

        session.query = "colour"
        session.queryDidChange()

        XCTAssertTrue(session.didYouMean.isEmpty)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.isLookupSettled)
        XCTAssertEqual(session.lastSearchedTerm, "colour")
        XCTAssertFalse(session.isSearching)
        await repository.releaseSearch()
    }

    func testLaunchDedupesCasedFavoritesAndRecents() {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(["Harbor", "harbor", "Colour"], forKey: "mongrel.dictionary.favoriteTerms")
        userDefaults.set(["Cat", "cat", "dog"], forKey: "mongrel.dictionary.recentTerms")

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        XCTAssertEqual(session.favoriteTerms, ["Harbor", "Colour"])
        XCTAssertEqual(session.recentTerms, ["Cat", "dog"])
    }

    func testSavedShelfDoesNotSilentlyEvictEarlierWords() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults, restoreLastLookupOnReady: false)
        for index in 0..<200 { session.toggleFavorite(term: "saved-\(index)") }
        XCTAssertEqual(session.favoriteTerms.count, 200)
        let saved = session.favoriteTerms
        session.toggleFavorite(term: "one-too-many")
        XCTAssertEqual(session.favoriteTerms, saved, "A full shelf must reject a new save, not delete another word")
        XCTAssertTrue(session.isFavorite("saved-0"))
        session.removeFavorite("saved-10")
        session.toggleFavorite(term: "replacement")
        XCTAssertTrue(session.isFavorite("replacement"))
        XCTAssertTrue(session.isFavorite("saved-0"))
    }

    func testClearHistoryPreventsPendingLookupFromRepopulatingHistory() async {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = SessionRepositoryDouble()
        let session = DictionarySession(repository: repository, userDefaults: defaults, restoreLastLookupOnReady: false)
        await waitUntil("ready for history privacy regression") { session.startup.phase == .ready }
        session.selectTerm("first")
        await waitUntil("first committed") { session.lastSearchedTerm == "first" && !session.isSearching }
        session.selectTerm("second")
        await waitUntil("second committed") { session.lastSearchedTerm == "second" && !session.isSearching }
        XCTAssertTrue(session.canGoBack)
        await repository.setBlockSearch(true)
        session.selectTerm("pending")
        // Yield until the fake repository has suspended this request.
        for _ in 0..<100 {
            if await repository.recordedSearchCount() >= 3 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        session.clearHistory()
        XCTAssertFalse(session.canGoBack)
        XCTAssertFalse(session.canGoForward)
        await repository.releaseSearch()
        await waitUntil("pending result can still finish without recording history") { !session.isSearching }
        session.flushPendingPersistence()
        XCTAssertTrue(session.recentTerms.isEmpty)
        XCTAssertTrue(session.topSearches.isEmpty)
        XCTAssertFalse(session.canGoBack)
        XCTAssertTrue((defaults.stringArray(forKey: "mongrel.dictionary.recentTerms") ?? []).isEmpty)
    }

    func testClearDeskResetsLookupHistory() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "dog": [
                    DictionaryRepository.SearchCard(
                        title: "Dog",
                        source: "Fast lookup",
                        summary: "A domesticated canine.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before history clear test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")
        await waitUntil("dog commits to history") {
            session.lastSearchedTerm == "dog" && session.isLookupSettled
        }

        session.selectTerm("cat")
        await waitUntil("cat commits and enables back") {
            session.lastSearchedTerm == "cat" && session.canGoBack
        }

        session.clearQuery()

        XCTAssertFalse(session.hasSearched)
        XCTAssertTrue(session.resultCards.isEmpty)
        XCTAssertFalse(session.canGoBack)
        XCTAssertFalse(session.canGoForward)

        session.goBack()
        XCTAssertEqual(session.lastSearchedTerm, "")
        XCTAssertTrue(session.resultCards.isEmpty)
    }

    func testAcceptInlineCompletionDoesNotCommitAPrefixHeadword() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResultsByTerm: [
                "cat": [
                    DictionaryRepository.SearchCard(
                        title: "Cat",
                        source: "Fast lookup",
                        summary: "A domesticated feline.",
                        chips: ["exact hit", "noun"]
                    )
                ],
                "catalog": [
                    DictionaryRepository.SearchCard(
                        title: "Catalog",
                        source: "Fast lookup",
                        summary: "A complete list of items.",
                        chips: ["exact hit", "noun"]
                    )
                ]
            ],
            suggestionsResult: ["cat", "catalog", "catch"],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            suggestionDebounceNanoseconds: 0,
            liveSearchDebounceNanoseconds: 2_000_000_000,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before tab-completion test") {
            session.startup.phase == .ready
        }

        session.query = "ca"
        session.queryDidChange()

        await waitUntil("prefix suggestions publish a completion") {
            session.inlineCompletion == "cat"
        }

        session.acceptInlineCompletion()

        await waitUntil("tab completion previews cat without committing") {
            session.lastSearchedTerm == "cat" &&
            !session.isSearching &&
            session.resultCards.map(\.title) == ["Cat"]
        }

        XCTAssertTrue(session.recentTerms.isEmpty)
        XCTAssertFalse(session.isLookupSettled)
    }

    func testSearchPackageUsesQueryIntentWhileComposing() async {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let repository = SessionRepositoryDouble(
            inventoryResult: [
                DictionaryRepository.SourceInventory(name: "Fast lookup", detail: "SQLite runtime", status: "ready")
            ],
            searchResults: [
                DictionaryRepository.SearchCard(
                    title: "Dog",
                    source: "Fast lookup",
                    summary: "A domesticated canine.",
                    chips: ["exact hit", "noun"]
                )
            ],
            loadedIndices: ["Fast lookup"]
        )

        let session = DictionarySession(
            repository: repository,
            userDefaults: userDefaults,
            inventoryBootstrapDelayNanoseconds: 0,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )

        await waitUntil("startup reaches ready before package-intent test") {
            session.startup.phase == .ready
        }

        session.selectTerm("dog")
        await waitUntil("dog lookup settles before composing") {
            session.isLookupSettled && session.lastSearchedTerm == "dog"
        }

        XCTAssertTrue(session.searchPackageText.contains("Mode: Define"))

        session.query = "do"
        session.queryIntent = .synonyms
        XCTAssertFalse(session.isLookupSettled)
        XCTAssertTrue(session.searchPackageText.contains("Mode: Synonyms"))
        XCTAssertTrue(session.searchPackageText.contains("Query: dog"))
    }

    func testDiscardedSessionDoesNotRemainAliveForCalendarNotifications() async {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var session: DictionarySession? = DictionarySession(
            repository: SessionRepositoryDouble(),
            userDefaults: defaults,
            backgroundAssistBootstrapDelayNanoseconds: 0,
            restoreLastLookupOnReady: false
        )
        await waitUntil("startup finishes before releasing the session") {
            session?.startup.phase == .ready
        }
        weak var releasedSession = session
        session = nil
        await waitUntil("calendar observer releases the discarded session") {
            releasedSession == nil
        }
    }

    func testRestoredQueryAndRecentsAreBounded() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(String(repeating: "a", count: 100_000), forKey: "mongrel.dictionary.lastQuery")
        defaults.set((0..<1_000).map { "term-\($0)" }, forKey: "mongrel.dictionary.recentTerms")
        let session = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults,
                                        restoreLastLookupOnReady: false)
        XCTAssertEqual(session.query.count, DictionarySession.maxQueryLength)
        XCTAssertEqual(session.recentTerms.count, 8)
    }

    func testExtremeStoredSearchCountsCannotOverflowOnRestoreOrCommit() async throws {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(["DOG": Int.max, "dog": 1]),
                     forKey: "mongrel.dictionary.searchFreq")
        let session = DictionarySession(repository: SessionRepositoryDouble(), userDefaults: defaults,
                                        backgroundAssistBootstrapDelayNanoseconds: 0,
                                        restoreLastLookupOnReady: false)
        XCTAssertEqual(session.topSearches.first?.count, Int.max)
        await waitUntil("startup finishes before committing saturated counter") {
            session.startup.phase == .ready
        }
        session.selectTerm("dog")
        await waitUntil("saturated counter lookup finishes") { session.isLookupSettled }
        XCTAssertEqual(session.topSearches.first?.count, Int.max)
    }

    private func makeIsolatedDefaults() -> (suiteName: String, userDefaults: UserDefaults) {
        let suiteName = "mongrel.dictionary.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        return (suiteName, userDefaults)
    }

    private func waitUntil(
        _ message: String,
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Timed out waiting for \(message)")
    }
}
