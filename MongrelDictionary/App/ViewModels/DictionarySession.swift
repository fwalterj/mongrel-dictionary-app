import Combine
import Foundation
import MongrelDictionaryCore

protocol DictionarySessionRepository: Sendable {
    func prewarm(profile: DictionaryRepository.PrewarmProfile) async
    func loadInventorySummary() async -> [DictionaryRepository.SourceInventory]
    func loadInventory() async -> [DictionaryRepository.SourceInventory]
    func diagnostics() async -> DictionaryRepository.Diagnostics
    func lastSearchProfile() async -> DictionaryRepository.SearchProfile?
    func search(term: String, intent: QueryIntent, bypassCache: Bool, allowBackgroundEnrichment: Bool) async -> [DictionaryRepository.SearchCard]
    func suggestedTerms(prefix: String) async -> [String]
    func didYouMean(term: String) async -> [String]
}

extension DictionaryRepository: DictionarySessionRepository {
    func loadInventory() -> [SourceInventory] {
        loadInventory(detailLevel: .detailed)
    }

    func loadInventorySummary() -> [SourceInventory] {
        loadInventory(detailLevel: .summary)
    }
}

@MainActor
final class DictionarySession: ObservableObject {
    struct DiagnosticsSnapshot: Sendable {
        let loadedIndices: [String]
        let inventoryCached: Bool
        let cacheEntries: [DictionaryRepository.Diagnostics.CacheEntry]
        let lastSearchProfile: DictionaryRepository.SearchProfile?

        static let empty = DiagnosticsSnapshot(
            loadedIndices: [],
            inventoryCached: false,
            cacheEntries: [],
            lastSearchProfile: nil
        )
    }

    struct StartupSnapshot: Sendable {
        enum Phase: Sendable, Equatable {
            case warmingSearch
            case syncingInventory
            case ready
        }

        let phase: Phase
        let title: String
        let detail: String

        var searchReady: Bool {
            phase != .warmingSearch
        }

        var inventoryReady: Bool {
            phase == .ready
        }

        var badgeText: String {
            switch phase {
            case .warmingSearch:
                return "Warming lookup"
            case .syncingInventory:
                return "Search ready"
            case .ready:
                return "Archive ready"
            }
        }

        static let warmingSearch = StartupSnapshot(
            phase: .warmingSearch,
            title: "Preparing instant lookup",
            detail: "Loading fast offline dictionary, synonym, and translation paths."
        )

        static let syncingInventory = StartupSnapshot(
            phase: .syncingInventory,
            title: "Search ready",
            detail: "Fast offline lookup is warm. Suggestions, regional notes, and source inventory details are syncing in the background."
        )

        static func ready(detail: String) -> StartupSnapshot {
            StartupSnapshot(
                phase: .ready,
                title: "Archive ready",
                detail: detail
            )
        }
    }

    struct CounterpartChip: Identifiable, Hashable, Sendable {
        let label: String
        let term: String

        var id: String { "\(label)\u{1F}\(term)" }
    }

    enum InventorySnapshotState: Sendable, Equatable {
        case unavailable
        case cached
        case liveSummary
        case live
    }

    struct SourceStat: Identifiable, Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let detail: String
        let status: String

        init(id: UUID = UUID(), name: String, detail: String, status: String) {
            self.id = id
            self.name = name
            self.detail = detail
            self.status = status
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case detail
            case status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            name = try container.decode(String.self, forKey: .name)
            detail = try container.decode(String.self, forKey: .detail)
            status = try container.decode(String.self, forKey: .status)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(detail, forKey: .detail)
            try container.encode(status, forKey: .status)
        }
    }

    struct SourceInventorySummary: Equatable, Sendable {
        let totalCount: Int
        let availableCount: Int
        let partialCount: Int
        let missingCount: Int

        static let empty = SourceInventorySummary(
            totalCount: 0,
            availableCount: 0,
            partialCount: 0,
            missingCount: 0
        )

        init(
            totalCount: Int,
            availableCount: Int,
            partialCount: Int,
            missingCount: Int
        ) {
            self.totalCount = totalCount
            self.availableCount = availableCount
            self.partialCount = partialCount
            self.missingCount = missingCount
        }

        init(stats: [SourceStat]) {
            var partialCount = 0
            var missingCount = 0

            for stat in stats {
                switch DictionarySession.classifySourceStatus(stat.status) {
                case .ready:
                    break
                case .partial:
                    partialCount += 1
                case .missing:
                    missingCount += 1
                }
            }

            self.init(
                totalCount: stats.count,
                availableCount: max(0, stats.count - partialCount - missingCount),
                partialCount: partialCount,
                missingCount: missingCount
            )
        }

        var isLoaded: Bool {
            totalCount > 0
        }

        var headline: String {
            if missingCount > 0 {
                return "\(availableCount) ready, \(partialCount) partial, \(missingCount) missing"
            }
            if partialCount > 0 {
                return "\(availableCount) ready, \(partialCount) partial"
            }
            return "\(availableCount) sources ready"
        }
    }

    struct SearchCheckpoint: Equatable, Sendable {
        let term: String
        let intent: QueryIntent
    }

    struct ExplorationGroup: Identifiable, Sendable {
        let id: String
        let title: String
        let items: [String]
    }

    struct ResultCard: Identifiable, Sendable {
        /// Derived from the card's position, source, and headword rather than a
        /// fresh UUID. Repeating a query then yields the same identities, so the
        /// results list is reused instead of torn down and rebuilt, and any
        /// expanded card stays expanded across a refresh.
        let id: String
        let title: String
        let source: String
        let summary: String
        let chips: [String]
        let counterparts: [CounterpartChip]
        let antonyms: [String]
        let relatedTerms: [String]
        let topicTerms: [String]

        init(
            ordinal: Int = 0,
            title: String,
            source: String,
            summary: String,
            chips: [String],
            counterparts: [CounterpartChip] = [],
            antonyms: [String] = [],
            relatedTerms: [String] = [],
            topicTerms: [String] = []
        ) {
            self.id = "\(ordinal)\u{1F}\(source)\u{1F}\(title)"
            self.title = title
            self.source = source
            self.summary = summary.count > 8_000 ? String(summary.prefix(8_000)) : summary
            self.chips = Array(chips.prefix(12))
            self.counterparts = Array(counterparts.prefix(16))
            self.antonyms = Array(antonyms.prefix(16))
            self.relatedTerms = Array(relatedTerms.prefix(16))
            self.topicTerms = Array(topicTerms.prefix(16))
        }
    }

    private let repository: any DictionarySessionRepository
    private let userDefaults: UserDefaults
    private let suggestionDebounceNanoseconds: UInt64
    private let liveSearchDebounceNanoseconds: UInt64
    private let inventoryBootstrapDelayNanoseconds: UInt64
    private let backgroundAssistBootstrapDelayNanoseconds: UInt64
    private let restoreLastLookupOnReady: Bool
    private let searchWatchdogNanoseconds: UInt64
    private let inventoryWaitTimeoutNanoseconds: UInt64
    private let launchQuery: String
    private var lastSearchWasCommitted = false
    private let recentTermsKey = "mongrel.dictionary.recentTerms"
    private let searchFreqKey = "mongrel.dictionary.searchFreq"
    private let lastQueryKey = "mongrel.dictionary.lastQuery"
    private let lastIntentKey = "mongrel.dictionary.lastIntent"
    private let favoriteTermsKey = "mongrel.dictionary.favoriteTerms"
    private let cachedSourceStatsKey = "mongrel.dictionary.cachedSourceStats"
    private var searchFrequency: [String: Int] = [:]
    private var searchHistory: [SearchCheckpoint] = []
    private var searchHistoryIndex: Int? = nil
    private var debounceTask: Task<Void, Never>?
    private var liveSearchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var searchWatchdog: Task<Void, Never>?
    private var lastQueryPersistTask: Task<Void, Never>?
    private var engagementPersistTask: Task<Void, Never>?
    private var calendarDayTask: Task<Void, Never>?
    private var backgroundAssistCompleted = false
    private var pendingRefreshAfterAssist = false
    private var commitBurstWindowStart: UInt64 = 0
    private var commitsInBurst = 0
    static let maxVisibleResultCards = 40
    static let maxQueryLength = DictionaryLookupRequest.maximumTermLength
    static let maximumSavedTerms = 200
    @Published private(set) var savedShelfNotice: String?
    private var searchRevision: UInt = 0
    private var suggestionRevision: UInt = 0

    @Published var query: String = ""
    @Published var queryIntent: QueryIntent = .define
    @Published private(set) var sourceStats: [SourceStat] = []
    @Published private(set) var sourceInventorySummary: SourceInventorySummary = .empty
    @Published private(set) var inventorySnapshotState: InventorySnapshotState = .unavailable
    @Published private(set) var resultCards: [ResultCard] = []
    @Published private(set) var explorationGroups: [ExplorationGroup] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var didYouMean: [String] = []
    @Published private(set) var recentTerms: [String] = []
    @Published private(set) var favoriteTerms: [String] = []
    @Published private(set) var topSearches: [(term: String, count: Int)] = []
    @Published private(set) var hasSearched: Bool = false
    @Published private(set) var lastSearchedTerm: String = ""
    @Published private(set) var lastSearchedIntent: QueryIntent = .define
    @Published private(set) var inFlightTerm: String = ""
    @Published private(set) var lastSearchTimedOut = false
    @Published private(set) var lastTimedOutTerm = ""
    @Published private(set) var hiddenResultCount = 0
    private var lastTimedOutIntent: QueryIntent = .define
    private var inFlightIntent: QueryIntent = .define
    private var inFlightShouldCommit = false
    private var inFlightRecordHistory = false
    private var inFlightTrackEngagement = false
    @Published private(set) var lastSearchDurationMS: Int = 0
    @Published private(set) var lastResultCount: Int = 0
    @Published private(set) var wordOfDay: (term: String, tagline: String) = ("", "")
    @Published private(set) var latencyHistory: [Int] = []
    @Published private(set) var averageSearchDurationMS: Int = 0
    @Published private(set) var p95SearchDurationMS: Int = 0
    @Published private(set) var diagnostics = DiagnosticsSnapshot.empty
    @Published private(set) var startup = StartupSnapshot.warmingSearch

    init(
        repository: any DictionarySessionRepository = DictionaryRepository(),
        userDefaults: UserDefaults = DictionaryPreferences.current,
        suggestionDebounceNanoseconds: UInt64 = 60_000_000,
        liveSearchDebounceNanoseconds: UInt64 = 180_000_000,
        inventoryBootstrapDelayNanoseconds: UInt64 = 0,
        backgroundAssistBootstrapDelayNanoseconds: UInt64 = 80_000_000,
        restoreLastLookupOnReady: Bool = true,
        searchWatchdogNanoseconds: UInt64 = 20_000_000_000,
        inventoryWaitTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.suggestionDebounceNanoseconds = suggestionDebounceNanoseconds
        self.liveSearchDebounceNanoseconds = liveSearchDebounceNanoseconds
        self.inventoryBootstrapDelayNanoseconds = inventoryBootstrapDelayNanoseconds
        self.backgroundAssistBootstrapDelayNanoseconds = backgroundAssistBootstrapDelayNanoseconds
        self.restoreLastLookupOnReady = restoreLastLookupOnReady
        self.searchWatchdogNanoseconds = searchWatchdogNanoseconds
        self.inventoryWaitTimeoutNanoseconds = inventoryWaitTimeoutNanoseconds

        let restoredQuery = String((userDefaults.string(forKey: lastQueryKey) ?? "").prefix(Self.maxQueryLength))
        query = restoredQuery
        launchQuery = restoredQuery
        if let savedIntent = userDefaults.string(forKey: lastIntentKey),
           let resolvedIntent = QueryIntent(rawValue: savedIntent) {
            queryIntent = resolvedIntent
        }
        let storedRecents = (userDefaults.array(forKey: recentTermsKey) as? [String]) ?? []
        let storedFavorites = (userDefaults.array(forKey: favoriteTermsKey) as? [String]) ?? []
        recentTerms = Self.dedupedPreferredTerms(storedRecents, limit: 8)
        favoriteTerms = Self.dedupedPreferredTerms(storedFavorites, limit: Self.maximumSavedTerms)
        if recentTerms != storedRecents {
            userDefaults.set(recentTerms, forKey: recentTermsKey)
        }
        if favoriteTerms != storedFavorites {
            userDefaults.set(favoriteTerms, forKey: favoriteTermsKey)
        }
        if let data = userDefaults.data(forKey: searchFreqKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            searchFrequency = Self.mergedSearchFrequency(decoded)
        }
        applySourceStats(Self.decodeSourceStats(
            from: userDefaults.data(forKey: cachedSourceStatsKey)
        ))
        if !sourceStats.isEmpty {
            inventorySnapshotState = .cached
        }
        topSearches = Self.rankedSearches(
            frequency: searchFrequency,
            preferredTerms: recentTerms + favoriteTerms
        )
        wordOfDay = Self.computeWordOfDay()
        Task { await bootstrapInteractiveSession() }
        calendarDayTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                guard !Task.isCancelled else { return }
                self?.wordOfDay = Self.computeWordOfDay()
            }
        }
    }

    deinit {
        calendarDayTask?.cancel()
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        searchTask?.cancel()
        prefetchTask?.cancel()
        searchWatchdog?.cancel()
        lastQueryPersistTask?.cancel()
        engagementPersistTask?.cancel()
    }

    // MARK: – History management

    func clearHistory() {
        engagementPersistTask?.cancel()
        engagementPersistTask = nil
        recentTerms = []
        searchFrequency = [:]
        topSearches = []
        searchHistory = []
        searchHistoryIndex = nil
        // A result already in flight may finish reading, but must not undo the
        // user's request to forget earlier activity when it eventually arrives.
        inFlightRecordHistory = false
        inFlightTrackEngagement = false
        userDefaults.removeObject(forKey: recentTermsKey)
        userDefaults.removeObject(forKey: searchFreqKey)
    }

    // MARK: – Word of the Day

    private static func computeWordOfDay() -> (term: String, tagline: String) {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % wordOfDayPool.count
        return wordOfDayPool[index]
    }

    private static let wordOfDayPool: [(term: String, tagline: String)] = [
        ("ephemeral",    "Lasting for a very short time"),
        ("sonder",       "The realisation that each passerby has a life as complex as your own"),
        ("liminal",      "Occupying a position at a threshold or boundary"),
        ("petrichor",    "The earthy scent produced when rain falls on dry soil"),
        ("lacuna",       "A gap or missing portion; an unfilled space"),
        ("serendipity",  "The occurrence of fortunate events by chance"),
        ("ineffable",    "Too great or extreme to be expressed in words"),
        ("sanguine",     "Optimistic or positive, especially in a difficult situation"),
        ("mellifluous",  "Sweet or musical; pleasant to hear"),
        ("lugubrious",   "Looking or sounding sad and dismal"),
        ("susurrus",     "A murmuring or whispering sound"),
        ("palimpsest",   "Something altered but still bearing traces of an earlier form"),
        ("equanimity",   "Mental calmness in difficult situations"),
        ("apocryphal",   "Of doubtful authenticity, although widely circulated"),
        ("elegy",        "A poem of serious reflection, typically lamenting the dead"),
        ("tendentious",  "Promoting a particular cause or point of view"),
        ("loquacious",   "Tending to talk a great deal; talkative"),
        ("solipsism",    "The view that the self is all that can be known to exist"),
        ("simulacrum",   "An image or representation of something; an unsatisfying imitation"),
        ("fugacious",    "Tending to disappear; fleeting"),
        ("inchoate",     "Just begun and not fully formed or developed"),
        ("shibboleth",   "A custom or belief distinguishing one group from another"),
        ("quiddity",     "The inherent nature or essence of something"),
        ("esoteric",     "Intended for or understood by only a small number of people"),
        ("abscond",      "To leave hurriedly and secretly, typically to avoid detection"),
        ("pellucid",     "Translucently clear; easily understood"),
        ("concatenate",  "Link things together in a chain or series"),
        ("ennui",        "A feeling of listlessness and dissatisfaction"),
        ("zeitgeist",    "The defining spirit or mood of a particular period"),
        ("hubris",       "Excessive pride or self-confidence; overconfidence leading to ruin"),
        ("pernicious",   "Having a harmful effect, especially in a gradual or subtle way"),
        ("cacophony",    "A harsh, discordant mixture of sounds"),
        ("sesquipedalian","Given to or characterised by the use of long words"),
        ("mercurial",    "Subject to sudden or unpredictable changes of mood"),
        ("obfuscate",    "Make obscure, unclear, or unintelligible"),
        ("numinous",     "Having a mysterious spiritual quality or presence"),
        ("flibbertigibbet", "A frivolous, flighty, or excessively talkative person"),
        ("verisimilitude", "The appearance of being true or real"),
        ("syzygy",       "Alignment of three celestial bodies; a pair of connected or similar things"),
        ("sycophant",    "A person who acts obsequiously to gain advantage"),
        ("perspicacious","Having a ready insight; mentally sharp and discerning"),
        ("fugue",        "A state of flight from reality; a complex contrapuntal composition"),
        ("torpor",       "A state of physical or mental inactivity; sluggishness"),
        ("propitious",   "Giving or indicating a good chance of success; favourable"),
        ("mnemonic",     "A device such as a pattern of letters aiding memorisation"),
        ("cavalier",     "Showing a lack of proper concern; treating serious matters casually"),
        ("redolent",     "Strongly reminiscent or suggestive of something; fragrant"),
        ("trenchant",    "Vigorous or incisive in expression; sharp or caustic"),
        ("lassitude",    "Physical or mental weariness; lack of energy"),
        ("mordant",      "Sharp or caustic; (of a substance) serving to fix dyes"),
    ]

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The field still matches the cards on screen, so suggestion chrome can
    /// stand down and leave the definition as the primary object.
    var isLookupSettled: Bool {
        hasSearched
            && !isSearching
            && lastSearchWasCommitted
            && lastSearchedIntent == queryIntent
            && normalizedLookupKey(for: query) == normalizedLookupKey(for: lastSearchedTerm)
    }

    /// The term Save / Command-D should act on: the cards on the desk while the
    /// field is still being composed, otherwise the typed query.
    var focusedTerm: String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasSearched, !lastSearchedTerm.isEmpty {
            let queryKey = normalizedLookupKey(for: trimmedQuery)
            let displayedKey = normalizedLookupKey(for: lastSearchedTerm)
            if queryKey.isEmpty || queryKey != displayedKey {
                return lastSearchedTerm
            }
        }
        if !trimmedQuery.isEmpty {
            return trimmedQuery
        }
        return lastSearchedTerm
    }

    /// The first suggestion that merely lengthens the typed prefix, offered as
    /// Tab completion rather than an inline ghost.
    var inlineCompletion: String? {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.count >= 2, let candidate = suggestions.first else { return nil }
        let typedKey = normalizedLookupKey(for: typed)
        let candidateKey = normalizedLookupKey(for: candidate)
        guard candidateKey != typedKey, candidateKey.hasPrefix(typedKey) else {
            return nil
        }
        return candidate
    }

    /// Cards remain on screen after the field is emptied, so the desk can say
    /// why the last lookup is still visible.
    var canRetryLookup: Bool {
        !isSearching && retryTarget != nil
    }

    var retryTarget: (term: String, intent: QueryIntent)? {
        let timedOut = lastTimedOutTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if !timedOut.isEmpty {
            return (timedOut, lastTimedOutIntent)
        }
        let displayed = lastSearchedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayed.isEmpty else { return nil }
        return (displayed, lastSearchedIntent)
    }

    var isShowingLastLookupWithoutQuery: Bool {
        hasSearched && !hasQuery && !resultCards.isEmpty
    }

    var canGoBack: Bool {
        guard let index = searchHistoryIndex else { return false }
        return index > 0
    }

    var canGoForward: Bool {
        guard let index = searchHistoryIndex else { return false }
        return index < searchHistory.count - 1
    }

    var currentTermIsFavorite: Bool {
        isFavorite(focusedTerm)
    }

    /// Rebuilt once per completed search rather than on every render pass.
    ///
    /// The inspector rail reads this while the reader types, and the derivation
    /// walks every card four times and normalises each term, so recomputing it
    /// as a stored property removed that work from the typing path.
    private func rebuildExplorationGroups() {
        guard !resultCards.isEmpty else {
            explorationGroups = []
            return
        }

        let focused = normalizedLookupKey(for: lastSearchedTerm)
        let candidates: [(id: String, title: String, terms: [String], limit: Int)] = [
            ("counterparts", "Counterparts", resultCards.flatMap { $0.counterparts.map(\.term) }, 10),
            ("related", "Related", resultCards.flatMap(\.relatedTerms), 12),
            ("topics", "Topics", resultCards.flatMap(\.topicTerms), 12),
            ("antonyms", "Antonyms", resultCards.flatMap(\.antonyms), 10)
        ]

        explorationGroups = candidates.compactMap { candidate in
            let terms = uniqueTerms(from: candidate.terms, excluding: focused)
            guard !terms.isEmpty else { return nil }
            return ExplorationGroup(
                id: candidate.id,
                title: candidate.title,
                items: Array(terms.prefix(candidate.limit))
            )
        }
    }

    private func clearExplorationGroups() {
        if !explorationGroups.isEmpty {
            explorationGroups = []
        }
    }

    private func clearSuggestionChrome() {
        suggestionRevision &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        if !suggestions.isEmpty {
            suggestions = []
        }
        clearDidYouMean()
    }

    private func clearDidYouMean() {
        if !didYouMean.isEmpty {
            didYouMean = []
        }
    }

    private func publishSuggestions(_ next: [String]) {
        if suggestions != next {
            suggestions = next
        }
    }

    private func publishDidYouMean(_ next: [String]) {
        if didYouMean != next {
            didYouMean = next
        }
    }

    var searchPackageText: String {
        let displayedTerm = lastSearchedTerm.isEmpty ? focusedTerm : lastSearchedTerm
        let displayedIntent = isLookupSettled ? lastSearchedIntent : queryIntent
        var lines: [String] = [
            "Mongrel Dictionary",
            "Query: \(displayedTerm)",
            "Mode: \(displayedIntent.rawValue)",
            "Results: \(lastResultCount)"
        ]

        if lastSearchDurationMS > 0 {
            lines.append("Latency: \(lastSearchDurationMS) ms")
        }
        if hiddenResultCount > 0 {
            lines.append("Showing: \(resultCards.count) of \(lastResultCount)")
        }

        let packagedCards = resultCards.prefix(16)
        for card in packagedCards {
            lines.append("")
            lines.append(card.title)
            if !card.chips.isEmpty {
                lines.append("Context: \(card.chips.joined(separator: ", "))")
            }
            lines.append(card.summary)
            if !card.counterparts.isEmpty {
                lines.append("Counterparts: \(card.counterparts.map { "\($0.label): \($0.term)" }.joined(separator: "; "))")
            }
            if !card.antonyms.isEmpty {
                lines.append("Antonyms: \(card.antonyms.joined(separator: ", "))")
            }
            if !card.relatedTerms.isEmpty {
                lines.append("Related terms: \(card.relatedTerms.joined(separator: ", "))")
            }
            if !card.topicTerms.isEmpty {
                lines.append("Topic mesh: \(card.topicTerms.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    var intentPrompt: String {
        promptText(for: queryIntent)
    }

    /// What a lookup mode will actually search, used for the prompt line and for
    /// the help text on each mode button.
    func promptText(for intent: QueryIntent) -> String {
        switch intent {
        case .define:
            return "Definitions, usage, contrasts, and nearby variants."
        case .synonyms:
            return DictionaryCorpusEdition.isPublicCore ? "Related words from Princeton WordNet 3.0." : "Thesaurus-first lookup with reference pivots as fallback."
        case .translation:
            return "Bilingual and multilingual sources with definition context."
        case .slang:
            return "Colloquial English and slang-focused local sources."
        }
    }

    // MARK: – Inventory presentation

    var availableSourceMetricText: String {
        sourceInventorySummary.isLoaded ? "\(sourceInventorySummary.availableCount)" : "…"
    }

    var availableSourceStatusText: String {
        guard sourceInventorySummary.isLoaded else { return "Scanning" }
        if isUsingCachedInventorySnapshot {
            return "\(sourceInventorySummary.availableCount) cached"
        }
        return "\(sourceInventorySummary.availableCount)"
    }

    var archiveInventoryStatusText: String {
        switch inventorySnapshotState {
        case .unavailable:
            return startup.inventoryReady ? "Unavailable" : "Syncing"
        case .cached:
            return startup.inventoryReady ? "Cached" : "Cached + syncing"
        case .liveSummary:
            return startup.inventoryReady ? "Ready + details syncing" : "Syncing"
        case .live:
            return startup.inventoryReady ? "Ready" : "Syncing"
        }
    }

    var sourceHealthHeadline: String {
        guard !sourceStats.isEmpty else {
            return startup.inventoryReady ? "Inventory unavailable" : "Inventory syncing"
        }

        let headline = sourceInventorySummary.headline
        if inventorySnapshotState == .cached {
            return "\(headline) (last known)"
        }
        if inventorySnapshotState == .liveSummary {
            return "\(headline) (details syncing)"
        }
        return headline
    }

    var sourceHealthFocus: [SourceStat] {
        let prioritized = sourceStats.filter {
            switch Self.classifySourceStatus($0.status) {
            case .ready:
                return false
            case .partial, .missing:
                return true
            }
        }
        return Array(prioritized.prefix(6))
    }

    var isUsingCachedInventorySnapshot: Bool {
        inventorySnapshotState == .cached
    }

    var isHydratingInventoryDetails: Bool {
        inventorySnapshotState == .liveSummary
    }

    // Called from .onChange(of: query) — fires suggestions after a short pause,
    // then a slightly later live search so the reading column fills as the
    // reader types rather than waiting on Return.
    func queryDidChange() {
        if query.count > Self.maxQueryLength {
            query = String(query.prefix(Self.maxQueryLength))
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        persistLastQuery(trimmed, immediately: trimmed.isEmpty)
        cancelStaleBackgroundLookups(for: trimmed)

        guard !trimmed.isEmpty else {
            debounceTask?.cancel()
            liveSearchTask?.cancel()
            cancelSearch()
            suggestionRevision &+= 1
            clearSuggestionChrome()
            return
        }
        guard trimmed.count >= 2 else {
            debounceTask?.cancel()
            liveSearchTask?.cancel()
            suggestionRevision &+= 1
            clearSuggestionChrome()
            return
        }
        guard !shouldSuppressLiveLookup(for: trimmed) else {
            debounceTask?.cancel()
            liveSearchTask?.cancel()
            suggestionRevision &+= 1
            clearSuggestionChrome()
            if !inFlightTerm.isEmpty,
               normalizedLookupKey(for: inFlightTerm) != normalizedLookupKey(for: trimmed) {
                cancelSearch()
            }
            return
        }
        debounceTask?.cancel()
        publishSuggestions(localSuggestions(for: trimmed))
        if isExactKnownLocalTerm(trimmed) {
            liveSearchTask?.cancel()
            previewSearch(commit: false)
        } else {
            scheduleLiveSearch(for: trimmed)
        }
        suggestionRevision &+= 1
        clearDidYouMean()
        let revision = suggestionRevision
        debounceTask = Task {
            do {
                if self.suggestionDebounceNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: self.suggestionDebounceNanoseconds)
                }
                let resolvedHits = await repository.suggestedTerms(prefix: trimmed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard revision == self.suggestionRevision else { return }
                    guard self.normalizedLookupKey(for: self.query) == self.normalizedLookupKey(for: trimmed) else { return }
                    self.publishSuggestions(self.mergeSuggestions(
                        local: self.localSuggestions(for: trimmed),
                        remote: resolvedHits
                    ))
                    self.searchIfQueryIsAnExactHeadword(trimmed, suggestions: resolvedHits)
                }

                let shouldAskForDidYouMean = trimmed.count >= 4 || trimmed.contains(" ") || trimmed.contains("-")
                guard shouldAskForDidYouMean, !Task.isCancelled else { return }

                let resolvedDidYouMeanHints = await repository.didYouMean(term: trimmed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard revision == self.suggestionRevision else { return }
                    self.publishDidYouMean(resolvedDidYouMeanHints)
                }
            } catch { /* cancelled — new keystroke */ }
        }
    }

    /// When the typed string is already a known headword, look it up at once
    /// instead of waiting out the live-search debounce. If a longer headword
    /// still starts with that string, preview only — "cat" in "catalog" must
    /// not pin Recents before the reader finishes the word.
    private func searchIfQueryIsAnExactHeadword(_ trimmed: String, suggestions: [String]) {
        let exact = suggestions.contains {
            $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard exact,
              normalizedLookupKey(for: query) == normalizedLookupKey(for: trimmed) else {
            return
        }

        let shouldCommit = !hasLongerHeadwordCompletion(trimmed, suggestions: suggestions)
        let sameDisplayedLookup = normalizedLookupKey(for: lastSearchedTerm) == normalizedLookupKey(for: trimmed)
            && lastSearchedIntent == queryIntent
        if sameDisplayedLookup {
            guard shouldCommit else { return }
            if isSearching,
               normalizedLookupKey(for: inFlightTerm) == normalizedLookupKey(for: trimmed),
               inFlightIntent == queryIntent {
                promoteInFlightLookupToCommitted()
            } else if !isSearching {
                commitCurrentLookupIfNeeded(term: trimmed, intent: queryIntent)
            }
            return
        }

        liveSearchTask?.cancel()
        previewSearch(commit: shouldCommit)
    }

    private func hasLongerHeadwordCompletion(_ trimmed: String, suggestions: [String]) -> Bool {
        let typedKey = normalizedLookupKey(for: trimmed)
        return suggestions.contains { candidate in
            let key = normalizedLookupKey(for: candidate)
            return key != typedKey && key.hasPrefix(typedKey)
        }
    }

    /// Programmatic query writes (chips, restore, select-term) also fire
    /// `queryDidChange`. Do not start a second live lookup for a search that
    /// is already on screen or already in flight.
    private func shouldSuppressLiveLookup(for trimmed: String) -> Bool {
        let key = normalizedLookupKey(for: trimmed)
        if !inFlightTerm.isEmpty, normalizedLookupKey(for: inFlightTerm) == key {
            return true
        }
        return hasSearched
            && normalizedLookupKey(for: lastSearchedTerm) == key
            && lastSearchedIntent == queryIntent
    }

    private func scheduleLiveSearch(for trimmed: String) {
        liveSearchTask?.cancel()
        guard liveSearchDebounceNanoseconds > 0, trimmed.count >= 3 else { return }
        let alreadyShowing = normalizedLookupKey(for: lastSearchedTerm) == normalizedLookupKey(for: trimmed)
            && lastSearchedIntent == queryIntent
        guard !alreadyShowing else { return }

        let delay = liveSearchDelay(for: trimmed)
        guard delay > 0 else {
            previewSearch(commit: false)
            return
        }
        liveSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                let current = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard current == trimmed else { return }
                self.previewSearch(commit: false)
            }
        }
    }

    func selectIntent(_ intent: QueryIntent) {
        queryIntent = intent
        userDefaults.set(intent.rawValue, forKey: lastIntentKey)
        if hasQuery {
            previewSearch()
            return
        }
        guard hasSearched, !lastSearchedTerm.isEmpty else { return }
        query = lastSearchedTerm
        persistLastQuery(lastSearchedTerm, immediately: true)
        previewSearch()
    }

    func selectTerm(_ term: String, searchImmediately: Bool = true) {
        let trimmed = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQueryLength))
        guard !trimmed.isEmpty else { return }
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        query = trimmed
        persistLastQuery(trimmed, immediately: true)
        if searchImmediately {
            previewSearch()
        }
    }

    /// Tab completion: fill the longer suggestion, but do not pin Recents when
    /// that suggestion is still a prefix of an even longer headword.
    func acceptInlineCompletion() {
        guard let completion = inlineCompletion else { return }
        let shouldCommit = !hasLongerHeadwordCompletion(completion, suggestions: suggestions)
        selectTerm(completion, searchImmediately: false)
        previewSearch(commit: shouldCommit)
    }

    func performLookup(_ request: DictionaryLookupRequest) {
        queryIntent = request.intent
        userDefaults.set(request.intent.rawValue, forKey: lastIntentKey)
        selectTerm(request.term)
    }

    /// Empties the field without taking the last cards off the desk.
    func clearSearchField() {
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        cancelSearch()
        query = ""
        clearSuggestionChrome()
        persistLastQuery("", immediately: true)
    }

    func clearQuery() {
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        cancelSearch()
        query = ""
        clearSuggestionChrome()
        resultCards = []
        explorationGroups = []
        hasSearched = false
        lastSearchedTerm = ""
        lastSearchedIntent = .define
        inFlightTerm = ""
        resetInFlightMetadata()
        lastSearchDurationMS = 0
        lastResultCount = 0
        lastSearchWasCommitted = false
        lastSearchTimedOut = false
        lastTimedOutTerm = ""
        lastTimedOutIntent = .define
        hiddenResultCount = 0
        searchHistory = []
        searchHistoryIndex = nil
        persistLastQuery("", immediately: true)
    }

    func isFavorite(_ term: String) -> Bool {
        let normalized = normalizedLookupKey(for: term)
        guard !normalized.isEmpty else { return false }
        return favoriteTerms.contains { normalizedLookupKey(for: $0) == normalized }
    }

    func retryCurrentLookup() {
        guard let target = retryTarget else { return }
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        query = target.term
        queryIntent = target.intent
        lastSearchTimedOut = false
        persistLastQuery(target.term, immediately: true)
        userDefaults.set(target.intent.rawValue, forKey: lastIntentKey)
        performSearch(
            term: target.term,
            intent: target.intent,
            committed: lastSearchWasCommitted || hasSearched,
            recordHistory: false,
            trackEngagement: false,
            bypassCache: true
        )
    }

    func restoreDisplayedQuery() {
        guard !lastSearchedTerm.isEmpty else { return }
        debounceTask?.cancel()
        liveSearchTask?.cancel()
        query = lastSearchedTerm
        queryIntent = lastSearchedIntent
        persistLastQuery(lastSearchedTerm, immediately: true)
        userDefaults.set(lastSearchedIntent.rawValue, forKey: lastIntentKey)
    }

    func forgetRecent(_ term: String) {
        let normalized = normalizedLookupKey(for: term)
        guard !normalized.isEmpty else { return }
        recentTerms.removeAll { normalizedLookupKey(for: $0) == normalized }
        userDefaults.set(recentTerms, forKey: recentTermsKey)
    }

    func removeFavorite(_ term: String) {
        savedShelfNotice = nil
        let normalized = normalizedLookupKey(for: term)
        guard !normalized.isEmpty else { return }
        favoriteTerms.removeAll { normalizedLookupKey(for: $0) == normalized }
        userDefaults.set(favoriteTerms, forKey: favoriteTermsKey)
    }

    func toggleFavorite(term: String? = nil) {
        savedShelfNotice = nil
        guard let rawTerm = DictionaryLookupRequest.normalizedTerm(term ?? focusedTerm) else { return }
        let normalized = normalizedLookupKey(for: rawTerm)
        if let existingIndex = favoriteTerms.firstIndex(where: { normalizedLookupKey(for: $0) == normalized }) {
            favoriteTerms.remove(at: existingIndex)
        } else {
            guard favoriteTerms.count < Self.maximumSavedTerms else {
                savedShelfNotice = "Your Saved Shelf holds \(Self.maximumSavedTerms) words. Remove a saved word before adding another. Nothing was removed."
                return
            }
            favoriteTerms.insert(rawTerm, at: 0)
        }
        userDefaults.set(favoriteTerms, forKey: favoriteTermsKey)
    }

    func goBack() {
        guard let index = searchHistoryIndex, index > 0 else { return }
        let newIndex = index - 1
        searchHistoryIndex = newIndex
        let checkpoint = searchHistory[newIndex]
        query = checkpoint.term
        queryIntent = checkpoint.intent
        performSearch(
            term: checkpoint.term,
            intent: checkpoint.intent,
            committed: true,
            recordHistory: false,
            trackEngagement: false
        )
    }

    func goForward() {
        guard let index = searchHistoryIndex, index < searchHistory.count - 1 else { return }
        let newIndex = index + 1
        searchHistoryIndex = newIndex
        let checkpoint = searchHistory[newIndex]
        query = checkpoint.term
        queryIntent = checkpoint.intent
        performSearch(
            term: checkpoint.term,
            intent: checkpoint.intent,
            committed: true,
            recordHistory: false,
            trackEngagement: false
        )
    }

    func cancelSearch() {
        searchRevision &+= 1
        searchTask?.cancel()
        searchTask = nil
        searchWatchdog?.cancel()
        searchWatchdog = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        isSearching = false
        inFlightTerm = ""
        resetInFlightMetadata()
    }

    func loadSourceStatsSummary() async {
        let inventory = await repository.loadInventorySummary()
        let resolvedStats = inventory.map {
            SourceStat(name: $0.name, detail: $0.detail, status: $0.status)
        }
        if resolvedStats.isEmpty {
            if sourceStats.isEmpty {
                inventorySnapshotState = .unavailable
            }
        } else {
            applySourceStats(resolvedStats)
            inventorySnapshotState = .liveSummary
        }
        await refreshDiagnostics()
    }

    func loadSourceStats() async {
        let inventory = await repository.loadInventory()
        let resolvedStats = inventory.map {
            SourceStat(name: $0.name, detail: $0.detail, status: $0.status)
        }
        if resolvedStats.isEmpty {
            if sourceStats.isEmpty {
                inventorySnapshotState = .unavailable
            }
        } else {
            applySourceStats(resolvedStats)
            inventorySnapshotState = .live
            persistSourceStatsCache(resolvedStats)
        }
        await refreshDiagnostics()
        if startup.inventoryReady {
            startup = .ready(detail: sourceStats.isEmpty ? "Fast lookup is ready. Source-health details will appear as archives are discovered." : sourceHealthHeadline)
        }
    }

    func previewSearch(commit: Bool = true) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            debounceTask?.cancel()
            liveSearchTask?.cancel()
            cancelSearch()
            clearSuggestionChrome()
            return
        }

        // Return after a live preview should pin the term without repeating the
        // lookup. Typing "har" / "harb" / "harbor" must not fill Recents.
        if commit,
           isSearching,
           normalizedLookupKey(for: inFlightTerm) == normalizedLookupKey(for: term),
           inFlightIntent == queryIntent {
            promoteInFlightLookupToCommitted()
            return
        }
        if commit,
           hasSearched,
           !isSearching,
           normalizedLookupKey(for: lastSearchedTerm) == normalizedLookupKey(for: term),
           lastSearchedIntent == queryIntent {
            commitCurrentLookupIfNeeded(term: term, intent: queryIntent)
            return
        }

        performSearch(
            term: term,
            intent: queryIntent,
            committed: commit
        )
    }

    func refreshDiagnostics() async {
        let snapshot = await repository.diagnostics()
        diagnostics = DiagnosticsSnapshot(
            loadedIndices: snapshot.loadedIndices,
            inventoryCached: snapshot.inventoryCached,
            cacheEntries: snapshot.cacheEntries,
            lastSearchProfile: snapshot.lastSearchProfile
        )
    }

    private func recordLatencySample(_ latencyMS: Int) {
        guard latencyMS >= 0 else { return }
        latencyHistory.append(latencyMS)
        if latencyHistory.count > 12 {
            latencyHistory.removeFirst(latencyHistory.count - 12)
        }
        averageSearchDurationMS = latencyHistory.isEmpty ? 0 : latencyHistory.reduce(0, +) / latencyHistory.count
        let sorted = latencyHistory.sorted()
        if sorted.isEmpty {
            p95SearchDurationMS = 0
        } else {
            let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
            p95SearchDurationMS = sorted[index]
        }
    }

    private func bootstrapInteractiveSession() async {
        startup = .warmingSearch
        await repository.prewarm(profile: .launchSearch)
        startup = .syncingInventory
        restoreLastLookupIfNeeded()

        Task(priority: .utility) {
            if self.backgroundAssistBootstrapDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.backgroundAssistBootstrapDelayNanoseconds)
            }
            await self.repository.prewarm(profile: .interactiveBackgroundAssist)
            await self.refreshDiagnostics()
            self.backgroundAssistCompleted = true
            self.refreshDisplayedLookupAfterSourcesGrew()
        }

        Task(priority: .utility) {
            if self.inventoryBootstrapDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.inventoryBootstrapDelayNanoseconds)
            }
            await self.waitForInteractiveSearchToSettleBeforeInventoryBootstrap()
            await self.finishInventoryBootstrap()
        }
    }

    private func waitForInteractiveSearchToSettleBeforeInventoryBootstrap() async {
        let timeout = inventoryWaitTimeoutNanoseconds
        guard timeout > 0 else { return }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ timeout
        while isSearching, DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func finishInventoryBootstrap() async {
        await loadSourceStatsSummary()
        let detail = sourceStats.isEmpty ? "Fast lookup is ready. Source-health details will appear as archives are discovered." : sourceHealthHeadline
        startup = .ready(detail: detail)

        Task(priority: .utility) {
            if self.backgroundAssistBootstrapDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.backgroundAssistBootstrapDelayNanoseconds)
            }
            await self.waitForInteractiveSearchToSettleBeforeInventoryBootstrap()
            await self.loadSourceStats()
        }
    }

    private func performSearch(
        term: String,
        intent: QueryIntent,
        committed: Bool,
        recordHistory: Bool? = nil,
        trackEngagement: Bool? = nil,
        bypassCache: Bool = false
    ) {
        let trimmed = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQueryLength))
        guard !trimmed.isEmpty else { return }

        let searchStart = Date()
        lastSearchTimedOut = false

        if normalizedLookupKey(for: query) == normalizedLookupKey(for: trimmed), query != trimmed {
            query = trimmed
        }
        // A live preview still needs its same-query suggestions to decide
        // whether this is a complete headword. Committing invalidates them.
        if committed { debounceTask?.cancel() }
        liveSearchTask?.cancel()
        cancelSearch()
        if committed {
            clearSuggestionChrome()
        }
        inFlightTerm = trimmed
        inFlightIntent = intent
        inFlightShouldCommit = committed
        inFlightRecordHistory = recordHistory ?? committed
        inFlightTrackEngagement = trackEngagement ?? committed
        persistLastQuery(trimmed, immediately: committed)
        if committed {
            userDefaults.set(intent.rawValue, forKey: lastIntentKey)
        }

        if !backgroundAssistCompleted {
            pendingRefreshAfterAssist = true
        }
        isSearching = true
        searchRevision &+= 1
        let revision = searchRevision
        startSearchWatchdog(revision: revision)
        searchTask = Task {
            let resolvedCards = await repository.search(
                term: trimmed,
                intent: intent,
                bypassCache: bypassCache,
                allowBackgroundEnrichment: committed
            )
            guard !Task.isCancelled else { return }
            let profile = await repository.lastSearchProfile()
            guard !Task.isCancelled else { return }
            let visibleCards = Array(resolvedCards.prefix(Self.maxVisibleResultCards))
            let mappedCards = visibleCards.enumerated().map { ordinal, card in
                ResultCard(
                    ordinal: ordinal,
                    title: card.title,
                    source: card.source,
                    summary: card.summary,
                    chips: card.chips,
                    counterparts: card.counterparts.map { .init(label: $0.label, term: $0.term) },
                    antonyms: card.antonyms,
                    relatedTerms: card.relatedTerms,
                    topicTerms: card.topicTerms
                )
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard revision == self.searchRevision else { return }
                guard self.lookupStillMatches(trimmed, intent: intent) else {
                    self.finishAbandonedSearch()
                    return
                }
                let shouldCommit = self.inFlightShouldCommit
                let shouldRecordHistory = self.inFlightRecordHistory
                let shouldTrackEngagement = self.inFlightTrackEngagement
                if !shouldCommit, mappedCards.isEmpty, !self.resultCards.isEmpty {
                    self.finishInFlightSearch()
                    return
                }
                self.resultCards = mappedCards
                self.hasSearched = true
                self.lastSearchedTerm = trimmed
                self.lastSearchedIntent = intent
                self.lastSearchWasCommitted = shouldCommit
                self.lastResultCount = resolvedCards.count
                self.hiddenResultCount = max(0, resolvedCards.count - visibleCards.count)
                self.lastTimedOutTerm = ""
                self.lastTimedOutIntent = .define
                if shouldCommit {
                    self.rebuildExplorationGroups()
                    self.clearSuggestionChrome()
                } else {
                    self.clearExplorationGroups()
                    self.clearDidYouMean()
                }
                if shouldRecordHistory {
                    self.recordSearchCheckpoint(term: trimmed, intent: intent)
                }
                if shouldTrackEngagement {
                    self.recordRecentAndFrequency(for: trimmed)
                }
                if shouldCommit {
                    self.noteCommittedSearch()
                }
                let measuredLatency = profile?.totalElapsedMS
                    ?? Int(Date().timeIntervalSince(searchStart) * 1000)
                self.lastSearchDurationMS = measuredLatency
                self.recordLatencySample(self.lastSearchDurationMS)
                if let profile {
                    self.diagnostics = DiagnosticsSnapshot(
                        loadedIndices: self.diagnostics.loadedIndices,
                        inventoryCached: self.diagnostics.inventoryCached,
                        cacheEntries: self.diagnostics.cacheEntries,
                        lastSearchProfile: profile
                    )
                }
                self.finishInFlightSearch()
                if shouldCommit, !self.isRapidCommitBurst {
                    self.scheduleRelatedLookupPrefetch()
                }
                if self.backgroundAssistCompleted {
                    self.refreshDisplayedLookupAfterSourcesGrew()
                }
            }

            let needsDidYouMean = committed && (resolvedCards.isEmpty || !resolvedCards.contains(where: {
                $0.chips.contains("exact hit") || $0.chips.contains("direct note hit")
            }))
            guard needsDidYouMean, !Task.isCancelled else { return }

            let resolvedDidYouMeanHints = await repository.didYouMean(term: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard revision == self.searchRevision else { return }
                guard self.lookupStillMatches(trimmed, intent: intent) else { return }
                self.publishDidYouMean(resolvedDidYouMeanHints)
            }
        }
    }

    private func lookupStillMatches(_ term: String, intent: QueryIntent) -> Bool {
        normalizedLookupKey(for: query) == normalizedLookupKey(for: term) && queryIntent == intent
    }

    private func finishInFlightSearch() {
        isSearching = false
        searchTask = nil
        searchWatchdog?.cancel()
        searchWatchdog = nil
        inFlightTerm = ""
        resetInFlightMetadata()
    }

    private func resetInFlightMetadata() {
        inFlightIntent = .define
        inFlightShouldCommit = false
        inFlightRecordHistory = false
        inFlightTrackEngagement = false
    }

    private func promoteInFlightLookupToCommitted() {
        inFlightShouldCommit = true
        inFlightRecordHistory = true
        inFlightTrackEngagement = true
    }

    private func finishAbandonedSearch() {
        finishInFlightSearch()
    }

    private func liveSearchDelay(for trimmed: String) -> UInt64 {
        let configured = liveSearchDebounceNanoseconds
        if trimmed.count >= 6 {
            return min(configured, 110_000_000)
        }
        if trimmed.count >= 4 {
            return min(configured, 160_000_000)
        }
        return configured
    }

    private func knownLocalTerms() -> [String] {
        favoriteTerms + recentTerms + topSearches.map(\.term) + [wordOfDay.term]
    }

    private func isExactKnownLocalTerm(_ trimmed: String) -> Bool {
        let key = normalizedLookupKey(for: trimmed)
        guard key.count >= 3 else { return false }
        return knownLocalTerms().contains { normalizedLookupKey(for: $0) == key }
    }

    private func localSuggestions(for prefix: String) -> [String] {
        let key = normalizedLookupKey(for: prefix)
        guard key.count >= 2 else { return [] }
        return uniqueTerms(from: knownLocalTerms(), excluding: key)
            .filter { normalizedLookupKey(for: $0).hasPrefix(key) }
            .prefix(6)
            .map { $0 }
    }

    private func mergeSuggestions(local: [String], remote: [String]) -> [String] {
        uniqueTerms(from: local + remote, excluding: normalizedLookupKey(for: query))
            .prefix(8)
            .map { $0 }
    }

    private func refreshDisplayedLookupAfterSourcesGrew() {
        guard pendingRefreshAfterAssist else { return }
        guard backgroundAssistCompleted, hasSearched, !isSearching, !lastSearchedTerm.isEmpty else { return }
        guard lookupStillMatches(lastSearchedTerm, intent: lastSearchedIntent) else { return }
        pendingRefreshAfterAssist = false
        performSearch(
            term: lastSearchedTerm,
            intent: lastSearchedIntent,
            committed: lastSearchWasCommitted,
            recordHistory: false,
            trackEngagement: false,
            bypassCache: true
        )
    }

    private func scheduleRelatedLookupPrefetch() {
        prefetchTask?.cancel()
        guard lastSearchWasCommitted, isLookupSettled, !isSearching else { return }
        let seeds = Array(explorationGroups.flatMap(\.items).prefix(2))
        guard !seeds.isEmpty else { return }
        let displayedTerm = lastSearchedTerm
        let intent = lastSearchedIntent
        prefetchTask = Task { [repository] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let stillOnDisplayedTerm = await MainActor.run {
                self.normalizedLookupKey(for: self.lastSearchedTerm) == self.normalizedLookupKey(for: displayedTerm)
                    && self.lastSearchedIntent == intent
                    && !self.isSearching
                    && self.isLookupSettled
            }
            guard stillOnDisplayedTerm else { return }
            for term in seeds {
                guard !Task.isCancelled else { return }
                _ = await repository.search(
                    term: term,
                    intent: intent,
                    bypassCache: false,
                    allowBackgroundEnrichment: false
                )
            }
        }
    }

    private func cancelStaleBackgroundLookups(for trimmed: String) {
        guard !lastSearchedTerm.isEmpty else { return }
        guard normalizedLookupKey(for: trimmed) != normalizedLookupKey(for: lastSearchedTerm) else { return }
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    private func noteCommittedSearch() {
        let now = DispatchTime.now().uptimeNanoseconds
        if commitBurstWindowStart == 0 || now &- commitBurstWindowStart > 2_000_000_000 {
            commitBurstWindowStart = now
            commitsInBurst = 1
        } else {
            commitsInBurst += 1
        }
    }

    private var isRapidCommitBurst: Bool {
        commitsInBurst >= 3
    }

    private func persistLastQuery(_ trimmed: String, immediately: Bool) {
        lastQueryPersistTask?.cancel()
        if immediately {
            userDefaults.set(trimmed, forKey: lastQueryKey)
            return
        }
        lastQueryPersistTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.userDefaults.set(trimmed, forKey: lastQueryKey)
        }
    }

    private func startSearchWatchdog(revision: UInt) {
        searchWatchdog?.cancel()
        guard searchWatchdogNanoseconds > 0 else { return }
        let timeout = searchWatchdogNanoseconds
        searchWatchdog = Task {
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard revision == self.searchRevision, self.isSearching else { return }
                self.lastTimedOutTerm = self.inFlightTerm
                self.lastTimedOutIntent = self.inFlightIntent
                self.lastSearchTimedOut = true
                self.cancelSearch()
            }
        }
    }

    private func restoreLastLookupIfNeeded() {
        guard restoreLastLookupOnReady, !hasSearched, inFlightTerm.isEmpty else { return }
        guard normalizedLookupKey(for: query) == normalizedLookupKey(for: launchQuery) else { return }
        let trimmed = launchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        previewSearch(commit: false)
    }

    private func commitCurrentLookupIfNeeded(term: String, intent: QueryIntent) {
        guard !lastSearchWasCommitted else { return }
        recordSearchCheckpoint(term: term, intent: intent)
        recordRecentAndFrequency(for: term)
        lastSearchWasCommitted = true
        clearSuggestionChrome()
        noteCommittedSearch()
        if !isRapidCommitBurst {
            scheduleRelatedLookupPrefetch()
        }
    }

    private func recordRecentAndFrequency(for term: String) {
        var updated = recentTerms.filter { normalizedLookupKey(for: $0) != normalizedLookupKey(for: term) }
        updated.insert(term, at: 0)
        recentTerms = Array(updated.prefix(8))
        userDefaults.set(recentTerms, forKey: recentTermsKey)

        let frequencyKey = normalizedLookupKey(for: term)
        let priorCount = searchFrequency[frequencyKey, default: 0]
        searchFrequency[frequencyKey] = priorCount == Int.max ? Int.max : priorCount + 1
        if searchFrequency.count > 200 {
            let trimmed = searchFrequency
                .sorted { $0.value > $1.value }
                .prefix(200)
                .map { ($0.key, $0.value) }
            searchFrequency = Dictionary(uniqueKeysWithValues: trimmed)
        }
        topSearches = Self.rankedSearches(
            frequency: searchFrequency,
            preferredTerms: recentTerms + favoriteTerms
        )
        scheduleEngagementPersist()
    }

    private func scheduleEngagementPersist() {
        engagementPersistTask?.cancel()
        engagementPersistTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.persistSearchFrequency()
        }
    }

    private func persistSearchFrequency() {
        if let encoded = try? JSONEncoder().encode(searchFrequency) {
            userDefaults.set(encoded, forKey: searchFreqKey)
        }
    }

    /// Normal termination must not drop writes still waiting for their debounce.
    func flushPendingPersistence() {
        lastQueryPersistTask?.cancel()
        lastQueryPersistTask = nil
        engagementPersistTask?.cancel()
        engagementPersistTask = nil
        userDefaults.set(String(query.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maxQueryLength)), forKey: lastQueryKey)
        userDefaults.set(queryIntent.rawValue, forKey: lastIntentKey)
        persistSearchFrequency()
    }

    private enum SourceHealthClassification {
        case ready
        case partial
        case missing
    }

    nonisolated private static func classifySourceStatus(_ status: String) -> SourceHealthClassification {
        let normalized = status.lowercased()
        if normalized.contains("missing") {
            return .missing
        }
        if normalized.contains("partial") || normalized.contains("queued") {
            return .partial
        }
        return .ready
    }

    private func applySourceStats(_ stats: [SourceStat]) {
        sourceStats = stats
        sourceInventorySummary = SourceInventorySummary(stats: stats)
    }

    private func persistSourceStatsCache(_ stats: [SourceStat]) {
        guard let encoded = try? JSONEncoder().encode(stats) else { return }
        userDefaults.set(encoded, forKey: cachedSourceStatsKey)
    }

    private static func decodeSourceStats(from data: Data?) -> [SourceStat] {
        guard let data,
              let decoded = try? JSONDecoder().decode([SourceStat].self, from: data) else {
            return []
        }
        return decoded
    }

    private func recordSearchCheckpoint(term: String, intent: QueryIntent) {
        let checkpoint = SearchCheckpoint(term: term, intent: intent)
        if let index = searchHistoryIndex, index < searchHistory.count - 1 {
            searchHistory.removeSubrange((index + 1)..<searchHistory.count)
        }
        if let last = searchHistory.last,
           last.intent == checkpoint.intent,
           normalizedLookupKey(for: last.term) == normalizedLookupKey(for: checkpoint.term) {
            searchHistory[searchHistory.count - 1] = checkpoint
        } else {
            searchHistory.append(checkpoint)
            if searchHistory.count > 60 {
                searchHistory.removeFirst(searchHistory.count - 60)
            }
        }
        searchHistoryIndex = max(0, searchHistory.count - 1)
    }

    private func uniqueTerms(from terms: [String], excluding normalizedTerm: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for term in terms {
            let normalized = normalizedLookupKey(for: term)
            guard !normalized.isEmpty, normalized != normalizedTerm, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            ordered.append(term)
        }
        return ordered
    }

    private func normalizedLookupKey(for term: String) -> String {
        Self.normalizedLookupKey(term)
    }

    nonisolated private static func normalizedLookupKey(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private static func dedupedPreferredTerms(_ terms: [String], limit: Int? = nil) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for term in terms {
            let key = normalizedLookupKey(term)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            ordered.append(term)
            if let limit, ordered.count >= limit { break }
        }
        return ordered
    }

    private static func mergedSearchFrequency(_ raw: [String: Int]) -> [String: Int] {
        var merged: [String: Int] = [:]
        for (term, count) in raw {
            let key = normalizedLookupKey(term)
            guard !key.isEmpty else { continue }
            let (sum, overflow) = merged[key, default: 0].addingReportingOverflow(max(0, count))
            merged[key] = overflow ? Int.max : sum
        }
        if merged.count > 200 {
            let trimmed = merged.sorted { $0.value > $1.value }.prefix(200)
            merged = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        return merged
    }

    private static func rankedSearches(
        frequency: [String: Int],
        preferredTerms: [String]
    ) -> [(term: String, count: Int)] {
        frequency
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { key, count in
                let display = preferredTerms.first { normalizedLookupKey($0) == key } ?? key
                return (term: display, count: count)
            }
    }
}
