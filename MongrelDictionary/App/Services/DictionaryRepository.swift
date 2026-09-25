import Foundation
import SQLite3

public actor DictionaryRepository {
    private final class ResourceBundleLocator {}
    private static let classicWordNetDataFiles = ["data.noun", "data.verb", "data.adj", "data.adv"]

    private enum CacheLimits {
        static let search = 120
        static let suggestions = 160
        static let didYouMean = 160
        static let lookupCandidates = 256
        static let fuzzyCandidates = 256
        static let definitionContexts = 192
    }

    public struct CounterpartTag: Codable, Sendable {
        public let label: String
        public let term: String
    }

    public struct SourceInventory: Sendable {
        public let name: String
        public let detail: String
        public let status: String
    }

    public enum InventoryDetailLevel: Sendable {
        case summary
        case detailed
    }

    struct QuickCanaryStatus: Sendable {
        let hasWordNet2025: Bool
        let hasClassicWordNet: Bool
    }

    struct DailyInventoryStatus: Sendable {
        let hasWordNet2025: Bool
        let hasClassicWordNet: Bool
        let hasAmericanWordList: Bool
        let hasBritishWordList: Bool
        let hasSouthAfricanWordList: Bool
        let hasLongmanReference: Bool
    }

    public struct Diagnostics: Sendable {
        public struct CacheEntry: Identifiable, Sendable {
            public let id = UUID()
            public let name: String
            public let count: Int
            public let limit: Int
        }

        public let loadedIndices: [String]
        public let inventoryCached: Bool
        public let cacheEntries: [CacheEntry]
        public let lastSearchProfile: SearchProfile?
    }

    public struct SearchProfile: Sendable {
        public struct SourceTiming: Identifiable, Sendable {
            public let id = UUID()
            public let name: String
            public let elapsedMS: Int
            public let resultCount: Int
        }

        public let term: String
        public let intent: QueryIntent
        public let cacheHit: Bool
        public let totalElapsedMS: Int
        public let sourceTimings: [SourceTiming]
    }

    private struct ReferenceNotesInventorySnapshot: Sendable {
        let notesCount: Int?
        let entriesCount: Int
    }

    struct DeepRecoveryDiagnostics: Sendable {
        struct PhaseTiming: Sendable {
            let name: String
            let elapsedMS: Int
        }

        let term: String
        let usedDirectEntries: Bool
        let standardCandidateCount: Int
        let fuzzyCandidateCount: Int
        let recoveredEntryCount: Int
        let totalElapsedMS: Int
        let phaseTimings: [PhaseTiming]
    }

    public struct SearchCard: Codable, Sendable {
        public let title: String
        public let source: String
        public let summary: String
        public let chips: [String]
        public let counterparts: [CounterpartTag]
        public let antonyms: [String]
        public let relatedTerms: [String]
        public let topicTerms: [String]

        public init(
            title: String,
            source: String,
            summary: String,
            chips: [String],
            counterparts: [CounterpartTag] = [],
            antonyms: [String] = [],
            relatedTerms: [String] = [],
            topicTerms: [String] = []
        ) {
            self.title = title
            self.source = source
            self.summary = summary
            self.chips = chips
            self.counterparts = counterparts
            self.antonyms = antonyms
            self.relatedTerms = relatedTerms
            self.topicTerms = topicTerms
        }
    }

    public enum PrewarmProfile: Sendable {
        case none
        case launchSearch
        case interactiveBackgroundAssist
        case interactiveSession
        case referenceNotes
        case phraseAndSuggestion
        case defineSearch
        case inventory
        case inventoryLight
        case derivedRegional
        case dailyLexical
        case dailyNotes
        case deepLexical
        case deepLexicalCore
        case deepShared
    }

    public init() {
        // Packaged apps must never consult the checkout used to build them.
        // Workbench access is available only through the explicit test initializer.
        let bundle = Bundle(for: ResourceBundleLocator.self)
        resourceBundle = bundle
        dictionaryRootURL = bundle.bundleURL
    }

    /// Lets packaged-runtime tests exclude the developer's untracked corpora.
    init(workspaceRootURL: URL) {
        self.dictionaryRootURL = workspaceRootURL
        self.resourceBundle = Bundle(for: ResourceBundleLocator.self)
    }

    /// Fault-injection seam: missing and damaged resources must be recoverable.
    init(workspaceRootURL: URL, resourceBundle: Bundle) {
        self.dictionaryRootURL = workspaceRootURL
        self.resourceBundle = resourceBundle
    }

    private let fileManager = FileManager.default
    private let dictionaryRootURL: URL
    private lazy var authoringNotesURL: URL = {
        dictionaryRootURL
            .appendingPathComponent("MongrelDictionary")
            .appendingPathComponent("ReferenceNotesAuthoring")
    }()

    private var ooThesaurus: [String: [String]]?
    private var mobyThesaurus: [String: [String]]?
    private var ooSortedHeadwords: [String]?
    private var mobySortedHeadwords: [String]?
    private var ooThesaurusHeadwords: Set<String>?
    private var mobyThesaurusHeadwords: Set<String>?
    private var freeDictPairs: [FreeDictPair]?
    private var zaMafokoEntries: [ZAMafokoEntry]?
    private var wordNetIndex: WordNetIndex?
    private var wordNetClassicIndex: WordNetClassicIndex?
    private var fastLookupIndex: FastLookupIndex?
    private var fastLookupStore: FastLookupStore?
    private var synonymLookupStore: CardLookupStore?
    private var translationLookupStore: CardLookupStore?
    private var aussieDictionaryIndex: AussieDictionaryIndex?
    private var regionalEnglishIndex: RegionalEnglishIndex?
    private var referenceNotesIndex: ReferenceNotesIndex?
    private var referenceNotesStore: ReferenceNotesStore?
    private var searchLexicon: SearchLexicon?
    private var deepLookupLexicon: SearchLexicon?
    private var inventorySummaryCache: [SourceInventory]?
    private var inventoryCache: [SourceInventory]?
    private var referenceNotesInventorySnapshot: ReferenceNotesInventorySnapshot?
    private var regionalEnglishRegionCounts: [String: Int]?
    private var searchCache: [SearchCacheKey: [SearchCard]] = [:]
    private var searchCacheOrder: [SearchCacheKey] = []
    private var suggestionsCache: [String: [String]] = [:]
    private var suggestionsCacheOrder: [String] = []
    private var didYouMeanCache: [String: [String]] = [:]
    private var didYouMeanCacheOrder: [String] = []
    private var standardLookupCandidatesCache: [String: [String]] = [:]
    private var standardLookupCandidatesCacheOrder: [String] = []
    private var lookupCandidatesCache: [String: [String]] = [:]
    private var lookupCandidatesCacheOrder: [String] = []
    private var fuzzyHeadwordCandidatesCache: [String: [String]] = [:]
    private var fuzzyHeadwordCandidatesCacheOrder: [String] = []
    private var definitionContextCache: [String: DefinitionContext] = [:]
    private var definitionContextCacheOrder: [String] = []
    private var normalizedLookupCache: [String: String] = [:]
    private var normalizedLookupCacheOrder: [String] = []
    private var defineEnrichmentInFlight: Set<SearchCacheKey> = []
    private var defineEnrichmentTask: Task<Void, Never>?
    private var defineEnrichmentGeneration: UInt = 0
    private var latestSearchProfile: SearchProfile?
    private var activeSearchGeneration: UInt = 0
    private let resourceBundle: Bundle

    private func bundledResourceURL(fileName: String) -> URL? {
        resourceBundle.url(forResource: fileName, withExtension: nil)
    }

    private func offlineArchiveFallbackURL(fileName: String) -> URL {
        dictionaryRootURL
            .appendingPathComponent("MongrelDictionary")
            .appendingPathComponent("App")
            .appendingPathComponent("Data")
            .appendingPathComponent("OfflineArchives")
            .appendingPathComponent(fileName)
    }

    private func packagedArchiveURL(fileName: String) -> URL {
        bundledResourceURL(fileName: fileName) ?? offlineArchiveFallbackURL(fileName: fileName)
    }

    private func packagedArchiveExists(fileName: String) -> Bool {
        fileManager.fileExists(atPath: packagedArchiveURL(fileName: fileName).path)
    }

    private func loadBundledArchive<T: Decodable>(fileName: String, as type: T.Type = T.self) -> T? {
        let url = bundledResourceURL(fileName: fileName) ?? offlineArchiveFallbackURL(fileName: fileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListDecoder().decode(type, from: data)
    }

    private func resourceURL(fileName: String, fallbackRelativePath: String) -> URL {
        bundledResourceURL(fileName: fileName)
            ?? dictionaryRootURL.appendingPathComponent(fallbackRelativePath)
    }

    private func workspaceResourceURL(relativePath: String) -> URL {
        dictionaryRootURL.appendingPathComponent(relativePath)
    }

    private func inventoryRawResourceURL(fileName: String, fallbackRelativePath: String) -> URL {
        let workspaceURL = workspaceResourceURL(relativePath: fallbackRelativePath)
        if fileManager.fileExists(atPath: workspaceURL.path) {
            return workspaceURL
        }
        return resourceURL(fileName: fileName, fallbackRelativePath: fallbackRelativePath)
    }

    private func classicWordNetFileURL(named fileName: String) -> URL? {
        if let bundled = bundledResourceURL(fileName: fileName) {
            return bundled
        }

        let preferred = dictionaryRootURL.appendingPathComponent("dict").appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let fallback = dictionaryRootURL.appendingPathComponent("WordNet-3.0/dict").appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fallback.path) {
            return fallback
        }

        return nil
    }

    public func loadInventory(detailLevel: InventoryDetailLevel = .detailed) -> [SourceInventory] {
        switch detailLevel {
        case .summary:
            if let inventoryCache {
                return inventoryCache
            }
            if let inventorySummaryCache {
                return inventorySummaryCache
            }
        case .detailed:
            if let inventoryCache {
                return inventoryCache
            }
        }

        let inventory = buildInventory(detailLevel: detailLevel)
        switch detailLevel {
        case .summary:
            inventorySummaryCache = inventory
        case .detailed:
            inventorySummaryCache = inventory
            inventoryCache = inventory
        }
        return inventory
    }

    private func buildInventory(detailLevel: InventoryDetailLevel) -> [SourceInventory] {
        [
            sourceInventory(
                name: "WordNet 2025 (OEWN XML)",
                detail: "Live · SAX-parsed on first search · WordNet® attribution required (Princeton)",
                relativePath: "english-wordnet-2025.xml"
            ),
            sourceInventoryWordNetClassic(),
            sourceInventoryAustralianEnglish(detailLevel: detailLevel),
            sourceInventoryEnglishRegional(
                name: "English (American) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (American).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryEnglishRegional(
                name: "English (Australian) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (Australian).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryEnglishRegional(
                name: "English (British) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (British).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryEnglishRegional(
                name: "English (Canadian) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (Canadian).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryEnglishRegional(
                name: "English (New Zealand) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (New Zealand).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryEnglishRegional(
                name: "English (South African) word list",
                relativePath: "01MAY2026_Resources/Dictionaries-master/English (South African).dic",
                detailLevel: detailLevel
            ),
            sourceInventoryReferenceNotes(detailLevel: detailLevel),
            sourceInventoryOpenOfficeThesaurus(detailLevel: detailLevel),
            sourceInventoryMobyThesaurus(detailLevel: detailLevel),
            sourceInventory(name: "FreeDict", detail: "Bilingual TEI dictionaries", relativePath: "fd-dictionaries-master"),
            sourceInventoryZAMafoko(detailLevel: detailLevel),
        ]
    }

    func quickCanaryStatus() -> QuickCanaryStatus {
        let wordNet2025URL = resourceURL(
            fileName: "english-wordnet-2025.xml",
            fallbackRelativePath: "english-wordnet-2025.xml"
        )

        return QuickCanaryStatus(
            hasWordNet2025: packagedArchiveExists(fileName: "WordNet2025.mgrt") || fileManager.fileExists(atPath: wordNet2025URL.path),
            hasClassicWordNet: packagedArchiveExists(fileName: "WordNetClassic.mgrt") || hasCompleteClassicWordNetData()
        )
    }

    func dailyInventoryStatus() -> DailyInventoryStatus {
        let wordNet2025URL = resourceURL(
            fileName: "english-wordnet-2025.xml",
            fallbackRelativePath: "english-wordnet-2025.xml"
        )
        let americanURL = resourceURL(
            fileName: "English (American).dic",
            fallbackRelativePath: "01MAY2026_Resources/Dictionaries-master/English (American).dic"
        )
        let britishURL = resourceURL(
            fileName: "English (British).dic",
            fallbackRelativePath: "01MAY2026_Resources/Dictionaries-master/English (British).dic"
        )
        let southAfricanURL = resourceURL(
            fileName: "English (South African).dic",
            fallbackRelativePath: "01MAY2026_Resources/Dictionaries-master/English (South African).dic"
        )
        let longmanURL = resourceURL(
            fileName: "longman-modern-english-dictionary-2nbsped-0582555124-9780582555129_compress.pdf",
            fallbackRelativePath: "longman-modern-english-dictionary-2nbsped-0582555124-9780582555129_compress.pdf"
        )
        let regions = loadRegionalEnglishRegionCounts() ?? [:]
        loadReferenceNoteArtifacts()
        let sourceTitles = referenceNotesStore?.sourceTitles ?? referenceNotesIndex?.sourceTitles ?? []
        return DailyInventoryStatus(
            hasWordNet2025: packagedArchiveExists(fileName: "WordNet2025.mgrt") || fileManager.fileExists(atPath: wordNet2025URL.path),
            hasClassicWordNet: packagedArchiveExists(fileName: "WordNetClassic.mgrt") || hasCompleteClassicWordNetData(),
            hasAmericanWordList: (regions["American"] ?? 0) > 0 || fileManager.fileExists(atPath: americanURL.path),
            hasBritishWordList: (regions["British"] ?? 0) > 0 || fileManager.fileExists(atPath: britishURL.path),
            hasSouthAfricanWordList: (regions["South African"] ?? 0) > 0 || fileManager.fileExists(atPath: southAfricanURL.path),
            hasLongmanReference: sourceTitles.contains("Longman Modern English Dictionary") || fileManager.fileExists(atPath: longmanURL.path)
        )
    }

    func referenceNotesProbe(term: String) async -> [SearchCard] {
        await searchReferenceNotes(term: term)
    }

    struct TimedProbeResult: Sendable {
        let cards: [SearchCard]
        let elapsedMS: Int
    }

    func referenceNotesTimedProbe(term: String) async -> TimedProbeResult {
        let start = DispatchTime.now().uptimeNanoseconds
        let cards = await searchReferenceNotes(term: term)
        return TimedProbeResult(cards: cards, elapsedMS: elapsedMS(since: start))
    }

    func referenceNotesDeepProbe(term: String) async -> [SearchCard] {
        await searchReferenceNotes(term: term, lexiconScope: .deepLookup)
    }

    func referenceNotesRecoveryProbe(term: String) async -> [SearchCard] {
        await searchReferenceNotesRecovery(term: term, lexiconScope: .deepLookup)
    }

    func referenceNotesRecoveryDiagnosticsProbe(term: String) async -> DeepRecoveryDiagnostics {
        await referenceNotesRecoveryDiagnostics(term: term, lexiconScope: .deepLookup)
    }

    func wordNetClassicProbe(term: String) async -> [SearchCard] {
        await searchWordNetClassic(term: term)
    }

    func synonymIntentProbe(term: String) async -> [SearchCard] {
        let normalizedQuery = normalizedLookupKey(term)
        let cards = await (
            searchThesaurusFusion(term: term) +
            searchOpenOfficeThesaurus(term: term) +
            searchMobyThesaurus(term: term)
        )
        let ranked = rankSearchCards(
            cards.filter { intentSourceGroup($0.source) == .thesaurus || $0.source == "Reference pivots" },
            query: normalizedQuery
        )

        if !ranked.isEmpty {
            return ranked
        }

        let pivots = await searchReferencePivots(term: term)
        return rankSearchCards(pivots, query: normalizedQuery)
    }

    func synonymAvailabilityProbe(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        let standardCandidates = standardLookupCandidates(for: normalized)
        let ooHeadwords = loadOpenOfficeThesaurusHeadwordSet()
        let mobyHeadwords = loadMobyThesaurusHeadwordSet()

        guard let matched = standardCandidates.first(where: { candidate in
            ooHeadwords.contains(candidate) || mobyHeadwords.contains(candidate)
        }) else {
            return []
        }

        var backing: [String] = []
        if ooHeadwords.contains(matched) {
            backing.append("OpenOffice")
        }
        if mobyHeadwords.contains(matched) {
            backing.append("Moby")
        }

        var summary = "\(matched.capitalized) is present in the packaged \(backing.joined(separator: " + ")) thesaurus headword archives, so synonym-mode has direct local thesaurus backing for this lemma."
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "Thesaurus availability probe",
                summary: summary,
                chips: ["thesaurus", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)] + backing
            )
        ]
    }

    func derivedEnglishProbe(term: String) async -> [SearchCard] {
        await searchDerivedEnglishForm(term: term)
    }

    func regionalEnglishProbe(term: String) async -> [SearchCard] {
        await searchRegionalEnglish(term: term)
    }

    func regionalSpellingProbe(term: String) async -> [SearchCard] {
        await searchRegionalSpellingNote(term: term)
    }

    func didYouMeanDeepProbe(term: String) async -> [String] {
        await didYouMean(term: term, lexiconScope: .deepLookup)
    }

    func derivedEnglishLightProbe(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }
        guard let inferred = inferredDerivedMeaningClassicOnly(for: normalized) else { return [] }

        var summary = "Derived from '\(inferred.base)'. \(term.capitalized) means \(inferred.shortDefinition)."
        if let baseDefinition = inferred.baseDefinitions.first {
            summary += " Base sense: \(baseDefinition)"
        }
        if !inferred.relatedTerms.isEmpty {
            summary += " Related word-family terms: \(inferred.relatedTerms.prefix(8).joined(separator: ", "))."
        }

        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        if let regions = regionalEnglishIndex?.regionsByHeadword[normalized], !regions.isEmpty {
            summary += " Attested in the \(regions.joined(separator: ", ")) regional wordlists."
        }

        return [
            SearchCard(
                title: term.capitalized,
                source: "English word-family inference",
                summary: summary,
                chips: [
                    "derived form",
                    inferred.kind.label,
                    "base: \(inferred.base)"
                ]
            )
        ]
    }

    func derivedEnglishHeuristicProbe(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }
        guard let candidate = derivationalBaseCandidates(for: normalized).first else { return [] }

        var summary = "Derived from '\(candidate.base)'. \(term.capitalized) means \(candidate.kind.definition(for: term, base: candidate.base))."
        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        if let regions = regionalEnglishIndex?.regionsByHeadword[normalized], !regions.isEmpty {
            summary += " Attested in the \(regions.joined(separator: ", ")) regional wordlists."
        }

        return [
            SearchCard(
                title: term.capitalized,
                source: "English word-family inference",
                summary: summary,
                chips: [
                    "derived form",
                    candidate.kind.label,
                    "base: \(candidate.base)"
                ]
            )
        ]
    }

    func regionalSpellingLightProbe(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        guard let regionalEnglishIndex else { return [] }

        let standardCandidates = standardLookupCandidates(for: normalized)
        let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
            regionalEnglishIndex.regionsByHeadword[$0] != nil
        }
        guard let matched = candidates.first,
              let regions = regionalEnglishIndex.regionsByHeadword[matched],
              !regions.isEmpty else {
            return []
        }

        for americanForm in regionalSpellingBaseCandidates(for: matched) where americanForm != matched {
            let label = regionalSpellingLabel(for: regions)
            var summary = "\(matched.capitalized) is a \(label) spelling variant of '\(americanForm)'."
            summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)

            return [
                SearchCard(
                    title: matched == normalized ? term.capitalized : matched.capitalized,
                    source: "Regional spelling note",
                    summary: summary,
                    chips: ["regional spelling", "base: \(americanForm)", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)] + Array(regions.prefix(3)),
                    counterparts: [.init(label: "\(label) counterpart", term: americanForm)]
                )
            ]
        }

        return []
    }

    public func prewarm(includeHeavyIndices: Bool = false) {
        loadReferenceNoteArtifacts()
        ensureReferenceNotesIndexLoaded()
        loadSearchArtifacts()
        loadRegionalArtifacts()
        loadAustralianArtifacts()
        loadClassicWordNetArtifacts()
        loadThesaurusArtifacts()
        _ = loadInventory()

        if includeHeavyIndices {
            loadModernWordNetArtifacts()
        }
    }

    public func prewarm(profile: PrewarmProfile) {
        switch profile {
        case .none:
            return
        case .launchSearch:
            prewarmLaunchSearch()
        case .interactiveBackgroundAssist:
            prewarmInteractiveBackgroundAssist()
        case .interactiveSession:
            prewarmLaunchSearch()
            prewarmInteractiveBackgroundAssist()
        case .referenceNotes:
            loadReferenceNoteArtifacts()
        case .phraseAndSuggestion:
            loadReferenceNoteArtifacts()
            loadSearchArtifacts()
            loadRegionalArtifacts()
            loadAustralianArtifacts()
        case .defineSearch:
            prewarmLaunchSearch()
            prewarmInteractiveBackgroundAssist()
        case .inventory:
            loadReferenceNoteArtifacts()
            ensureReferenceNotesIndexLoaded()
            loadSearchArtifacts()
            loadRegionalArtifacts()
            loadAustralianArtifacts()
            loadClassicWordNetArtifacts()
            loadModernWordNetArtifacts()
            loadThesaurusArtifacts()
            _ = loadInventory(detailLevel: .detailed)
        case .inventoryLight:
            _ = loadInventory(detailLevel: .summary)
        case .derivedRegional:
            loadRegionalArtifacts()
            loadClassicWordNetArtifacts()
        case .dailyLexical:
            loadRegionalArtifacts()
            loadThesaurusHeadwordArtifacts()
            loadThesaurusArtifacts()
        case .dailyNotes:
            loadReferenceNoteArtifacts()
        case .deepLexical:
            loadRegionalArtifacts()
            loadClassicWordNetArtifacts()
            loadThesaurusHeadwordArtifacts()
            loadThesaurusArtifacts()
        case .deepLexicalCore:
            loadClassicWordNetArtifacts()
            loadThesaurusHeadwordArtifacts()
            loadThesaurusArtifacts()
        case .deepShared:
            loadReferenceNoteArtifacts()
            loadDeepLookupArtifacts()
            loadRegionalArtifacts()
        }
    }

    private func prewarmLaunchSearch() {
        loadFastLookupArtifacts()
        loadSynonymLookupArtifacts()
        loadTranslationLookupArtifacts()
    }

    private func prewarmInteractiveBackgroundAssist() {
        loadReferenceNoteArtifacts()
        loadSearchArtifacts()
        loadRegionalArtifacts()
        loadAustralianArtifacts()
        loadThesaurusHeadwordArtifacts()
    }

    public func lastSearchProfile() -> SearchProfile? {
        latestSearchProfile
    }

    public func diagnostics() -> Diagnostics {
        var loadedIndices: [String] = []
        if wordNetIndex != nil { loadedIndices.append("WordNet 2025") }
        if wordNetClassicIndex != nil { loadedIndices.append("WordNet classic") }
        if fastLookupStore != nil || fastLookupIndex != nil { loadedIndices.append("Fast lookup") }
        if synonymLookupStore != nil { loadedIndices.append("Synonym lookup") }
        if translationLookupStore != nil { loadedIndices.append("Translation lookup") }
        if referenceNotesStore != nil { loadedIndices.append("Reference notes store") }
        if referenceNotesIndex != nil { loadedIndices.append("Reference notes index") }
        if referenceNotesStore != nil || referenceNotesIndex != nil { loadedIndices.append("Reference notes") }
        if regionalEnglishIndex != nil { loadedIndices.append("Regional English") }
        if aussieDictionaryIndex != nil { loadedIndices.append("Aussie dictionary") }
        if searchLexicon != nil { loadedIndices.append("Search lexicon") }
        if deepLookupLexicon != nil { loadedIndices.append("Deep lookup lexicon") }
        if ooThesaurus != nil { loadedIndices.append("OpenOffice thesaurus") }
        if mobyThesaurus != nil { loadedIndices.append("Moby thesaurus") }
        if freeDictPairs != nil { loadedIndices.append("FreeDict") }
        if zaMafokoEntries != nil { loadedIndices.append("ZA Mafoko") }

        let cacheEntries = [
            Diagnostics.CacheEntry(name: "Search", count: searchCache.count, limit: CacheLimits.search),
            Diagnostics.CacheEntry(name: "Suggestions", count: suggestionsCache.count, limit: CacheLimits.suggestions),
            Diagnostics.CacheEntry(name: "Did-you-mean", count: didYouMeanCache.count, limit: CacheLimits.didYouMean),
            Diagnostics.CacheEntry(name: "Standard lookup", count: standardLookupCandidatesCache.count, limit: CacheLimits.lookupCandidates),
            Diagnostics.CacheEntry(name: "Lookup", count: lookupCandidatesCache.count, limit: CacheLimits.lookupCandidates),
            Diagnostics.CacheEntry(name: "Fuzzy lookup", count: fuzzyHeadwordCandidatesCache.count, limit: CacheLimits.fuzzyCandidates),
            Diagnostics.CacheEntry(name: "Normalized lookup", count: normalizedLookupCache.count, limit: 4096),
            Diagnostics.CacheEntry(name: "Definition contexts", count: definitionContextCache.count, limit: CacheLimits.definitionContexts),
            Diagnostics.CacheEntry(name: "Reference rows", count: referenceNotesStore?.cachedRowCount ?? 0, limit: ReferenceNotesStore.rowCacheLimit),
            Diagnostics.CacheEntry(name: "Synonym rows", count: synonymLookupStore?.cachedRowCount ?? 0, limit: CardLookupStore.rowCacheLimit),
            Diagnostics.CacheEntry(name: "Translation rows", count: translationLookupStore?.cachedRowCount ?? 0, limit: CardLookupStore.rowCacheLimit),
        ]

        return Diagnostics(
            loadedIndices: loadedIndices,
            inventoryCached: inventoryCache != nil || inventorySummaryCache != nil,
            cacheEntries: cacheEntries,
            lastSearchProfile: latestSearchProfile
        )
    }

    private func loadReferenceNoteArtifacts() {
        if referenceNotesStore == nil {
            referenceNotesStore = openReferenceNotesStore()
        }
        if referenceNotesStore == nil, referenceNotesIndex == nil {
            referenceNotesIndex = loadReferenceNotesIndex()
        }
    }

    private func ensureReferenceNotesIndexLoaded() {
        if referenceNotesIndex == nil {
            referenceNotesIndex = loadReferenceNotesIndex()
        }
    }

    private func loadFastLookupArtifacts() {
        if fastLookupStore == nil {
            fastLookupStore = openFastLookupStore()
        }
        if fastLookupStore == nil, fastLookupIndex == nil {
            fastLookupIndex = loadFastLookupIndex()
        }
    }

    private func loadSynonymLookupArtifacts() {
        if synonymLookupStore == nil {
            synonymLookupStore = openCardLookupStore(fileName: "SynonymLookup.sqlite3", tableName: "synonym_cards")
        }
    }

    private func loadTranslationLookupArtifacts() {
        if translationLookupStore == nil {
            translationLookupStore = openCardLookupStore(fileName: "TranslationLookup.sqlite3", tableName: "translation_cards")
        }
    }

    private func loadThesaurusHeadwordArtifacts() {
        _ = loadOpenOfficeThesaurusHeadwordSet()
        _ = loadMobyThesaurusHeadwordSet()
    }

    private func loadSearchArtifacts() {
        if searchLexicon == nil { searchLexicon = loadSearchLexicon() }
    }

    private func loadDeepLookupArtifacts() {
        if deepLookupLexicon == nil { deepLookupLexicon = loadDeepLookupLexicon() }
    }

    private func loadRegionalArtifacts() {
        if regionalEnglishIndex == nil { regionalEnglishIndex = loadRegionalEnglishIndex() }
    }

    private func loadAustralianArtifacts() {
        if aussieDictionaryIndex == nil { aussieDictionaryIndex = loadAussieDictionaryIndex() }
    }

    private func loadClassicWordNetArtifacts() {
        if wordNetClassicIndex == nil { wordNetClassicIndex = loadWordNetClassicIndex() }
    }

    private func loadModernWordNetArtifacts() {
        if wordNetIndex == nil { wordNetIndex = loadWordNetIndex() }
    }

    private func loadThesaurusArtifacts() {
        if ooThesaurus == nil { ooThesaurus = loadOpenOfficeThesaurus() }
        if mobyThesaurus == nil { mobyThesaurus = loadMobyThesaurus() }

        if ooSortedHeadwords == nil, let ooThesaurus {
            ooSortedHeadwords = ooThesaurus.keys.sorted()
        }
        if mobySortedHeadwords == nil, let mobyThesaurus {
            mobySortedHeadwords = mobyThesaurus.keys.sorted()
        }
    }

    private func loadOpenOfficeThesaurusHeadwordSet() -> Set<String> {
        if let ooThesaurusHeadwords {
            return ooThesaurusHeadwords
        }
        if let archive: WordListArchive = loadBundledArchive(fileName: "OpenOfficeThesaurusHeadwords.mgrt") {
            let headwords = Set(archive.headwords)
            ooThesaurusHeadwords = headwords
            return headwords
        }
        if ooThesaurus == nil {
            ooThesaurus = loadOpenOfficeThesaurus()
        }
        let headwords = ooThesaurus.map { Set($0.keys) } ?? Set<String>()
        ooThesaurusHeadwords = headwords
        return headwords
    }

    private func loadMobyThesaurusHeadwordSet() -> Set<String> {
        if let mobyThesaurusHeadwords {
            return mobyThesaurusHeadwords
        }
        if let archive: WordListArchive = loadBundledArchive(fileName: "MobyThesaurusHeadwords.mgrt") {
            let headwords = Set(archive.headwords)
            mobyThesaurusHeadwords = headwords
            return headwords
        }
        if mobyThesaurus == nil {
            mobyThesaurus = loadMobyThesaurus()
        }
        let headwords = mobyThesaurus.map { Set($0.keys) } ?? Set<String>()
        mobyThesaurusHeadwords = headwords
        return headwords
    }

    public func search(
        term: String,
        intent: QueryIntent = .define,
        bypassCache: Bool = false,
        allowBackgroundEnrichment: Bool = true
    ) async -> [SearchCard] {
        if Task.isCancelled { return [] }
        if allowBackgroundEnrichment {
            activeSearchGeneration &+= 1
        }
        let generation = activeSearchGeneration
        if isStaleSearch(generation) { return [] }
        let normalizedQuery = normalizedLookupKey(term)
        let cacheKey = SearchCacheKey(term: normalizedQuery, intent: intent)
        if !bypassCache, let cached = cacheLookup(cacheKey: cacheKey, in: &searchCache, order: &searchCacheOrder) {
            latestSearchProfile = SearchProfile(
                term: normalizedQuery,
                intent: intent,
                cacheHit: true,
                totalElapsedMS: 0,
                sourceTimings: []
            )
            return cached
        }
        let searchStartNS = DispatchTime.now().uptimeNanoseconds
        let sourceResults: [TimedSourceResult]
        var shouldCacheResults = allowBackgroundEnrichment
        if intent == .define {
            if let fastResults = await searchFastDefineSources(term: term, normalizedQuery: normalizedQuery) {
                sourceResults = fastResults
                shouldCacheResults = true
            } else if allowBackgroundEnrichment {
                sourceResults = await searchLightweightDefineSources(term: term)
                if !isStaleSearch(generation),
                   normalizedQuery.count >= 3,
                   shouldEnrichLightweightDefineResults(sourceResults) {
                    scheduleDefineEnrichmentIfNeeded(cacheKey: cacheKey, term: term, normalizedQuery: normalizedQuery)
                }
            } else {
                sourceResults = await searchPreviewDefineSources(term: term)
            }
        } else if intent == .synonyms {
            if let fastResults = await searchFastSynonymSources(term: term, normalizedQuery: normalizedQuery) {
                sourceResults = fastResults
                shouldCacheResults = true
            } else if allowBackgroundEnrichment {
                sourceResults = await searchSources(term: term, intent: intent)
            } else {
                sourceResults = await searchPreviewDefineSources(term: term)
            }
        } else if intent == .translation {
            if let fastResults = await searchFastTranslationSources(term: term, normalizedQuery: normalizedQuery) {
                sourceResults = fastResults
                shouldCacheResults = true
            } else if translationLookupStore != nil {
                if let fastContextResults = await searchFastDefineSources(term: term, normalizedQuery: normalizedQuery) {
                    sourceResults = fastContextResults
                    shouldCacheResults = true
                } else if allowBackgroundEnrichment {
                    sourceResults = await searchLightweightTranslationContextSources(term: term)
                } else {
                    sourceResults = await searchPreviewTranslationSources(term: term)
                }
            } else {
                sourceResults = await searchSources(term: term, intent: intent)
            }
        } else if intent == .slang {
            if let fastResults = await searchFastSlangSources(term: term, normalizedQuery: normalizedQuery) {
                sourceResults = fastResults
                shouldCacheResults = true
            } else if allowBackgroundEnrichment {
                sourceResults = await searchSources(term: term, intent: intent)
            } else {
                sourceResults = await searchPreviewDefineSources(term: term)
            }
        } else {
            sourceResults = await searchSources(term: term, intent: intent)
        }
        if isStaleSearch(generation) { return [] }
        let cards = finalizedSearchCards(
            term: term,
            intent: intent,
            normalizedQuery: normalizedQuery,
            sourceResults: sourceResults
        )

        if shouldCacheResults {
            storeCache(
                cacheKey: cacheKey,
                value: cards,
                in: &searchCache,
                order: &searchCacheOrder,
                limit: CacheLimits.search
            )
        }
        latestSearchProfile = SearchProfile(
            term: normalizedQuery,
            intent: intent,
            cacheHit: false,
            totalElapsedMS: elapsedMS(since: searchStartNS),
            sourceTimings: sourceResults.map {
                SearchProfile.SourceTiming(
                    name: $0.name,
                    elapsedMS: $0.elapsedMS,
                    resultCount: $0.cards.count
                )
            }
        )
        return cards
    }

    private func isStaleSearch(_ generation: UInt) -> Bool {
        Task.isCancelled || generation != activeSearchGeneration
    }

    private func searchFastDefineSources(term: String, normalizedQuery: String) async -> [TimedSourceResult]? {
        guard let fastCards = fastDefineCards(term: term, normalizedQuery: normalizedQuery) else {
            return nil
        }
        let shouldSearchReferenceNotes = shouldSearchReferenceNotesOnFastDefine(term: term, loadIfNeeded: false)
        let shouldSearchRegionalNote = shouldSearchRegionalSpellingNoteOnFastDefine(normalizedQuery: normalizedQuery)

        return await withTaskGroup(of: TimedSourceResult.self) { group in
            group.addTask {
                TimedSourceResult(name: "Fast lookup", cards: fastCards, elapsedMS: 0)
            }
            if shouldSearchReferenceNotes {
                group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
            }
            if shouldSearchRegionalNote {
                group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
            }

            var results: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                results.append(result)
            }
            return results
        }
    }

    private func shouldSearchRegionalSpellingNoteOnFastDefine(normalizedQuery: String) -> Bool {
        if regionalEnglishIndex != nil {
            return true
        }
        return !regionalSpellingBaseCandidates(for: normalizedQuery).isEmpty
    }

    private func searchFastSynonymSources(term: String, normalizedQuery: String) async -> [TimedSourceResult]? {
        guard let synonymCards = fastSynonymCards(term: term, normalizedQuery: normalizedQuery) else {
            return nil
        }
        return [TimedSourceResult(name: "Synonym lookup", cards: synonymCards, elapsedMS: 0)]
    }

    private func searchFastTranslationSources(term: String, normalizedQuery: String) async -> [TimedSourceResult]? {
        guard let translationCards = fastTranslationCards(term: term, normalizedQuery: normalizedQuery) else {
            return nil
        }
        return [TimedSourceResult(name: "Translation lookup", cards: translationCards, elapsedMS: 0)]
    }

    private func searchFastSlangSources(term: String, normalizedQuery: String) async -> [TimedSourceResult]? {
        guard let slangCards = fastSlangCards(term: term, normalizedQuery: normalizedQuery) else {
            return nil
        }
        return [TimedSourceResult(name: "Australian slang", cards: slangCards, elapsedMS: 0)]
    }

    private struct ThesaurusCandidateMatches {
        let openOffice: [String]
        let moby: [String]

        var hasMatches: Bool {
            !openOffice.isEmpty || !moby.isEmpty
        }
    }

    private enum ThesaurusFallbackPlan {
        case none
        case openOffice
        case moby
        case fusion
    }

    private func thesaurusCandidateMatches(for normalizedTerm: String) -> ThesaurusCandidateMatches {
        guard !normalizedTerm.isEmpty else {
            return ThesaurusCandidateMatches(openOffice: [], moby: [])
        }

        let candidates = thesaurusLookupCandidates(for: normalizedTerm)
        let openOfficeHeadwords = loadOpenOfficeThesaurusHeadwordSet()
        let mobyHeadwords = loadMobyThesaurusHeadwordSet()

        return ThesaurusCandidateMatches(
            openOffice: candidates.filter { openOfficeHeadwords.contains($0) },
            moby: candidates.filter { mobyHeadwords.contains($0) }
        )
    }

    private func thesaurusFallbackPlan(for term: String) -> ThesaurusFallbackPlan {
        let matches = thesaurusCandidateMatches(for: normalizedLookupKey(term))
        switch (!matches.openOffice.isEmpty, !matches.moby.isEmpty) {
        case (true, true):
            return .fusion
        case (true, false):
            return .openOffice
        case (false, true):
            return .moby
        case (false, false):
            return .none
        }
    }

    private enum TranslationFallbackPlan {
        case lightweightOnly
        case bilingualSources
    }

    private func translationFallbackPlan() -> TranslationFallbackPlan {
        translationLookupStore == nil ? .bilingualSources : .lightweightOnly
    }

    private func searchPreviewDefineSources(term: String) async -> [TimedSourceResult] {
        if Task.isCancelled { return [] }
        return await withTaskGroup(of: TimedSourceResult.self) { group in
            group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
            group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
            group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }

            var collected: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                collected.append(result)
            }
            return collected
        }
    }

    private func searchPreviewTranslationSources(term: String) async -> [TimedSourceResult] {
        if Task.isCancelled { return [] }
        return await withTaskGroup(of: TimedSourceResult.self) { group in
            group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
            group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }

            var collected: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                collected.append(result)
            }
            return collected
        }
    }

    private func searchLightweightDefineSources(term: String) async -> [TimedSourceResult] {
        if Task.isCancelled { return [] }
        return await withTaskGroup(of: TimedSourceResult.self) { group in
            group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
            group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
            group.addTask { await self.profiledSource("English word-family inference") { await $0.searchDerivedEnglishForm(term: term) } }
            group.addTask { await self.profiledSource("Regional English wordlists") { await $0.searchRegionalEnglish(term: term) } }
            group.addTask { await self.profiledSource("Australian English") { await $0.searchAustralianEnglish(term: term) } }
            group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }
            group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }

            var collected: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                collected.append(result)
            }
            return collected
        }
    }

    private func searchLightweightTranslationContextSources(term: String) async -> [TimedSourceResult] {
        if Task.isCancelled { return [] }
        return await withTaskGroup(of: TimedSourceResult.self) { group in
            group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
            group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
            group.addTask { await self.profiledSource("English word-family inference") { await $0.searchDerivedEnglishForm(term: term) } }
            group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }
            group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }

            var collected: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                collected.append(result)
            }
            return collected
        }
    }

    private func scheduleDefineEnrichmentIfNeeded(
        cacheKey: SearchCacheKey,
        term: String,
        normalizedQuery: String
    ) {
        defineEnrichmentTask?.cancel()
        defineEnrichmentGeneration &+= 1
        let generation = defineEnrichmentGeneration
        defineEnrichmentInFlight = [cacheKey]
        defineEnrichmentTask = Task.detached(priority: .utility) {
            defer {
                Task {
                    await self.finishDefineEnrichment(cacheKey: cacheKey, generation: generation)
                }
            }
            guard !Task.isCancelled, normalizedQuery.count >= 3 else { return }
            let worker = DictionaryRepository()
            guard !Task.isCancelled else { return }
            await worker.prewarm(profile: .defineSearch)
            guard !Task.isCancelled else { return }
            let enrichedSourceResults = await worker.searchSources(term: term, intent: .define)
            guard !Task.isCancelled else { return }
            await self.applyDefineEnrichment(
                cacheKey: cacheKey,
                term: term,
                normalizedQuery: normalizedQuery,
                enrichedSourceResults: enrichedSourceResults,
                generation: generation
            )
        }
    }

    private func shouldEnrichLightweightDefineResults(_ sourceResults: [TimedSourceResult]) -> Bool {
        let cards = sourceResults.flatMap(\.cards)
        guard !cards.isEmpty else {
            return true
        }

        let fullyResolvedSources: Set<String> = [
            "Mongrel reference notes",
            "Regional spelling note",
            "English word-family inference",
            "Australian usage notes"
        ]
        if cards.contains(where: { fullyResolvedSources.contains($0.source) }) {
            return false
        }

        let coverageOnlySources: Set<String> = [
            "Regional English wordlists",
            "Australian English Dictionary",
            "Reference pivots"
        ]
        return cards.allSatisfy { coverageOnlySources.contains($0.source) }
    }

    private func finishDefineEnrichment(cacheKey: SearchCacheKey, generation: UInt) {
        guard generation == defineEnrichmentGeneration else { return }
        defineEnrichmentInFlight.remove(cacheKey)
        if defineEnrichmentInFlight.isEmpty {
            defineEnrichmentTask = nil
        }
    }

    private func applyDefineEnrichment(
        cacheKey: SearchCacheKey,
        term: String,
        normalizedQuery: String,
        enrichedSourceResults: [TimedSourceResult],
        generation: UInt
    ) {
        guard generation == defineEnrichmentGeneration else { return }
        let enrichedCards = finalizedSearchCards(
            term: term,
            intent: .define,
            normalizedQuery: normalizedQuery,
            sourceResults: enrichedSourceResults
        )
        storeCache(
            cacheKey: cacheKey,
            value: enrichedCards,
            in: &searchCache,
            order: &searchCacheOrder,
            limit: CacheLimits.search
        )
    }

    private func finalizedSearchCards(
        term: String,
        intent: QueryIntent,
        normalizedQuery: String,
        sourceResults: [TimedSourceResult]
    ) -> [SearchCard] {
        let all = sourceResults.flatMap(\.cards)

        let filtered: [SearchCard]
        switch intent {
        case .define:
            let primary = rankSearchCards(all.filter { intentSourceGroup($0.source) == .definition }, query: normalizedQuery)
            let secondary = rankSearchCards(all.filter { intentSourceGroup($0.source) == .thesaurus }, query: normalizedQuery)
            let tertiary = rankSearchCards(all.filter { intentSourceGroup($0.source) == .other }, query: normalizedQuery)
            filtered = primary + secondary + tertiary
        case .synonyms:
            let syn = rankSearchCards(all.filter { intentSourceGroup($0.source) == .thesaurus || $0.source == "Reference pivots" }, query: normalizedQuery)
            filtered = syn.isEmpty ? all : syn
        case .translation:
            let trans = rankSearchCards(all.filter { intentSourceGroup($0.source) == .bilingual }, query: normalizedQuery)
            let context = rankSearchCards(all.filter { intentSourceGroup($0.source) == .definition }, query: normalizedQuery)
            filtered = (trans + context).isEmpty ? all : (trans + context)
        case .slang:
            let slang = rankSearchCards(all.filter { intentSourceGroup($0.source) == .slang }, query: normalizedQuery)
            let context = rankSearchCards(all.filter { intentSourceGroup($0.source) == .definition || intentSourceGroup($0.source) == .thesaurus }, query: normalizedQuery)
            filtered = (slang + context).isEmpty ? all : (slang + context)
        }

        var cards = filtered
        if cards.isEmpty {
            cards.append(
                SearchCard(
                    title: term.capitalized,
                    source: "No match — \(intent.rawValue) mode",
                    summary: intentEmptyMessage(term: term, intent: intent),
                    chips: ["no exact hit", intent.rawValue.lowercased(), "local only"]
                )
            )
        }
        return cards
    }

    private func searchSources(term: String, intent: QueryIntent) async -> [TimedSourceResult] {
        if Task.isCancelled { return [] }
        let thesaurusPlan = thesaurusFallbackPlan(for: term)
        let translationPlan = translationFallbackPlan()

        return await withTaskGroup(of: TimedSourceResult.self) { group in
            switch intent {
            case .define:
                group.addTask { await self.profiledSource("WordNet 2025") { await $0.searchWordNet(term: term) } }
                group.addTask { await self.profiledSource("WordNet classic") { await $0.searchWordNetClassic(term: term) } }
                group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
                group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
                group.addTask { await self.profiledSource("English word-family inference") { await $0.searchDerivedEnglishForm(term: term) } }
                group.addTask { await self.profiledSource("Regional English wordlists") { await $0.searchRegionalEnglish(term: term) } }
                group.addTask { await self.profiledSource("Australian English") { await $0.searchAustralianEnglish(term: term) } }
                group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }
                switch thesaurusPlan {
                case .fusion:
                    group.addTask { await self.profiledSource("Thesaurus fusion") { await $0.searchThesaurusFusion(term: term) } }
                case .openOffice:
                    group.addTask { await self.profiledSource("OpenOffice thesaurus") { await $0.searchOpenOfficeThesaurus(term: term) } }
                case .moby:
                    group.addTask { await self.profiledSource("Moby thesaurus") { await $0.searchMobyThesaurus(term: term) } }
                case .none:
                    break
                }
                group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }

            case .synonyms:
                switch thesaurusPlan {
                case .fusion:
                    group.addTask { await self.profiledSource("Thesaurus fusion") { await $0.searchThesaurusFusion(term: term) } }
                case .openOffice:
                    group.addTask { await self.profiledSource("OpenOffice thesaurus") { await $0.searchOpenOfficeThesaurus(term: term) } }
                case .moby:
                    group.addTask { await self.profiledSource("Moby thesaurus") { await $0.searchMobyThesaurus(term: term) } }
                case .none:
                    break
                }
                group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }
                group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }

            case .translation:
                switch translationPlan {
                case .bilingualSources:
                    group.addTask { await self.profiledSource("FreeDict") { await $0.searchFreeDict(term: term) } }
                    group.addTask { await self.profiledSource("ZA Mafoko") { await $0.searchZAMafoko(term: term) } }
                case .lightweightOnly:
                    break
                }
                group.addTask { await self.profiledSource("WordNet 2025") { await $0.searchWordNet(term: term) } }
                group.addTask { await self.profiledSource("WordNet classic") { await $0.searchWordNetClassic(term: term) } }
                group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
                group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }

            case .slang:
                group.addTask { await self.profiledSource("Australian glossary") { await $0.searchAustralianGlossary(term: term) } }
                group.addTask { await self.profiledSource("Australian English") { await $0.searchAustralianEnglish(term: term) } }
                group.addTask { await self.profiledSource("Reference notes") { await $0.searchReferenceNotes(term: term) } }
                group.addTask { await self.profiledSource("Regional English wordlists") { await $0.searchRegionalEnglish(term: term) } }
                group.addTask { await self.profiledSource("Regional spelling note") { await $0.searchRegionalSpellingNote(term: term) } }
                group.addTask { await self.profiledSource("WordNet 2025") { await $0.searchWordNet(term: term) } }
                group.addTask { await self.profiledSource("WordNet classic") { await $0.searchWordNetClassic(term: term) } }
                switch thesaurusPlan {
                case .fusion:
                    group.addTask { await self.profiledSource("Thesaurus fusion") { await $0.searchThesaurusFusion(term: term) } }
                case .openOffice:
                    group.addTask { await self.profiledSource("OpenOffice thesaurus") { await $0.searchOpenOfficeThesaurus(term: term) } }
                case .moby:
                    group.addTask { await self.profiledSource("Moby thesaurus") { await $0.searchMobyThesaurus(term: term) } }
                case .none:
                    break
                }
                group.addTask { await self.profiledSource("Reference pivots") { await $0.searchReferencePivots(term: term) } }
            }

            var results: [TimedSourceResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
                results.append(result)
            }
            return results
        }
    }

    private struct TimedSourceResult: Sendable {
        let name: String
        let cards: [SearchCard]
        let elapsedMS: Int
    }

    private func profiledSource(
        _ name: String,
        operation: @Sendable (isolated DictionaryRepository) async -> [SearchCard]
    ) async -> TimedSourceResult {
        if Task.isCancelled {
            return TimedSourceResult(name: name, cards: [], elapsedMS: 0)
        }
        let startNS = DispatchTime.now().uptimeNanoseconds
        let cards = await operation(self)
        return TimedSourceResult(name: name, cards: cards, elapsedMS: elapsedMS(since: startNS))
    }

    private func elapsedMS(since startNS: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startNS) / 1_000_000)
    }

    // Maps a card's source label to a semantic group for intent-based filtering.
    private enum SourceGroup { case definition, thesaurus, bilingual, slang, other }
    private func intentSourceGroup(_ source: String) -> SourceGroup {
        let s = source.lowercased()
        if s.contains("wordnet") || s.contains("gcide") { return .definition }
        if s.contains("australian english dictionary") { return .definition }
        if s.contains("mongrel reference notes") { return .definition }
        if s.contains("regional english wordlists") || s.contains("regional spelling note") || s.contains("english word-family inference") { return .definition }
        if s.contains("synonym digest") { return .thesaurus }
        if s.contains("openoffice") || s.contains("moby") || s.contains("thesaurus fusion") || s.contains("thesaurus") { return .thesaurus }
        if s.contains("translation digest") { return .bilingual }
        if s.contains("freedict") || s.contains("za mafoko") || s.contains("bilingual") { return .bilingual }
        if s.contains("australian glossary") || s.contains("australian usage notes") || s.contains("aussie") { return .slang }
        return .other
    }

    private func intentEmptyMessage(term: String, intent: QueryIntent) -> String {
        switch intent {
        case .define:      return "No exact definition found for '\(term)' in the bundled definition sources. Check the spelling or try a nearby headword."
        case .synonyms:    return "No synonym entries found for '\(term)' in OpenOffice or Moby Thesaurus. Try the Define mode for a broader search."
        case .translation: return "No bilingual entries found for '\(term)' in FreeDict or ZA Mafoko. Coverage depends on which language pairs were bundled."
        case .slang:       return "No Australian slang or colloquial entries found for '\(term)'. The Australian glossary covers ~80 common terms."
        }
    }

    private func rankSearchCards(_ cards: [SearchCard], query: String) -> [SearchCard] {
        cards.sorted { lhs, rhs in
            let leftScore = searchCardScore(lhs, query: query)
            let rightScore = searchCardScore(rhs, query: query)
            if leftScore == rightScore {
                return lhs.title < rhs.title
            }
            return leftScore > rightScore
        }
    }

    private func searchCardScore(_ card: SearchCard, query: String) -> Int {
        var score = sourcePriority(for: card.source) * 100
        let titleKey = normalizedLookupKey(card.title)
        let compactQuery = compactLookupKey(query)
        let compactTitle = compactLookupKey(titleKey)

        if titleKey == query || compactTitle == compactQuery {
            score += 500
        }

        if card.chips.contains("exact hit") || card.chips.contains("exact") {
            score += 420
        } else if card.chips.contains("variant hit") || card.chips.contains("variant") {
            score += 260
        } else if card.chips.contains("typo-tolerant hit") {
            score += 140
        }

        if card.chips.contains("direct note hit") {
            score += 40
        }
        if card.chips.contains("phrase-core hit") {
            score += 180
        }
        if card.chips.contains("synonym-led hit") {
            score += 25
        }
        if card.chips.contains("companion result") {
            score -= 220
        }
        if card.chips.contains("dialect companion") {
            score -= 20
        }

        if card.source == "Reference pivots" { score -= 600 }
        if card.source.hasPrefix("No match") { score -= 1000 }
        return score
    }

    private func sourcePriority(for source: String) -> Int {
        switch source {
        case "Mongrel reference notes": return 16
        case "WordNet 2025 (Open English WordNet)": return 15
        case "WordNet 3.x (Princeton dict)": return 14
        case "Regional spelling note": return 13
        case "English word-family inference": return 12
        case "Regional English wordlists": return 11
        case "Australian usage notes": return 10
        case "Australian English Dictionary": return 9
        case "Synonym digest": return 8
        case let source where source.hasPrefix("Thesaurus fusion"): return 8
        case "OpenOffice British thesaurus": return 7
        case "Moby Thesaurus II": return 6
        case "Translation digest": return 5
        case let source where source.hasPrefix("FreeDict"): return 5
        case "ZA Mafoko multilingual termbank": return 4
        case "Reference pivots": return 1
        default: return 2
        }
    }

    private func searchReferencePivots(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard normalized.count >= 2 else { return [] }
        if searchLexicon == nil { searchLexicon = loadSearchLexicon() }
        guard let searchLexicon else { return [] }

        let prefix = String(normalized.prefix(max(2, min(4, normalized.count))))
        let australianVariantSet = Set(australianVariants(for: normalized).map(normalizedLookupKey))
        let inflectionVariantSet = Set(inflectionVariants(for: normalized).map(normalizedLookupKey))
        let derivationalVariants = derivationalBaseCandidates(for: normalized).map(\.base)
        var candidates: [String] = []
        candidates.append(contentsOf: prefixMatches(in: searchLexicon.sortedHeadwords, prefix: prefix, limit: 36))
        let compact = compactLookupKey(normalized)
        if compact != normalized, compact.count >= 2 {
            candidates.append(contentsOf: prefixMatches(in: searchLexicon.sortedHeadwords, prefix: String(compact.prefix(3)), limit: 20))
        }

        candidates.append(contentsOf: Array(australianVariantSet))
        candidates.append(contentsOf: Array(inflectionVariantSet))
        candidates.append(contentsOf: derivationalVariants)

        let deduped = dedupePreservingOrder(candidates)
            .filter { $0 != normalized && searchLexicon.headwords.contains($0) }

        let ranked = deduped
            .map { candidate in
                let normalizedCandidate = normalizedLookupKey(candidate)
                let edit = boundedLevenshtein(normalized, normalizedCandidate, limit: 3)
                let prefixBoost = normalizedCandidate.hasPrefix(prefix) ? 3 : 0
                let variantBoost = australianVariantSet.contains(normalizedCandidate) ? 2 : 0
                let inflectionBoost = inflectionVariantSet.contains(normalizedCandidate) ? 1 : 0
                let editBoost = max(0, 3 - (edit ?? 4))
                return (candidate, prefixBoost + variantBoost + inflectionBoost + editBoost)
            }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0 < $1.0
                }
                return $0.1 > $1.1
            }
            .map { $0.0 }
            .prefix(12)

        let pivotTerms = Array(ranked)
        guard !pivotTerms.isEmpty else { return [] }

        return [
            SearchCard(
                title: term.capitalized,
                source: "Reference pivots",
                summary: "Closest local headwords: \(pivotTerms.joined(separator: ", ")).",
                chips: ["fallback", "pivot search", "headword proximity"]
            )
        ]
    }

    // MARK: - WordNet 2025 (LMF/XML)

    private func searchWordNet(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if wordNetIndex == nil {
            wordNetIndex = loadWordNetIndex()
        }
        guard let index = wordNetIndex else { return [] }

        let standardCandidates = standardLookupCandidates(for: normalized)
        let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
            index.synsetsByHeadword[$0] != nil
        }
        guard let matched = candidates.first,
              let synsets = index.synsetsByHeadword[matched],
              !synsets.isEmpty else { return [] }

        let pos = index.posByHeadword[matched] ?? "?"
        let posLabel = wordNetPOSName(pos)

        // Build per-POS sense count breakdown across all LexicalEntries for this headword.
        let posBreakdownLabel: String
        if let posMap = index.synsetCountByPOSByHeadword[matched], !posMap.isEmpty {
            posBreakdownLabel = posMap
                .sorted { wordNetPOSName($0.key) < wordNetPOSName($1.key) }
                .map { "\(wordNetPOSName($0.key)): \($0.value)" }
                .joined(separator: " · ")
        } else {
            posBreakdownLabel = "\(posLabel): \(synsets.count)"
        }

        let definitions = synsets.prefix(6).compactMap { index.definitionBySynset[$0] }
        guard !definitions.isEmpty else { return [] }

        let relatedLemmas = dedupePreservingOrder(
            synsets
                .flatMap { index.headwordsBySynset[$0] ?? [] }
                .filter { normalizedLookupKey($0) != matched }
        )

        var summary = definitions.enumerated()
            .map { i, def in "\(i + 1). \(def)" }
            .joined(separator: "  ·  ")

        if !relatedLemmas.isEmpty {
            summary += "  ·  Related lemmas: \(relatedLemmas.prefix(8).joined(separator: ", "))."
        }
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "WordNet 2025 (Open English WordNet)",
                summary: summary,
                chips: [posBreakdownLabel, "synsets: \(synsets.count)", "lemmas: \(relatedLemmas.count + 1)", "wordnet", "oewn", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)]
            )
        ]
    }

    private func loadWordNetIndex() -> WordNetIndex? {
        if let archive: WordNet2025Archive = loadBundledArchive(fileName: "WordNet2025.mgrt") {
            return WordNetIndex(
                synsetsByHeadword: archive.synsetsByHeadword,
                posByHeadword: archive.posByHeadword,
                definitionBySynset: archive.definitionBySynset,
                headwordsBySynset: archive.headwordsBySynset,
                sortedHeadwords: archive.sortedHeadwords,
                synsetCountByPOSByHeadword: archive.synsetCountByPOSByHeadword
            )
        }

        let url = resourceURL(fileName: "english-wordnet-2025.xml", fallbackRelativePath: "english-wordnet-2025.xml")
        guard fileManager.fileExists(atPath: url.path),
              let parser = XMLParser(contentsOf: url) else { return nil }

        let delegate = WordNetXMLDelegate()
        parser.delegate = delegate
        parser.parse()

        let sorted = delegate.synsetsByHeadword.keys.sorted()
        return WordNetIndex(
            synsetsByHeadword: delegate.synsetsByHeadword,
            posByHeadword: delegate.posByHeadword,
            definitionBySynset: delegate.definitionBySynset,
            headwordsBySynset: delegate.headwordsBySynset,
            sortedHeadwords: sorted,
            synsetCountByPOSByHeadword: delegate.synsetCountByPOSByHeadword
        )
    }

    private func wordNetPOSName(_ pos: String) -> String {
        switch pos {
        case "n": return "noun"
        case "v": return "verb"
        case "a", "s": return "adjective"
        case "r": return "adverb"
        default: return pos
        }
    }

    private func sourceInventory(name: String, detail: String, relativePath: String) -> SourceInventory {
        let url = resourceURL(fileName: URL(fileURLWithPath: relativePath).lastPathComponent, fallbackRelativePath: relativePath)
        let exists = fileManager.fileExists(atPath: url.path)

        let runtimeArchive: String?
        switch name {
        case "WordNet 2025 (OEWN XML)": runtimeArchive = "WordNet2025.mgrt"
        case "FreeDict": runtimeArchive = "TranslationLookup.sqlite3"
        default: runtimeArchive = nil
        }
        if let runtimeArchive, packagedArchiveExists(fileName: runtimeArchive) {
            return SourceInventory(name: name, detail: "Bundled offline lexical data", status: "Packaged archive present")
        }

        if name == "GCIDE", !exists {
            let sigExists = fileManager.fileExists(atPath: dictionaryRootURL.appendingPathComponent("gcide-0.54.tar.gz.sig").path)
            return SourceInventory(name: name, detail: detail, status: sigExists ? "Signature present, archive missing" : "Missing")
        }

        if name == "Australian English Dictionary", exists {
            return SourceInventory(name: name, detail: detail, status: "Present")
        }

        if name == "FreeDict", exists {
            return SourceInventory(name: name, detail: detail, status: "Present")
        }

        if name == "Etymology DB", exists {
            let hasCSV = fileManager.fileExists(atPath: url.appendingPathComponent("etymology.csv").path)
            return SourceInventory(name: name, detail: detail, status: hasCSV ? "Relation data present" : "Schema present, data export missing")
        }

        return SourceInventory(name: name, detail: detail, status: exists ? "Present" : "Missing")
    }

    private func sourceInventoryWordNetClassic() -> SourceInventory {
        if packagedArchiveExists(fileName: "WordNetClassic.mgrt") {
            return SourceInventory(
                name: "WordNet 3.x (classic dict)",
                detail: "Bundled Princeton WordNet archive · WordNet® attribution required (Princeton)",
                status: "Packaged archive present"
            )
        }
        let present = availableClassicWordNetDataFiles()
        let requiredFiles = Self.classicWordNetDataFiles

        let status: String
        if present.isEmpty {
            status = "Missing"
        } else if present.count == requiredFiles.count {
            status = "Present (\(present.count) data files)"
        } else {
            let missing = requiredFiles.filter { !present.contains($0) }
            status = "Partial (\(present.count)/\(requiredFiles.count) data files; missing: \(missing.joined(separator: ", ")))"
        }

        return SourceInventory(
            name: "WordNet 3.x (classic dict)",
            detail: "Legacy Princeton dict format · WordNet® attribution required (Princeton)",
            status: status
        )
    }

    private func hasCompleteClassicWordNetData() -> Bool {
        Self.classicWordNetDataFiles.allSatisfy { classicWordNetFileURL(named: $0) != nil }
    }

    private func availableClassicWordNetDataFiles() -> [String] {
        Self.classicWordNetDataFiles.filter { classicWordNetFileURL(named: $0) != nil }
    }

    private func loadRegionalEnglishRegionCounts() -> [String: Int]? {
        if let regionalEnglishRegionCounts {
            return regionalEnglishRegionCounts
        }

        if let regionalEnglishIndex {
            let counts = Dictionary(
                grouping: regionalEnglishIndex.regionsByHeadword.flatMap { headword, regions in
                    regions.map { ($0, headword) }
                },
                by: \.0
            ).mapValues { Set($0.map(\.1)).count }
            regionalEnglishRegionCounts = counts
            return counts
        }

        if let archive: RegionalEnglishArchive = loadBundledArchive(fileName: "RegionalEnglish.mgrt") {
            regionalEnglishRegionCounts = archive.regionCounts
            return archive.regionCounts
        }

        return nil
    }

    private func loadReferenceNotesInventorySnapshot() -> ReferenceNotesInventorySnapshot? {
        if let referenceNotesInventorySnapshot {
            return referenceNotesInventorySnapshot
        }

        if let referenceNotesIndex {
            let snapshot = ReferenceNotesInventorySnapshot(
                notesCount: referenceNotesIndex.notes.count,
                entriesCount: referenceNotesIndex.entries.count
            )
            referenceNotesInventorySnapshot = snapshot
            return snapshot
        }

        if referenceNotesStore == nil {
            referenceNotesStore = openReferenceNotesStore()
        }
        if let referenceNotesStore {
            let snapshot = ReferenceNotesInventorySnapshot(
                notesCount: nil,
                entriesCount: referenceNotesStore.entryCount
            )
            referenceNotesInventorySnapshot = snapshot
            return snapshot
        }

        if let archive: ReferenceNotesArchive = loadBundledArchive(fileName: "ReferenceNotes.mgrt") {
            let snapshot = ReferenceNotesInventorySnapshot(
                notesCount: archive.notes.count,
                entriesCount: archive.entries.count
            )
            referenceNotesInventorySnapshot = snapshot
            return snapshot
        }

        return nil
    }

    private func sourceInventoryEnglishRegional(
        name: String,
        relativePath: String,
        detailLevel: InventoryDetailLevel
    ) -> SourceInventory {
        let rawDetail = "Hunspell/SCOWL-style regional English word list for orthography and headword coverage"
        let archiveDetail = "Packaged regional-English headword archive for orthography and dialect coverage"
        let url = inventoryRawResourceURL(
            fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
            fallbackRelativePath: relativePath
        )
        if fileManager.fileExists(atPath: url.path) {
            return SourceInventory(name: name, detail: rawDetail, status: "Present")
        }

        let label = name
            .replacingOccurrences(of: "English (", with: "")
            .replacingOccurrences(of: ") word list", with: "")
        if detailLevel == .detailed, let count = loadRegionalEnglishRegionCounts()?[label] {
            return SourceInventory(name: name, detail: archiveDetail, status: "\(count) headwords present")
        }

        if packagedArchiveExists(fileName: "RegionalEnglish.mgrt") {
            return SourceInventory(name: name, detail: archiveDetail, status: "Packaged archive present")
        }

        return SourceInventory(name: name, detail: rawDetail, status: "Missing")
    }

    private func sourceInventoryReferenceNotes(detailLevel: InventoryDetailLevel) -> SourceInventory {
        let detail = "Hand-authored dictionary notes adapted from the English-language reference archive in this workspace"
        if detailLevel == .detailed, let snapshot = loadReferenceNotesInventorySnapshot() {
            let status: String
            if let notesCount = snapshot.notesCount {
                status = "\(notesCount) notes / \(snapshot.entriesCount) searchable entries present"
            } else {
                status = "\(snapshot.entriesCount) searchable entries present"
            }
            return SourceInventory(name: "Mongrel reference notes", detail: detail, status: status)
        }

        if packagedArchiveExists(fileName: "ReferenceNotes.sqlite3") {
            return SourceInventory(
                name: "Mongrel reference notes",
                detail: detail,
                status: "Searchable note store present"
            )
        }
        if packagedArchiveExists(fileName: "ReferenceNotes.mgrt") {
            return SourceInventory(
                name: "Mongrel reference notes",
                detail: detail,
                status: "Packaged archive present"
            )
        }
        if fileManager.fileExists(atPath: authoringNotesURL.path) {
            return SourceInventory(
                name: "Mongrel reference notes",
                detail: detail,
                status: "Authoring notes present"
            )
        }

        return SourceInventory(name: "Mongrel reference notes", detail: detail, status: "Missing")
    }

    private func sourceInventoryAustralianEnglish(detailLevel: InventoryDetailLevel) -> SourceInventory {
        let rawDetail = "Hunspell AussieDic word list for Australian spellings and local headwords"
        let archiveDetail = "Packaged Australian English headword archive for local spellings and regional vocabulary"
        let rawURL = inventoryRawResourceURL(
            fileName: "AussieDic.dic",
            fallbackRelativePath: "Australian-English-Dictionary-main/Source/2.5/Source/dictionaries/AussieDic.dic"
        )
        if fileManager.fileExists(atPath: rawURL.path) {
            return SourceInventory(name: "Australian English Dictionary", detail: rawDetail, status: "Present")
        }

        if detailLevel == .detailed, let aussieDictionaryIndex {
            return SourceInventory(
                name: "Australian English Dictionary",
                detail: archiveDetail,
                status: "\(aussieDictionaryIndex.headwords.count) headwords present"
            )
        }
        if detailLevel == .detailed, let archive: WordListArchive = loadBundledArchive(fileName: "AussieDictionary.mgrt") {
            return SourceInventory(
                name: "Australian English Dictionary",
                detail: archiveDetail,
                status: "\(archive.headwords.count) headwords present"
            )
        }
        if packagedArchiveExists(fileName: "AussieDictionary.mgrt") {
            return SourceInventory(
                name: "Australian English Dictionary",
                detail: archiveDetail,
                status: "Packaged archive present"
            )
        }

        return SourceInventory(name: "Australian English Dictionary", detail: rawDetail, status: "Missing")
    }

    private func sourceInventoryOpenOfficeThesaurus(detailLevel: InventoryDetailLevel) -> SourceInventory {
        let rawDetail = "British English idx/dat thesaurus"
        let archiveDetail = "Packaged British-English synonym archive"
        let rawURL = inventoryRawResourceURL(
            fileName: "th_en_GB_final.dat",
            fallbackRelativePath: "oo2_th_en_GB/th_en_GB_final.dat"
        )
        if fileManager.fileExists(atPath: rawURL.path) {
            return SourceInventory(name: "OpenOffice thesaurus", detail: rawDetail, status: "Present")
        }

        if detailLevel == .detailed {
            let headwords = loadOpenOfficeThesaurusHeadwordSet()
            if !headwords.isEmpty {
                return SourceInventory(
                    name: "OpenOffice thesaurus",
                    detail: archiveDetail,
                    status: "\(headwords.count) headwords present"
                )
            }
        }

        let archivePresent = packagedArchiveExists(fileName: "OpenOfficeThesaurusHeadwords.mgrt")
            || packagedArchiveExists(fileName: "OpenOfficeThesaurus.mgrt")
        return SourceInventory(
            name: "OpenOffice thesaurus",
            detail: archivePresent ? archiveDetail : rawDetail,
            status: archivePresent ? "Packaged archive present" : "Missing"
        )
    }

    private func sourceInventoryMobyThesaurus(detailLevel: InventoryDetailLevel) -> SourceInventory {
        let rawDetail = "30k English root-word synonym graph"
        let archiveDetail = "Packaged synonym graph for English headwords"
        let rawURL = inventoryRawResourceURL(
            fileName: "mthesaur.txt",
            fallbackRelativePath: "Moby-Project-main/Moby Thesaurus II/mthesaur.txt"
        )
        if fileManager.fileExists(atPath: rawURL.path) {
            return SourceInventory(name: "Moby Thesaurus II", detail: rawDetail, status: "Present")
        }

        if detailLevel == .detailed {
            let headwords = loadMobyThesaurusHeadwordSet()
            if !headwords.isEmpty {
                return SourceInventory(
                    name: "Moby Thesaurus II",
                    detail: archiveDetail,
                    status: "\(headwords.count) headwords present"
                )
            }
        }

        let archivePresent = packagedArchiveExists(fileName: "MobyThesaurusHeadwords.mgrt")
            || packagedArchiveExists(fileName: "MobyThesaurus.mgrt")
        return SourceInventory(
            name: "Moby Thesaurus II",
            detail: archivePresent ? archiveDetail : rawDetail,
            status: archivePresent ? "Packaged archive present" : "Missing"
        )
    }

    private func sourceInventoryZAMafoko(detailLevel: InventoryDetailLevel) -> SourceInventory {
        let rawDetail = "Multilingual South African terminology"
        let archiveDetail = "Packaged multilingual South African terminology archive"
        let rawURL = inventoryRawResourceURL(
            fileName: "combined_all.jsonl",
            fallbackRelativePath: "za-mafoko-master/data/combined_all.jsonl"
        )
        if fileManager.fileExists(atPath: rawURL.path) {
            return SourceInventory(name: "ZA Mafoko", detail: rawDetail, status: "Present")
        }

        if detailLevel == .detailed, let zaMafokoEntries {
            return SourceInventory(name: "ZA Mafoko", detail: archiveDetail, status: "\(zaMafokoEntries.count) entries present")
        }
        if detailLevel == .detailed, let archive: ZAMafokoArchive = loadBundledArchive(fileName: "ZAMafoko.mgrt") {
            return SourceInventory(name: "ZA Mafoko", detail: archiveDetail, status: "\(archive.entries.count) entries present")
        }
        if packagedArchiveExists(fileName: "ZAMafoko.mgrt") {
            return SourceInventory(name: "ZA Mafoko", detail: archiveDetail, status: "Packaged archive present")
        }

        return SourceInventory(name: "ZA Mafoko", detail: rawDetail, status: "Missing")
    }

    private func searchAustralianEnglish(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if aussieDictionaryIndex == nil {
            aussieDictionaryIndex = loadAussieDictionaryIndex()
        }

        guard let aussieDictionaryIndex else { return [] }

        let standardCandidates = standardLookupCandidates(for: normalized)
        let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
            aussieDictionaryIndex.headwords.contains($0)
        }
        guard let matched = candidates.first else {
            return []
        }

        let neighboring = prefixMatches(in: aussieDictionaryIndex.sortedHeadwords, prefix: String(matched.prefix(4)), limit: 5)
            .filter { $0 != matched }

        var summary = "Confirmed in the AussieDic Australian English word list. This source is best for local spelling and headword coverage rather than full dictionary-style definitions."
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)
        if !neighboring.isEmpty {
            summary += " Nearby entries: \(neighboring.joined(separator: ", "))."
        }

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "Australian English Dictionary",
                summary: summary,
                chips: ["australian english", "hunspell", "headword", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)]
            )
        ]
    }

    private func searchRegionalEnglish(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        guard let regionalEnglishIndex else { return [] }

        let matched: String
        let standardCandidates: [String]
        if regionalEnglishIndex.regionsByHeadword[normalized] != nil {
            matched = normalized
            standardCandidates = [normalized]
        } else {
            standardCandidates = standardLookupCandidates(for: normalized)
            let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
                regionalEnglishIndex.regionsByHeadword[$0] != nil
            }
            guard let candidate = candidates.first else { return [] }
            matched = candidate
        }

        guard let regions = regionalEnglishIndex.regionsByHeadword[matched],
              !regions.isEmpty else {
            return []
        }

        var summary = "Recognized in the regional English wordlists for \(regions.joined(separator: ", ")). This source confirms headword and spelling coverage rather than supplying a full authored dictionary entry."
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)
        if let inferred = inferredDerivedMeaning(for: normalized) {
            summary += " In plain terms, '\(normalized)' means \(inferred.shortDefinition)."
        }

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "Regional English wordlists",
                summary: summary,
                chips: [
                    "regional english",
                    lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates),
                    "regions: \(regions.count)"
                ] + Array(regions.prefix(3))
            )
        ]
    }

    private func searchReferenceNotes(term: String, lexiconScope: LexiconScope = .global) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }
        loadReferenceNoteArtifacts()
        let phraseCoreKey = phraseCoreLookupKey(for: term)

        if let referenceNotesStore {
            let exactDirectRows = dedupeStoredReferenceRows(referenceNotesStore.lookupRows(for: normalized))
            let exactDirectKeys = Set(exactDirectRows.map { normalizedLookupKey($0.entry.title) })
            let exactPhraseCoreRows = phraseCoreKey.isEmpty
                ? []
                : dedupeStoredReferenceRows(referenceNotesStore.phraseCoreRows(for: phraseCoreKey))
                    .filter { !exactDirectKeys.contains(normalizedLookupKey($0.entry.title)) }

            if !exactDirectRows.isEmpty || !exactPhraseCoreRows.isEmpty {
                return buildReferenceNoteCards(
                    directEntries: exactDirectRows.map(\.entry),
                    phraseCoreEntries: exactPhraseCoreRows.map(\.entry),
                    query: normalized,
                    phraseCoreKey: phraseCoreKey,
                    candidateKeys: [normalized],
                    standardCandidates: [normalized],
                    sourceTitles: referenceNotesStore.sourceTitles,
                    topicTermsByEntryKey: Dictionary(
                        uniqueKeysWithValues: (exactDirectRows + exactPhraseCoreRows).map {
                            (referenceEntryCacheKey($0.entry), $0.topicTerms)
                        }
                    ),
                    companionEntriesProvider: { relatedTerm in
                        dedupeReferenceEntries(
                            dedupeStoredReferenceRows(
                                referenceNotesStore.lookupRows(for: normalizedLookupKey(relatedTerm))
                            ).map(\.entry)
                        )
                    },
                    relatedEntryExists: { relatedTerm in
                        referenceNotesStore.hasLookupKey(normalizedLookupKey(relatedTerm))
                    }
                )
            }

            let standardCandidates = standardLookupCandidates(for: normalized)
            var candidateKeys = standardCandidates
            var directRows = storedReferenceRows(for: candidateKeys, in: referenceNotesStore)
            if directRows.isEmpty {
                let fuzzyCandidates = fuzzyHeadwordCandidates(for: normalized, scope: lexiconScope)
                candidateKeys = dedupePreservingOrder(standardCandidates + fuzzyCandidates)
                directRows = storedReferenceRows(for: candidateKeys, in: referenceNotesStore)
            }
            let directKeys = Set(directRows.map { normalizedLookupKey($0.entry.title) })
            let phraseCoreRows = exactPhraseCoreRows.filter {
                !directKeys.contains(normalizedLookupKey($0.entry.title))
            }

            if !directRows.isEmpty || !phraseCoreRows.isEmpty {
                return buildReferenceNoteCards(
                    directEntries: directRows.map(\.entry),
                    phraseCoreEntries: phraseCoreRows.map(\.entry),
                    query: normalized,
                    phraseCoreKey: phraseCoreKey,
                    candidateKeys: candidateKeys,
                    standardCandidates: standardCandidates,
                    sourceTitles: referenceNotesStore.sourceTitles,
                    topicTermsByEntryKey: Dictionary(
                        uniqueKeysWithValues: (directRows + phraseCoreRows).map {
                            (referenceEntryCacheKey($0.entry), $0.topicTerms)
                        }
                    ),
                    companionEntriesProvider: { relatedTerm in
                        dedupeReferenceEntries(
                            dedupeStoredReferenceRows(
                                referenceNotesStore.lookupRows(for: normalizedLookupKey(relatedTerm))
                            ).map(\.entry)
                        )
                    },
                    relatedEntryExists: { relatedTerm in
                        referenceNotesStore.hasLookupKey(normalizedLookupKey(relatedTerm))
                    }
                )
            }
        }

        if referenceNotesIndex == nil {
            referenceNotesIndex = loadReferenceNotesIndex()
        }
        guard let referenceNotesIndex else { return [] }
        if self.referenceNotesIndex == nil {
            self.referenceNotesIndex = referenceNotesIndex
        }

        let exactDirectEntries = dedupeReferenceEntries(referenceNotesIndex.entriesByLookupKey[normalized] ?? [])
        let exactDirectKeys = Set(exactDirectEntries.map { normalizedLookupKey($0.title) })
        let exactPhraseCoreEntries = phraseCoreKey.isEmpty
            ? []
            : dedupeReferenceEntries(referenceNotesIndex.entriesByPhraseCoreKey[phraseCoreKey] ?? [])
                .filter { !exactDirectKeys.contains(normalizedLookupKey($0.title)) }

        let standardCandidates: [String]
        var directEntries: [ReferenceEntry]
        let candidateKeys: [String]
        if !exactDirectEntries.isEmpty || !exactPhraseCoreEntries.isEmpty {
            standardCandidates = [normalized]
            directEntries = exactDirectEntries
            candidateKeys = [normalized]
        } else {
            standardCandidates = standardLookupCandidates(for: normalized)
            directEntries = dedupeReferenceEntries(
                standardCandidates.flatMap { referenceNotesIndex.entriesByLookupKey[$0] ?? [] }
            )
            let fuzzyCandidates = fuzzyHeadwordCandidates(for: normalized, scope: lexiconScope)
            candidateKeys = dedupePreservingOrder(standardCandidates + fuzzyCandidates)
            directEntries = dedupeReferenceEntries(
                candidateKeys.flatMap { referenceNotesIndex.entriesByLookupKey[$0] ?? [] }
            )
        }
        let directKeys = Set(directEntries.map { normalizedLookupKey($0.title) })
        let phraseCoreEntries = exactPhraseCoreEntries.filter {
            !directKeys.contains(normalizedLookupKey($0.title))
        }

        guard !directEntries.isEmpty || !phraseCoreEntries.isEmpty else { return [] }

        return buildReferenceNoteCards(
            directEntries: directEntries,
            phraseCoreEntries: phraseCoreEntries,
            query: normalized,
            phraseCoreKey: phraseCoreKey,
            candidateKeys: candidateKeys,
            standardCandidates: standardCandidates,
            sourceTitles: referenceNotesIndex.sourceTitles,
            topicTermsByEntryKey: referenceNotesIndex.topicTermsByEntryKey,
            companionEntriesProvider: { relatedTerm in
                dedupeReferenceEntries(
                    (referenceNotesIndex.entriesByLookupKey[normalizedLookupKey(relatedTerm)] ?? [])
                )
            },
            relatedEntryExists: { relatedTerm in
                !((referenceNotesIndex.entriesByLookupKey[normalizedLookupKey(relatedTerm)]) ?? []).isEmpty
            }
        )
    }

    private func buildReferenceNoteCards(
        directEntries: [ReferenceEntry],
        phraseCoreEntries: [ReferenceEntry],
        query normalized: String,
        phraseCoreKey: String,
        candidateKeys: [String],
        standardCandidates: [String],
        sourceTitles: Set<String>,
        topicTermsByEntryKey: [String: [String]],
        companionEntriesProvider: (String) -> [ReferenceEntry],
        relatedEntryExists: (String) -> Bool
    ) -> [SearchCard] {
        let companionTerms = dedupePreservingOrder(
            (directEntries + phraseCoreEntries).flatMap { entry in
                entry.counterparts.map(\.term) + entry.seeAlso
            }
        )
        let phraseCoreKeys = Set(phraseCoreEntries.map { normalizedLookupKey($0.title) })
        let directKeys = Set(directEntries.map { normalizedLookupKey($0.title) })
        let companionEntries = dedupeReferenceEntries(companionTerms.flatMap(companionEntriesProvider))
        .filter {
            let key = normalizedLookupKey($0.title)
            return !directKeys.contains(key) && !phraseCoreKeys.contains(key)
        }

        let rankedDirectEntries = rankReferenceEntries(directEntries, query: normalized, candidates: candidateKeys)
        let rankedPhraseCoreEntries = rankReferenceEntries(phraseCoreEntries, query: normalized, candidates: [phraseCoreKey])
        let rankedCompanionEntries = rankReferenceEntries(companionEntries, query: normalized, candidates: companionTerms)
        let companionCounterpartTerms = Set(
            (directEntries + phraseCoreEntries).flatMap(\.counterparts).map { normalizedLookupKey($0.term) }
        )
        let rankedEntries = Array((rankedDirectEntries + rankedPhraseCoreEntries + rankedCompanionEntries).prefix(6))

        return rankedEntries.map { entry in
            var summary = sanitizedReferenceNoteSummary(
                entry.summary,
                sourceTitle: entry.sourceTitle,
                knownSourceTitles: sourceTitles
            )
            if !entry.synonyms.isEmpty {
                summary += " Near synonyms: \(entry.synonyms.prefix(6).joined(separator: ", "))."
            }
            let antonyms = dedupeReferenceStrings(entry.antonyms)
            let relatedTerms = dedupePreservingOrder(entry.seeAlso).filter { related in
                let key = normalizedLookupKey(related)
                guard key != normalizedLookupKey(entry.title) else { return false }
                return relatedEntryExists(related)
            }
            let topicTerms = topicTermsByEntryKey[referenceEntryCacheKey(entry)] ?? []
            let directMatchChips = referenceDirectMatchChips(
                for: entry,
                query: normalized,
                candidates: candidateKeys,
                standardCandidates: standardCandidates
            )
            let phraseCoreMatchChips = referencePhraseCoreMatchChips(
                for: entry,
                phraseCoreKey: phraseCoreKey
            )
            let companionMatchChips = referenceCompanionMatchChips(
                for: entry,
                counterpartTerms: companionCounterpartTerms
            )
            let entryKey = normalizedLookupKey(entry.title)
            let matchChips: [String]
            if directKeys.contains(entryKey) {
                matchChips = directMatchChips
            } else if phraseCoreKeys.contains(entryKey) {
                matchChips = phraseCoreMatchChips
            } else {
                matchChips = companionMatchChips
            }

            return SearchCard(
                title: entry.title,
                source: "Mongrel reference notes",
                summary: summary,
                chips: dedupeReferenceStrings(entry.chips + matchChips),
                counterparts: entry.counterparts.map { .init(label: $0.label, term: $0.term) },
                antonyms: antonyms,
                relatedTerms: relatedTerms,
                topicTerms: topicTerms
            )
        }
    }

    private func searchReferenceNotesRecovery(term: String, lexiconScope: LexiconScope = .deepLookup) async -> [SearchCard] {
        let recovery = buildReferenceNotesRecovery(term: term, lexiconScope: lexiconScope)
        guard !recovery.entries.isEmpty else { return [] }

        let rankedEntries = rankReferenceRecoveryEntries(recovery.entries, query: recovery.normalized, candidates: recovery.candidateKeys)
        return Array(rankedEntries.prefix(4)).map { entry in
            let entryKey = normalizedLookupKey(entry.title)
            let matchedCandidate = referenceRecoveryMatchedCandidate(
                for: entry,
                candidateKeys: recovery.candidateKeys,
                fallback: entryKey
            )
            return SearchCard(
                title: entry.title,
                source: "Mongrel reference notes",
                summary: "Recovered reference-note entry for '\(entry.title)'.",
                chips: ["recovery probe", lookupMatchChip(query: recovery.normalized, matched: matchedCandidate, standardCandidates: recovery.standardCandidates)]
            )
        }
    }

    private func referenceNotesRecoveryDiagnostics(term: String, lexiconScope: LexiconScope) async -> DeepRecoveryDiagnostics {
        let totalStart = DispatchTime.now().uptimeNanoseconds
        let recovery = buildReferenceNotesRecovery(term: term, lexiconScope: lexiconScope)
        let rankingStart = DispatchTime.now().uptimeNanoseconds
        let rankedEntries = rankReferenceRecoveryEntries(recovery.entries, query: recovery.normalized, candidates: recovery.candidateKeys)
        let rankingElapsed = elapsedMS(since: rankingStart)
        let totalElapsed = elapsedMS(since: totalStart)

        return DeepRecoveryDiagnostics(
            term: recovery.normalized,
            usedDirectEntries: recovery.usedDirectEntries,
            standardCandidateCount: recovery.standardCandidates.count,
            fuzzyCandidateCount: recovery.fuzzyCandidateCount,
            recoveredEntryCount: rankedEntries.count,
            totalElapsedMS: totalElapsed,
            phaseTimings: recovery.phaseTimings + [
                .init(name: "ranking", elapsedMS: rankingElapsed)
            ]
        )
    }

    private func buildReferenceNotesRecovery(term: String, lexiconScope: LexiconScope) -> ReferenceNotesRecoveryResult {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else {
            return ReferenceNotesRecoveryResult(
                normalized: normalized,
                standardCandidates: [],
                candidateKeys: [],
                entries: [],
                usedDirectEntries: false,
                fuzzyCandidateCount: 0,
                phaseTimings: []
            )
        }

        let standardStart = DispatchTime.now().uptimeNanoseconds
        let standardCandidates = standardLookupCandidates(for: normalized)
        let standardElapsed = elapsedMS(since: standardStart)

        loadReferenceNoteArtifacts()
        if let referenceNotesStore {
            let directStart = DispatchTime.now().uptimeNanoseconds
            let directEntries = storedReferenceRows(for: standardCandidates, in: referenceNotesStore).map(\.entry)
            let directElapsed = elapsedMS(since: directStart)
            let candidateKeys: [String]
            let entries: [ReferenceEntry]
            let fuzzyCandidateCount: Int
            let usedDirectEntries: Bool
            if directEntries.isEmpty {
                let fuzzyStart = DispatchTime.now().uptimeNanoseconds
                let fuzzyCandidates = fuzzyHeadwordCandidates(for: normalized, scope: lexiconScope)
                let fuzzyElapsed = elapsedMS(since: fuzzyStart)
                candidateKeys = dedupePreservingOrder(standardCandidates + fuzzyCandidates)
                let hydrateStart = DispatchTime.now().uptimeNanoseconds
                entries = storedReferenceRows(for: candidateKeys, in: referenceNotesStore).map(\.entry)
                let hydrateElapsed = elapsedMS(since: hydrateStart)
                return ReferenceNotesRecoveryResult(
                    normalized: normalized,
                    standardCandidates: standardCandidates,
                    candidateKeys: candidateKeys,
                    entries: entries,
                    usedDirectEntries: false,
                    fuzzyCandidateCount: fuzzyCandidates.count,
                    phaseTimings: [
                        .init(name: "standard_candidates", elapsedMS: standardElapsed),
                        .init(name: "direct_hydration", elapsedMS: directElapsed),
                        .init(name: "fuzzy_candidates", elapsedMS: fuzzyElapsed),
                        .init(name: "recovery_hydration", elapsedMS: hydrateElapsed),
                    ]
                )
            } else {
                candidateKeys = standardCandidates
                entries = directEntries
                fuzzyCandidateCount = 0
                usedDirectEntries = true
            }

            return ReferenceNotesRecoveryResult(
                normalized: normalized,
                standardCandidates: standardCandidates,
                candidateKeys: candidateKeys,
                entries: entries,
                usedDirectEntries: usedDirectEntries,
                fuzzyCandidateCount: fuzzyCandidateCount,
                phaseTimings: [
                    .init(name: "standard_candidates", elapsedMS: standardElapsed),
                    .init(name: "direct_hydration", elapsedMS: directElapsed),
                ]
            )
        }

        if referenceNotesIndex == nil {
            referenceNotesIndex = loadReferenceNotesIndex()
        }
        guard let referenceNotesIndex else {
            return ReferenceNotesRecoveryResult(
                normalized: normalized,
                standardCandidates: [],
                candidateKeys: [],
                entries: [],
                usedDirectEntries: false,
                fuzzyCandidateCount: 0,
                phaseTimings: []
            )
        }
        if self.referenceNotesIndex == nil {
            self.referenceNotesIndex = referenceNotesIndex
        }

        let directStart = DispatchTime.now().uptimeNanoseconds
        let directEntries = dedupeReferenceEntries(
            standardCandidates.flatMap { referenceNotesIndex.entriesByLookupKey[$0] ?? [] }
        )
        let directElapsed = elapsedMS(since: directStart)
        let candidateKeys: [String]
        let entries: [ReferenceEntry]
        let fuzzyCandidateCount: Int
        let usedDirectEntries: Bool
        if directEntries.isEmpty {
            let fuzzyStart = DispatchTime.now().uptimeNanoseconds
            let fuzzyCandidates = fuzzyHeadwordCandidates(for: normalized, scope: lexiconScope)
            let fuzzyElapsed = elapsedMS(since: fuzzyStart)
            candidateKeys = dedupePreservingOrder(standardCandidates + fuzzyCandidates)
            let hydrateStart = DispatchTime.now().uptimeNanoseconds
            entries = dedupeReferenceEntries(
                candidateKeys.flatMap { referenceNotesIndex.entriesByLookupKey[$0] ?? [] }
            )
            let hydrateElapsed = elapsedMS(since: hydrateStart)
            return ReferenceNotesRecoveryResult(
                normalized: normalized,
                standardCandidates: standardCandidates,
                candidateKeys: candidateKeys,
                entries: entries,
                usedDirectEntries: false,
                fuzzyCandidateCount: fuzzyCandidates.count,
                phaseTimings: [
                    .init(name: "standard_candidates", elapsedMS: standardElapsed),
                    .init(name: "direct_hydration", elapsedMS: directElapsed),
                    .init(name: "fuzzy_candidates", elapsedMS: fuzzyElapsed),
                    .init(name: "recovery_hydration", elapsedMS: hydrateElapsed),
                ]
            )
        } else {
            candidateKeys = standardCandidates
            entries = directEntries
            fuzzyCandidateCount = 0
            usedDirectEntries = true
        }

        return ReferenceNotesRecoveryResult(
            normalized: normalized,
            standardCandidates: standardCandidates,
            candidateKeys: candidateKeys,
            entries: entries,
            usedDirectEntries: usedDirectEntries,
            fuzzyCandidateCount: fuzzyCandidateCount,
            phaseTimings: [
                .init(name: "standard_candidates", elapsedMS: standardElapsed),
                .init(name: "direct_hydration", elapsedMS: directElapsed),
            ]
        )
    }

    private func searchRegionalSpellingNote(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        guard let regionalEnglishIndex else {
            return []
        }

        let matched: String
        let standardCandidates: [String]
        if regionalEnglishIndex.regionsByHeadword[normalized] != nil {
            matched = normalized
            standardCandidates = [normalized]
        } else {
            standardCandidates = standardLookupCandidates(for: normalized)
            let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
                regionalEnglishIndex.regionsByHeadword[$0] != nil
            }
            guard let candidate = candidates.first else { return [] }
            matched = candidate
        }

        guard let regions = regionalEnglishIndex.regionsByHeadword[matched],
              !regions.isEmpty else {
            return []
        }

        for americanForm in regionalSpellingBaseCandidates(for: matched) {
            guard americanForm != matched else { continue }
            let context = definitionContext(for: americanForm)

            let baseSense = context?.definitions.first ?? "the same thing as '\(americanForm)'"
            let label = regionalSpellingLabel(for: regions)
            var summary = "\(matched.capitalized) is a \(label) spelling variant of '\(americanForm)'. In ordinary meaning, it refers to \(baseSense)"
            summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)
            if let context, !context.relatedTerms.isEmpty {
                summary += " Related forms: \(context.relatedTerms.prefix(6).joined(separator: ", "))."
            }

            return [
                SearchCard(
                    title: matched == normalized ? term.capitalized : matched.capitalized,
                    source: "Regional spelling note",
                    summary: summary,
                    chips: ["regional spelling", "base: \(americanForm)", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)] + Array(regions.prefix(3)),
                    counterparts: [.init(label: "\(label) counterpart", term: americanForm)]
                )
            ]
        }

        return []
    }

    // MARK: - WordNet 3.x classic dict (data.noun/data.verb/data.adj/data.adv)

    private func searchWordNetClassic(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if wordNetClassicIndex == nil {
            wordNetClassicIndex = loadWordNetClassicIndex()
        }
        guard let index = wordNetClassicIndex else { return [] }

        let matched: String
        let standardCandidates: [String]
        if index.definitionsByHeadword[normalized] != nil {
            matched = normalized
            standardCandidates = [normalized]
        } else {
            standardCandidates = standardLookupCandidates(for: normalized)
            let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
                index.definitionsByHeadword[$0] != nil
            }
            guard let candidate = candidates.first else { return [] }
            matched = candidate
        }

        guard let definitions = index.definitionsByHeadword[matched],
              !definitions.isEmpty else {
            return []
        }

        let synonyms = index.synonymsByHeadword[matched] ?? []
        let posLabel: String
        if let posMap = index.senseCountByPOSByHeadword[matched], !posMap.isEmpty {
            posLabel = posMap
                .sorted { wordNetPOSName($0.key) < wordNetPOSName($1.key) }
                .map { "\(wordNetPOSName($0.key)): \($0.value)" }
                .joined(separator: " · ")
        } else {
            posLabel = "classic"
        }

        var summary = definitions.prefix(6).enumerated()
            .map { i, def in "\(i + 1). \(def)" }
            .joined(separator: "  ·  ")

        if !synonyms.isEmpty {
            summary += "  ·  Related lemmas: \(synonyms.prefix(10).joined(separator: ", "))."
        }
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "WordNet 3.x (Princeton dict)",
                summary: summary,
                chips: [posLabel, "classic", "wordnet", "princeton", lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates)]
            )
        ]
    }

    private func searchDerivedEnglishForm(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }
        guard !hasExactDefinitionHit(for: normalized) else { return [] }
        guard let inferred = inferredDerivedMeaning(for: normalized) else { return [] }

        var summary = "Derived from '\(inferred.base)'. \(term.capitalized) means \(inferred.shortDefinition)."
        if let baseDefinition = inferred.baseDefinitions.first {
            summary += " Base sense: \(baseDefinition)"
        }
        if !inferred.relatedTerms.isEmpty {
            summary += " Related word-family terms: \(inferred.relatedTerms.prefix(8).joined(separator: ", "))."
        }

        if regionalEnglishIndex == nil {
            regionalEnglishIndex = loadRegionalEnglishIndex()
        }
        if let regions = regionalEnglishIndex?.regionsByHeadword[normalized], !regions.isEmpty {
            summary += " Attested in the \(regions.joined(separator: ", ")) regional wordlists."
        }

        return [
            SearchCard(
                title: term.capitalized,
                source: "English word-family inference",
                summary: summary,
                chips: [
                    "derived form",
                    inferred.kind.label,
                    "base: \(inferred.base)"
                ]
            )
        ]
    }

    private func loadWordNetClassicIndex() -> WordNetClassicIndex {
        if let archive: WordNetClassicArchive = loadBundledArchive(fileName: "WordNetClassic.mgrt") {
            return WordNetClassicIndex(
                definitionsByHeadword: archive.definitionsByHeadword,
                synonymsByHeadword: archive.synonymsByHeadword,
                sortedHeadwords: archive.sortedHeadwords,
                senseCountByPOSByHeadword: archive.senseCountByPOSByHeadword
            )
        }

        let files: [(name: String, pos: String)] = [
            ("data.noun", "n"),
            ("data.verb", "v"),
            ("data.adj", "a"),
            ("data.adv", "r")
        ]

        var definitionsByHeadword: [String: [String]] = [:]
        var synonymsByHeadword: [String: [String]] = [:]
        var senseCountByPOSByHeadword: [String: [String: Int]] = [:]

        for file in files {
            guard let url = classicWordNetFileURL(named: file.name) else { continue }
            guard let data = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = data.components(separatedBy: .newlines)
            for line in lines {
                if line.isEmpty || line.first == " " { continue }
                guard let separator = line.firstIndex(of: "|") else { continue }

                let left = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let gloss = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !left.isEmpty, !gloss.isEmpty else { continue }

                let tokens = left.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if tokens.count < 5 { continue }

                guard let wordCount = Int(String(tokens[3]), radix: 16), wordCount > 0 else { continue }
                let needed = 4 + (wordCount * 2)
                if tokens.count < needed { continue }

                var words: [String] = []
                var idx = 4
                for _ in 0..<wordCount {
                    let raw = String(tokens[idx]).replacingOccurrences(of: "_", with: " ")
                    let normalizedWord = normalizedLookupKey(raw)
                    if !normalizedWord.isEmpty {
                        words.append(normalizedWord)
                    }
                    idx += 2
                }
                if words.isEmpty { continue }

                let uniqueWords = dedupePreservingOrder(words)
                for headword in uniqueWords {
                    var defs = definitionsByHeadword[headword] ?? []
                    if !defs.contains(gloss) {
                        defs.append(gloss)
                        definitionsByHeadword[headword] = Array(defs.prefix(10))
                    }

                    let related = uniqueWords.filter { $0 != headword }
                    if !related.isEmpty {
                        let merged = dedupePreservingOrder((synonymsByHeadword[headword] ?? []) + related)
                        synonymsByHeadword[headword] = Array(merged.prefix(64))
                    }

                    var posMap = senseCountByPOSByHeadword[headword] ?? [:]
                    posMap[file.pos, default: 0] += 1
                    senseCountByPOSByHeadword[headword] = posMap
                }
            }
        }

        return WordNetClassicIndex(
            definitionsByHeadword: definitionsByHeadword,
            synonymsByHeadword: synonymsByHeadword,
            sortedHeadwords: definitionsByHeadword.keys.sorted(),
            senseCountByPOSByHeadword: senseCountByPOSByHeadword
        )
    }

    private func searchAustralianGlossary(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        let standardCandidates = standardLookupCandidates(for: normalized)
        let candidates = matchedCandidates(for: normalized, standardCandidates: standardCandidates) {
            australianGlossary[$0] != nil
        }
        guard let matched = candidates.first,
              let entry = australianGlossary[matched] else {
            return []
        }

        var summary = entry.description
        summary += lookupMatchSummary(query: normalized, matched: matched, standardCandidates: standardCandidates)

        return [
            SearchCard(
                title: matched == normalized ? term.capitalized : matched.capitalized,
                source: "Australian usage notes",
                summary: summary,
                chips: [
                    "australian",
                    "usage",
                    lookupMatchChip(query: normalized, matched: matched, standardCandidates: standardCandidates),
                    "register: \(entry.register.rawValue)",
                    "slang-level: \(entry.slangLevel.rawValue)"
                ]
            )
        ]
    }

    private func loadAussieDictionaryIndex() -> AussieDictionaryIndex {
        if let archive: WordListArchive = loadBundledArchive(fileName: "AussieDictionary.mgrt") {
            let headwords = Set(archive.headwords)
            return AussieDictionaryIndex(headwords: headwords, sortedHeadwords: archive.headwords.sorted())
        }

        let url = resourceURL(
            fileName: "AussieDic.dic",
            fallbackRelativePath: "Australian-English-Dictionary-main/Source/2.5/Source/dictionaries/AussieDic.dic"
        )
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return AussieDictionaryIndex(headwords: [], sortedHeadwords: [])
        }

        var headwords = Set<String>()
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            if index == 0 { continue }
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let headword = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = normalizedLookupKey(headword)
            guard !normalized.isEmpty else { continue }
            headwords.insert(normalized)
        }

        return AussieDictionaryIndex(headwords: headwords, sortedHeadwords: headwords.sorted())
    }

    private func loadRegionalEnglishIndex() -> RegionalEnglishIndex {
        if let archive: RegionalEnglishArchive = loadBundledArchive(fileName: "RegionalEnglish.mgrt") {
            return RegionalEnglishIndex(
                regionsByHeadword: archive.regionsByHeadword,
                sortedHeadwords: archive.sortedHeadwords
            )
        }

        var regionsByHeadword: [String: Set<String>] = [:]

        for source in regionalEnglishSources {
            let url = resourceURL(
                fileName: URL(fileURLWithPath: source.relativePath).lastPathComponent,
                fallbackRelativePath: source.relativePath
            )
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                if index == 0 { continue }
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let headword = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
                let normalized = normalizedLookupKey(headword)
                guard !normalized.isEmpty else { continue }
                regionsByHeadword[normalized, default: []].insert(source.label)
            }
        }

        let normalizedRegions = regionsByHeadword
            .mapValues { Array($0).sorted() }

        return RegionalEnglishIndex(
            regionsByHeadword: normalizedRegions,
            sortedHeadwords: normalizedRegions.keys.sorted()
        )
    }

    private func loadReferenceNotesIndex() -> ReferenceNotesIndex? {
        if let archive: ReferenceNotesArchive = loadBundledArchive(fileName: "ReferenceNotes.mgrt") {
            return ReferenceNotesIndex(
                notes: archive.notes,
                entries: archive.entries,
                entriesByLookupKey: archive.entriesByLookupKey,
                entriesByPhraseCoreKey: archive.entriesByPhraseCoreKey,
                sortedHeadwords: archive.sortedHeadwords,
                topicTermsByEntryKey: archive.topicTermsByEntryKey,
                sourceTitles: Set(archive.sourceTitles)
            )
        }

        var notes: [ReferenceNote] = []
        if let archivedNotes: [ReferenceNote] = loadBundledArchive(fileName: "ReferenceNotes.mgrt") {
            notes = archivedNotes
        } else if let files = try? fileManager.contentsOfDirectory(at: authoringNotesURL, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let decoder = JSONDecoder()
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let fileNotes = try? decoder.decode([ReferenceNote].self, from: data) else {
                    continue
                }
                notes.append(contentsOf: fileNotes)
            }
        }
        guard !notes.isEmpty else { return nil }

        let entries = notes.flatMap(\.expandedEntries)

        var entriesByLookupKey: [String: [ReferenceEntry]] = [:]
        var entriesByPhraseCoreKey: [String: [ReferenceEntry]] = [:]
        for entry in entries {
            for key in entry.lookupKeys {
                let normalized = normalizedLookupKey(key)
                guard !normalized.isEmpty else { continue }
                entriesByLookupKey[normalized, default: []].append(entry)

                let phraseCoreKey = phraseCoreLookupKey(for: key)
                if phraseCoreKey != normalized {
                    entriesByPhraseCoreKey[phraseCoreKey, default: []].append(entry)
                }
            }
        }

        let resolvableLookupKeys = Set(entriesByLookupKey.keys)
        let semanticTopicChipsByEntryKey = Dictionary(
            uniqueKeysWithValues: entries.map {
                (referenceEntryCacheKey($0), semanticTopicChips(from: $0.chips))
            }
        )
        var topicTermsByEntryKey: [String: [String]] = [:]
        for entry in entries {
            let relatedTerms = dedupePreservingOrder(entry.seeAlso).filter { related in
                let key = normalizedLookupKey(related)
                guard key != normalizedLookupKey(entry.title) else { return false }
                return resolvableLookupKeys.contains(key)
            }
            let excludedTopicTerms = Set(
                ([entry.title] + relatedTerms + entry.counterparts.map(\.term))
                    .map(normalizedLookupKey)
            )
            topicTermsByEntryKey[referenceEntryCacheKey(entry)] = topicMeshTerms(
                for: entry,
                among: entries,
                semanticTopicChipsByEntryKey: semanticTopicChipsByEntryKey,
                excluding: excludedTopicTerms
            )
        }

        return ReferenceNotesIndex(
            notes: notes,
            entries: entries,
            entriesByLookupKey: entriesByLookupKey,
            entriesByPhraseCoreKey: entriesByPhraseCoreKey,
            sortedHeadwords: entries.map(\.title).map(normalizedLookupKey).sorted(),
            topicTermsByEntryKey: topicTermsByEntryKey,
            sourceTitles: Set(entries.map(\.sourceTitle))
        )
    }

    private func openReferenceNotesStore() -> ReferenceNotesStore? {
        let url = bundledResourceURL(fileName: "ReferenceNotes.sqlite3") ?? offlineArchiveFallbackURL(fileName: "ReferenceNotes.sqlite3")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return ReferenceNotesStore(url: url)
    }

    private func openCardLookupStore(fileName: String, tableName: String) -> CardLookupStore? {
        let url = bundledResourceURL(fileName: fileName) ?? offlineArchiveFallbackURL(fileName: fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return CardLookupStore(url: url, tableName: tableName)
    }

    private func searchOpenOfficeThesaurus(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        let matches = thesaurusCandidateMatches(for: normalized)
        guard !matches.openOffice.isEmpty else { return [] }

        if ooThesaurus == nil {
            ooThesaurus = loadOpenOfficeThesaurus()
        }
        guard let ooThesaurus else { return [] }

        let matchedKeys = matches.openOffice.filter { key in
            guard let groups = ooThesaurus[key] else { return false }
            return !groups.isEmpty
        }
        guard !matchedKeys.isEmpty else { return [] }

        let groups = matchedKeys.flatMap { ooThesaurus[$0] ?? [] }
        let flat = dedupePreservingOrder(groups.flatMap { parseThesaurusSenseLine($0) })
            .filter { normalizedLookupKey($0) != normalized }

        guard !flat.isEmpty else { return [] }

        return [
            SearchCard(
                title: term.capitalized,
                source: "OpenOffice British thesaurus",
                summary: flat.prefix(18).joined(separator: ", "),
                chips: [
                    "thesaurus",
                    "british english",
                    matchedKeys.contains(normalized) ? "exact hit" : "variant hit",
                    "forms: \(matchedKeys.count)"
                ]
            )
        ]
    }

    private func loadOpenOfficeThesaurus() -> [String: [String]] {
        if let archive: ThesaurusArchive = loadBundledArchive(fileName: "OpenOfficeThesaurus.mgrt") {
            ooSortedHeadwords = archive.entries.keys.sorted()
            return archive.entries
        }

        let url = resourceURL(fileName: "th_en_GB_final.dat", fallbackRelativePath: "oo2_th_en_GB/th_en_GB_final.dat")
        guard let data = try? String(contentsOf: url, encoding: .isoLatin1) else { return [:] }

        var result: [String: [String]] = [:]
        let lines = data.components(separatedBy: .newlines)
        var index = 2
        while index < lines.count {
            let head = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.isEmpty {
                index += 1
                continue
            }

            let parts = head.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let senseCount = Int(parts[1]) else {
                index += 1
                continue
            }

            let key = normalizedLookupKey(parts[0])
            var senses: [String] = []
            for offset in 1...senseCount where index + offset < lines.count {
                let sense = lines[index + offset].trimmingCharacters(in: .whitespacesAndNewlines)
                if !sense.isEmpty { senses.append(sense) }
            }
            result[key] = senses
            index += senseCount + 1
        }

        ooSortedHeadwords = result.keys.sorted()
        return result
    }

    private func searchMobyThesaurus(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        let matches = thesaurusCandidateMatches(for: normalized)
        guard !matches.moby.isEmpty else { return [] }

        if mobyThesaurus == nil {
            mobyThesaurus = loadMobyThesaurus()
        }
        guard let mobyThesaurus else { return [] }

        let matchedKeys = matches.moby.filter { key in
            guard let synonyms = mobyThesaurus[key] else { return false }
            return !synonyms.isEmpty
        }
        guard !matchedKeys.isEmpty else { return [] }

        let synonyms = dedupePreservingOrder(matchedKeys.flatMap { mobyThesaurus[$0] ?? [] })
            .filter { normalizedLookupKey($0) != normalized }

        guard !synonyms.isEmpty else { return [] }

        return [
            SearchCard(
                title: term.capitalized,
                source: "Moby Thesaurus II",
                summary: synonyms.prefix(20).joined(separator: ", "),
                chips: [
                    "moby",
                    "synonyms",
                    "public domain",
                    matchedKeys.contains(normalized) ? "exact hit" : "variant hit"
                ]
            )
        ]
    }

    private func loadMobyThesaurus() -> [String: [String]] {
        if let archive: ThesaurusArchive = loadBundledArchive(fileName: "MobyThesaurus.mgrt") {
            mobySortedHeadwords = archive.entries.keys.sorted()
            return archive.entries
        }

        let url = resourceURL(
            fileName: "mthesaur.txt",
            fallbackRelativePath: "Moby-Project-main/Moby Thesaurus II/mthesaur.txt"
        )
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var result: [String: [String]] = [:]
        for line in data.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let head = parts.first, !head.isEmpty else { continue }
            result[normalizedLookupKey(head)] = Array(parts.dropFirst())
        }
        mobySortedHeadwords = result.keys.sorted()
        return result
    }

    private func searchThesaurusFusion(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        let matches = thesaurusCandidateMatches(for: normalized)
        guard matches.hasMatches else { return [] }

        var ooSynonyms: [String] = []
        var mobySynonyms: [String] = []

        if !matches.openOffice.isEmpty {
            if ooThesaurus == nil { ooThesaurus = loadOpenOfficeThesaurus() }
            guard let ooThesaurus else { return [] }
            for key in matches.openOffice {
                if let groups = ooThesaurus[key], !groups.isEmpty {
                    ooSynonyms.append(contentsOf: groups.flatMap { parseThesaurusSenseLine($0) })
                }
            }
        }

        if !matches.moby.isEmpty {
            if mobyThesaurus == nil { mobyThesaurus = loadMobyThesaurus() }
            guard let mobyThesaurus else { return [] }
            for key in matches.moby {
                if let synonyms = mobyThesaurus[key], !synonyms.isEmpty {
                    mobySynonyms.append(contentsOf: synonyms)
                }
            }
        }

        let ooSet = Set(ooSynonyms.map { normalizedLookupKey($0) })
        let mobySet = Set(mobySynonyms.map { normalizedLookupKey($0) })

        let merged = dedupePreservingOrder(ooSynonyms + mobySynonyms)
            .filter { normalizedLookupKey($0) != normalized }

        guard !merged.isEmpty else { return [] }

        let ranked = rankSynonyms(merged, against: normalized, ooSet: ooSet, mobySet: mobySet)
        let crossSourceCount = ranked.filter {
            let n = normalizedLookupKey($0)
            return ooSet.contains(n) && mobySet.contains(n)
        }.count

        let chips = [
            "thesaurus fusion",
            "oo: \(min(ooSynonyms.count, 999))",
            "moby: \(min(mobySynonyms.count, 999))",
            "ranked: \(ranked.count)",
            "cross-source: \(crossSourceCount)"
        ]

        let source: String
        switch (ooSynonyms.isEmpty, mobySynonyms.isEmpty) {
        case (false, false):
            source = "Thesaurus fusion (OpenOffice + Moby) · ranked"
        case (false, true):
            source = "Thesaurus fusion (OpenOffice) · ranked"
        case (true, false):
            source = "Thesaurus fusion (Moby) · ranked"
        case (true, true):
            return []
        }

        return [
            SearchCard(
                title: term.capitalized,
                source: source,
                summary: ranked.prefix(28).joined(separator: ", "),
                chips: chips
            )
        ]
    }

    private func searchFreeDict(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if freeDictPairs == nil {
            freeDictPairs = loadFreeDictPairs()
        }

        guard let freeDictPairs else { return [] }
        let matches = freeDictPairs.compactMap { pair -> SearchCard? in
            guard let values = pair.translationsByHeadword[normalized], !values.isEmpty else { return nil }
            // Format summary with a language label prefix for immediate clarity
            let langLabel = freeDictLanguageLabel(pair.shortName)
            let translationsText = values.prefix(10).joined(separator: " · ")
            return SearchCard(
                title: term.capitalized,
                source: "FreeDict — \(langLabel)",
                summary: translationsText,
                chips: ["translation", pair.shortName, freeDictTargetCode(pair.shortName), "tei"]
            )
        }

        return Array(matches.prefix(8))
    }

    // Human-readable "English → Spanish" style label for a pair code like "eng-spa"
    private func freeDictLanguageLabel(_ pairCode: String) -> String {
        let parts = pairCode.split(separator: "-")
        guard parts.count == 2 else { return pairCode }
        let from = freeDictLangName(String(parts[0]))
        let to = freeDictLangName(String(parts[1]))
        return "\(from) → \(to)"
    }

    private func freeDictTargetCode(_ pairCode: String) -> String {
        String(pairCode.split(separator: "-").last ?? "??")
    }

    private func freeDictLangName(_ code: String) -> String {
        let map: [String: String] = [
            "eng": "English", "spa": "Spanish", "deu": "German", "fra": "French",
            "ita": "Italian", "por": "Portuguese", "nld": "Dutch", "rus": "Russian",
            "ara": "Arabic", "jpn": "Japanese", "zho": "Chinese", "kor": "Korean",
            "swe": "Swedish", "nor": "Norwegian", "dan": "Danish", "fin": "Finnish",
            "pol": "Polish", "ces": "Czech", "hun": "Hungarian", "tur": "Turkish",
            "lat": "Latin", "ell": "Greek", "heb": "Hebrew", "hin": "Hindi",
            "ben": "Bengali", "vie": "Vietnamese", "tha": "Thai", "ind": "Indonesian",
            "afr": "Afrikaans", "swa": "Swahili", "epo": "Esperanto", "iri": "Irish",
            "wel": "Welsh", "cat": "Catalan", "ron": "Romanian", "bul": "Bulgarian",
            "hrv": "Croatian", "srp": "Serbian", "slk": "Slovak", "slv": "Slovenian",
        ]
        return map[code] ?? code.uppercased()
    }

    private func loadFreeDictPairs() -> [FreeDictPair] {
        let root = dictionaryRootURL.appendingPathComponent("fd-dictionaries-master")
        guard let directories = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

        // High-value pairs get a higher entry cap for better coverage.
        let priorityPairs: Set<String> = ["eng-spa", "eng-deu", "eng-fra", "eng-ita", "eng-por", "eng-nld", "eng-swe", "eng-lat"]

        let allPairs = directories
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("eng-") }
            .sorted { a, b in
                // Sort priority pairs first
                let aPriority = priorityPairs.contains(a.lastPathComponent)
                let bPriority = priorityPairs.contains(b.lastPathComponent)
                if aPriority != bPriority { return aPriority }
                return a.lastPathComponent < b.lastPathComponent
            }

        return allPairs.compactMap { directory in
            let base = directory.lastPathComponent
            let isPriority = priorityPairs.contains(base)
            let entryCap = isPriority ? 15_000 : 6_000
            let teiURL = directory.appendingPathComponent("\(base).tei")
            guard let xml = try? String(contentsOf: teiURL, encoding: .utf8) else { return nil }

            var translations: [String: [String]] = [:]
            let entryPattern = #"(?s)<entry>(.*?)</entry>"#
            let orthPattern = #"<orth>(.*?)</orth>"#
            let quotePattern = #"<quote>(.*?)</quote>"#

            guard let entryRegex = try? NSRegularExpression(pattern: entryPattern),
                  let orthRegex = try? NSRegularExpression(pattern: orthPattern),
                  let quoteRegex = try? NSRegularExpression(pattern: quotePattern) else {
                return nil
            }

            let xmlRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
            entryRegex.enumerateMatches(in: xml, range: xmlRange) { match, _, stop in
                guard let match,
                      let entryRange = Range(match.range(at: 1), in: xml) else { return }
                let entry = String(xml[entryRange])
                let entryRangeNS = NSRange(entry.startIndex..<entry.endIndex, in: entry)

                guard let orthMatch = orthRegex.firstMatch(in: entry, range: entryRangeNS),
                      let orthRange = Range(orthMatch.range(at: 1), in: entry) else {
                    return
                }

                let headword = normalizedLookupKey(String(entry[orthRange]).decodedXMLEntities())
                guard !headword.isEmpty else { return }

                let quotes = quoteRegex.matches(in: entry, range: entryRangeNS).compactMap { quoteMatch in
                    Range(quoteMatch.range(at: 1), in: entry).map { String(entry[$0]).decodedXMLEntities() }
                }
                if !quotes.isEmpty {
                    translations[headword] = Array(NSOrderedSet(array: quotes)).compactMap { $0 as? String }
                }

                if translations.count > entryCap {
                    stop.pointee = true
                }
            }

            return FreeDictPair(
                name: freeDictLanguageLabel(base),
                shortName: base,
                translationsByHeadword: translations
            )
        }
    }

    private func searchZAMafoko(term: String) async -> [SearchCard] {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return [] }

        if zaMafokoEntries == nil {
            zaMafokoEntries = loadZAMafokoEntries()
        }

        guard let match = zaMafokoEntries?.first(where: { entry in
            entry.values.values.contains { normalizedLookupKey($0) == normalized }
        }) else {
            return []
        }

        let rendered = match.values
            .sorted { $0.key < $1.key }
            .map { "\($0.key.uppercased()): \($0.value)" }
            .joined(separator: " · ")

        return [
            SearchCard(
                title: term.capitalized,
                source: "ZA Mafoko multilingual termbank",
                summary: rendered,
                chips: ["translation", "south africa", "multilingual"]
            )
        ]
    }

    private func loadZAMafokoEntries() -> [ZAMafokoEntry] {
        if let archive: ZAMafokoArchive = loadBundledArchive(fileName: "ZAMafoko.mgrt") {
            return archive.entries
        }

        let url = resourceURL(
            fileName: "combined_all.jsonl",
            fallbackRelativePath: "za-mafoko-master/data/combined_all.jsonl"
        )
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        return data
            .components(separatedBy: .newlines)
            .compactMap { line -> ZAMafokoEntry? in
                guard let lineData = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }

                let supportedKeys = ["eng", "afr", "zul", "xho", "ssw", "nbl", "tsn", "nso", "sot", "ven", "tso", "ngh"]
                let values = supportedKeys.reduce(into: [String: String]()) { partial, key in
                    if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        partial[key] = value
                    }
                }
                return values.isEmpty ? nil : ZAMafokoEntry(values: values)
            }
    }

    private func normalizedLookupKey(_ string: String) -> String {
        if let cached = cacheLookup(
            cacheKey: string,
            in: &normalizedLookupCache,
            order: &normalizedLookupCacheOrder
        ) {
            return cached
        }
        let normalized = Self.normalizedLookupKeyStatic(string)
        storeCache(
            cacheKey: string,
            value: normalized,
            in: &normalizedLookupCache,
            order: &normalizedLookupCacheOrder,
            limit: 4096
        )
        return normalized
    }

    fileprivate static func normalizedLookupKeyStatic(_ string: String) -> String {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201B}", with: "'")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    fileprivate static func displayTitleStatic(_ headword: String) -> String {
        headword
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    fileprivate static func fastLookupPOSBreakdownStatic(_ posCounts: [String: Int], fallback: String) -> String {
        guard !posCounts.isEmpty else { return fallback }
        return posCounts
            .sorted { lhs, rhs in wordnetPOSLabelStatic(lhs.key) < wordnetPOSLabelStatic(rhs.key) }
            .map { "\(wordnetPOSLabelStatic($0.key)): \($0.value)" }
            .joined(separator: " · ")
    }

    fileprivate static func fastLookupSummaryStatic(
        definitions: [String],
        relatedTerms: [String],
        relatedLimit: Int
    ) -> String {
        var summary = definitions
            .prefix(6)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "  ·  ")
        if !relatedTerms.isEmpty {
            summary += "  ·  Related lemmas: \(relatedTerms.prefix(relatedLimit).joined(separator: ", "))."
        }
        return summary
    }

    fileprivate static func wordnetPOSLabelStatic(_ pos: String) -> String {
        switch pos {
        case "n": return "noun"
        case "v": return "verb"
        case "a", "s": return "adjective"
        case "r": return "adverb"
        default: return pos
        }
    }

    private func phraseCoreLookupKey(for string: String) -> String {
        let normalized = normalizedLookupKey(string)
        guard normalized.contains(" ") || normalized.contains("-") || normalized.contains("'") else {
            return normalized
        }

        let tokenized = normalized
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { token in
                !token.isEmpty && !phraseCoreStopwords.contains(token)
            }

        return tokenized.joined(separator: " ")
    }

    // Prefix suggestions via binary search on pre-sorted headwords — O(log n + k).
    public func suggestedTerms(prefix: String) async -> [String] {
        if Task.isCancelled { return [] }
        let p = normalizedLookupKey(prefix)
        guard p.count >= 2 else { return [] }
        if let cached = cacheLookup(cacheKey: p, in: &suggestionsCache, order: &suggestionsCacheOrder) {
            return cached
        }
        if searchLexicon == nil {
            searchLexicon = loadSearchLexicon()
        }
        guard let lexicon = searchLexicon else { return [] }

        var merged: [String] = []
        merged.append(contentsOf: prefixMatches(in: lexicon.sortedHeadwords, prefix: p, limit: 24))
        if p.count >= 3 {
            let compactPrefix = compactLookupKey(p)
            if compactPrefix != p, compactPrefix.count >= 2 {
                merged.append(contentsOf: prefixMatches(in: lexicon.sortedHeadwords, prefix: compactPrefix, limit: 12))
            }
        }

        var seen = Set<String>()
        let suggestions = merged.filter { candidate in
            guard candidate != p, !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
        .prefix(8)
        .map { $0 }

        if Task.isCancelled { return [] }
        storeCache(
            cacheKey: p,
            value: suggestions,
            in: &suggestionsCache,
            order: &suggestionsCacheOrder,
            limit: CacheLimits.suggestions
        )
        return suggestions
    }

    public func australianDidYouMean(term: String) async -> [String] {
        let normalized = normalizedLookupKey(term)
        guard normalized.count >= 2 else { return [] }

        if aussieDictionaryIndex == nil {
            aussieDictionaryIndex = loadAussieDictionaryIndex()
        }

        var candidates = Set<String>()

        let variants = australianVariants(for: normalized)
        if let index = aussieDictionaryIndex {
            for variant in variants where variant != normalized && index.headwords.contains(variant) {
                candidates.insert(variant)
            }

            let auPrefix = String(normalized.prefix(3))
            if !auPrefix.isEmpty {
                prefixMatches(in: index.sortedHeadwords, prefix: auPrefix, limit: 8)
                    .filter { $0 != normalized }
                    .forEach { candidates.insert($0) }
            }
        }

        australianGlossary.keys
            .filter { $0.hasPrefix(String(normalized.prefix(3))) && $0 != normalized }
            .prefix(8)
            .forEach { candidates.insert($0) }

        return Array(candidates)
            .sorted()
            .prefix(6)
            .map { $0 }
    }

    public func didYouMean(term: String) async -> [String] {
        await didYouMean(term: term, lexiconScope: .global)
    }

    private func didYouMean(term: String, lexiconScope: LexiconScope) async -> [String] {
        if Task.isCancelled { return [] }
        let normalized = normalizedLookupKey(term)
        guard normalized.count >= 2 else { return [] }
        let cacheKey = lexiconScope == .global ? normalized : "deep::\(normalized)"
        if let cached = cacheLookup(cacheKey: cacheKey, in: &didYouMeanCache, order: &didYouMeanCacheOrder) {
            return cached
        }

        let lexicon: SearchLexicon
        switch lexiconScope {
        case .global:
            if searchLexicon == nil {
                searchLexicon = loadSearchLexicon()
            }
            guard let searchLexicon else { return [] }
            lexicon = searchLexicon
        case .deepLookup:
            if deepLookupLexicon == nil {
                deepLookupLexicon = loadDeepLookupLexicon()
            }
            guard let deepLookupLexicon else { return [] }
            lexicon = deepLookupLexicon
        }

        let directCandidates = standardLookupCandidates(for: normalized)
        let hasDirectResolution = directCandidates.contains { lexicon.headwords.contains($0) } ||
            australianGlossary[normalized] != nil
        guard !hasDirectResolution else { return [] }

        let candidates = dedupePreservingOrder(
            fuzzyHeadwordCandidates(for: normalized, scope: lexiconScope) +
            (lexiconScope == .global ? await australianDidYouMean(term: term) : []) +
            prefixFallbackCandidates(for: normalized, lexicon: lexicon)
        )

        let suggestions = Array(candidates.prefix(6))
        if Task.isCancelled { return [] }
        storeCache(
            cacheKey: cacheKey,
            value: suggestions,
            in: &didYouMeanCache,
            order: &didYouMeanCacheOrder,
            limit: CacheLimits.didYouMean
        )
        return suggestions
    }

    private func prefixMatches(in sorted: [String], prefix: String, limit: Int) -> [String] {
        guard !sorted.isEmpty, !prefix.isEmpty else { return [] }
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        var results: [String] = []
        var index = lo
        while index < sorted.count, sorted[index].hasPrefix(prefix), results.count < limit {
            results.append(sorted[index])
            index += 1
        }
        return results
    }

    private func prefixFallbackCandidates(for normalizedTerm: String, lexicon: SearchLexicon? = nil) -> [String] {
        let activeLexicon: SearchLexicon
        if let lexicon {
            activeLexicon = lexicon
        } else {
            if searchLexicon == nil {
                searchLexicon = loadSearchLexicon()
            }
            guard let searchLexicon else { return [] }
            activeLexicon = searchLexicon
        }
        let prefix = String(normalizedTerm.prefix(min(3, normalizedTerm.count)))
        guard prefix.count >= 2 else { return [] }
        return prefixMatches(in: activeLexicon.sortedHeadwords, prefix: prefix, limit: 8)
            .filter { $0 != normalizedTerm }
    }

    private func australianVariants(for base: String) -> [String] {
        var variants = Set<String>([base])

        if base.hasSuffix("our") {
            variants.insert(String(base.dropLast(3)) + "or")
        }
        if base.hasSuffix("or") {
            variants.insert(String(base.dropLast(2)) + "our")
        }

        if base.hasSuffix("ise") {
            variants.insert(String(base.dropLast(3)) + "ize")
        }
        if base.hasSuffix("ize") {
            variants.insert(String(base.dropLast(3)) + "ise")
        }

        if base.hasSuffix("yse") {
            variants.insert(String(base.dropLast(3)) + "yze")
        }
        if base.hasSuffix("yze") {
            variants.insert(String(base.dropLast(3)) + "yse")
        }

        if base.hasSuffix("re") {
            variants.insert(String(base.dropLast(2)) + "er")
        }
        if base.hasSuffix("er") {
            variants.insert(String(base.dropLast(2)) + "re")
        }

        if base.hasSuffix("ogue") {
            variants.insert(String(base.dropLast(4)) + "og")
        }
        if base.hasSuffix("og") {
            variants.insert(String(base.dropLast(2)) + "ogue")
        }

        return Array(variants)
    }

    private func thesaurusLookupCandidates(for normalizedTerm: String) -> [String] {
        let standard = standardLookupCandidates(for: normalizedTerm)
        if let ooThesaurus, standard.contains(where: { key in
            guard let groups = ooThesaurus[key] else { return false }
            return !groups.isEmpty
        }) {
            return standard
        }
        if let mobyThesaurus, standard.contains(where: { key in
            guard let synonyms = mobyThesaurus[key] else { return false }
            return !synonyms.isEmpty
        }) {
            return standard
        }
        return lookupCandidates(for: normalizedTerm)
    }

    private enum LexiconScope {
        case global
        case deepLookup
    }

    private func matchedCandidates(
        for normalizedTerm: String,
        standardCandidates: [String],
        lexiconScope: LexiconScope = .global,
        matches: (String) -> Bool
    ) -> [String] {
        let directMatches = standardCandidates.filter(matches)
        if !directMatches.isEmpty {
            return directMatches
        }

        let fuzzyMatches = fuzzyHeadwordCandidates(for: normalizedTerm, scope: lexiconScope).filter(matches)
        return dedupePreservingOrder(directMatches + fuzzyMatches)
    }

    private func standardLookupCandidates(for normalizedTerm: String) -> [String] {
        if let cached = cacheLookup(
            cacheKey: normalizedTerm,
            in: &standardLookupCandidatesCache,
            order: &standardLookupCandidatesCacheOrder
        ) {
            return cached
        }

        let candidates = dedupePreservingOrder(
            [normalizedTerm] +
            australianVariants(for: normalizedTerm) +
            regionalSpellingBaseCandidates(for: normalizedTerm) +
            inflectionVariants(for: normalizedTerm) +
            derivationalBaseCandidates(for: normalizedTerm).map(\.base) +
            punctuationVariants(for: normalizedTerm)
        )
        storeCache(
            cacheKey: normalizedTerm,
            value: candidates,
            in: &standardLookupCandidatesCache,
            order: &standardLookupCandidatesCacheOrder,
            limit: CacheLimits.lookupCandidates
        )
        return candidates
    }

    private func lookupCandidates(for normalizedTerm: String, includeFuzzy: Bool = true) -> [String] {
        if includeFuzzy, let cached = cacheLookup(
            cacheKey: normalizedTerm,
            in: &lookupCandidatesCache,
            order: &lookupCandidatesCacheOrder
        ) {
            return cached
        }

        var candidates = standardLookupCandidates(for: normalizedTerm)
        if includeFuzzy {
            candidates.append(contentsOf: fuzzyHeadwordCandidates(for: normalizedTerm))
        }
        let deduped = dedupePreservingOrder(candidates)
        if includeFuzzy {
            storeCache(
                cacheKey: normalizedTerm,
                value: deduped,
                in: &lookupCandidatesCache,
                order: &lookupCandidatesCacheOrder,
                limit: CacheLimits.lookupCandidates
            )
        }
        return deduped
    }

    private func punctuationVariants(for term: String) -> [String] {
        let spaced = term
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let apostropheLight = spaced.replacingOccurrences(of: "'", with: "")
        return dedupePreservingOrder([
            spaced,
            spaced.replacingOccurrences(of: " ", with: "-"),
            spaced.replacingOccurrences(of: " ", with: ""),
            apostropheLight,
            apostropheLight.replacingOccurrences(of: " ", with: "-"),
            apostropheLight.replacingOccurrences(of: " ", with: "")
        ])
    }

    private func fuzzyHeadwordCandidates(for normalizedTerm: String, scope: LexiconScope = .global) -> [String] {
        guard normalizedTerm.count >= 3 else { return [] }
        let cacheKey = scope == .global ? normalizedTerm : "deep::\(normalizedTerm)"
        if let cached = cacheLookup(
            cacheKey: cacheKey,
            in: &fuzzyHeadwordCandidatesCache,
            order: &fuzzyHeadwordCandidatesCacheOrder
        ) {
            return cached
        }

        let lexicon: SearchLexicon
        switch scope {
        case .global:
            if searchLexicon == nil {
                searchLexicon = loadSearchLexicon()
            }
            guard let searchLexicon else { return [] }
            lexicon = searchLexicon
        case .deepLookup:
            if deepLookupLexicon == nil {
                deepLookupLexicon = loadDeepLookupLexicon()
            }
            guard let deepLookupLexicon else { return [] }
            lexicon = deepLookupLexicon
        }

        let limit = typoEditLimit(for: normalizedTerm)
        var candidates = Set<String>()

        candidates.formUnion(
            deletionSignatures(for: normalizedTerm)
                .filter { lexicon.headwords.contains($0) }
        )
        candidates.formUnion(
            singleCharacterDuplicationVariants(for: normalizedTerm)
                .filter { lexicon.headwords.contains($0) }
        )
        candidates.formUnion(
            collapsedRepeatVariants(for: normalizedTerm)
                .filter { lexicon.headwords.contains($0) }
        )
        for transposed in adjacentTranspositions(for: normalizedTerm) where lexicon.headwords.contains(transposed) {
            candidates.insert(transposed)
        }

        let compactQuery = compactLookupKey(normalizedTerm)
        if candidates.isEmpty {
            let prefixLimit = scope == .deepLookup ? 12 : 24
            let compactPrefixLimit = scope == .deepLookup ? 6 : 12
            let targetCandidates = scope == .deepLookup ? 20 : 40

            let prefixes = [3, 2, 4]
                .filter { normalizedTerm.count >= $0 }
                .map { String(normalizedTerm.prefix($0)) }
            for prefix in prefixes {
                for match in prefixMatches(in: lexicon.sortedHeadwords, prefix: prefix, limit: prefixLimit) {
                    candidates.insert(match)
                    if candidates.count >= targetCandidates {
                        break
                    }
                }
                if candidates.count >= targetCandidates {
                    break
                }
            }

            if candidates.count < (targetCandidates / 2), compactQuery != normalizedTerm {
                let compactPrefixes = [3, 2, 4]
                    .filter { compactQuery.count >= $0 }
                    .map { String(compactQuery.prefix($0)) }
                for prefix in compactPrefixes {
                    for match in prefixMatches(in: lexicon.sortedHeadwords, prefix: prefix, limit: compactPrefixLimit) {
                        candidates.insert(match)
                        if candidates.count >= targetCandidates {
                            break
                        }
                    }
                    if candidates.count >= targetCandidates {
                        break
                    }
                }
            }
        }

        let queryLength = normalizedTerm.count
        var scored: [(String, Int)] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            if candidate == normalizedTerm { continue }
            if abs(candidate.count - queryLength) > limit { continue }

            let sharedPrefix = sharedPrefixLength(normalizedTerm, candidate)
            if sharedPrefix == 0 && limit <= 1 { continue }

            guard let edit = boundedLevenshtein(normalizedTerm, candidate, limit: limit) else { continue }

            let compactCandidate = compactLookupKey(candidate)
            let compactBoost = compactQuery == compactCandidate ? 6 : 0
            let spaceBoost = candidate.contains(" ") || candidate.contains("-") ? 1 : 0
            let score = max(0, (limit + 1) * 10 - (edit * 10)) + sharedPrefix + compactBoost + spaceBoost
            scored.append((candidate, score))
        }

        scored.sort {
            if $0.1 == $1.1 { return $0.0 < $1.0 }
            return $0.1 > $1.1
        }

        let ranked = Array(scored.prefix(10).map(\.0))
        storeCache(
            cacheKey: cacheKey,
            value: ranked,
            in: &fuzzyHeadwordCandidatesCache,
            order: &fuzzyHeadwordCandidatesCacheOrder,
            limit: CacheLimits.fuzzyCandidates
        )
        return ranked
    }

    private func cacheLookup<Key, Value>(
        cacheKey: Key,
        in cache: inout [Key: Value],
        order: inout [Key]
    ) -> Value? where Key: Hashable & Equatable {
        guard let value = cache[cacheKey] else {
            return nil
        }
        if let index = order.firstIndex(of: cacheKey) {
            order.remove(at: index)
        }
        order.append(cacheKey)
        return value
    }

    private func storeCache<Key, Value>(
        cacheKey: Key,
        value: Value,
        in cache: inout [Key: Value],
        order: inout [Key],
        limit: Int
    ) where Key: Hashable & Equatable {
        cache[cacheKey] = value
        if let existingIndex = order.firstIndex(of: cacheKey) {
            order.remove(at: existingIndex)
        }
        order.append(cacheKey)
        while cache.count > limit, let evicted = order.first {
            order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func hasExactDefinitionHit(for normalizedTerm: String) -> Bool {
        let hasFastLookup = fastLookupContains(headword: normalizedTerm)
        let hasGlossary = australianGlossary[normalizedTerm] != nil
        let hasReferenceNote: Bool
        if referenceNotesStore == nil && referenceNotesIndex == nil {
            loadReferenceNoteArtifacts()
        }
        if let referenceNotesStore {
            hasReferenceNote = referenceNotesStore.hasLookupKey(normalizedTerm)
        } else {
            if referenceNotesIndex == nil { referenceNotesIndex = loadReferenceNotesIndex() }
            hasReferenceNote = !((referenceNotesIndex?.entriesByLookupKey[normalizedTerm]) ?? []).isEmpty
        }
        return hasFastLookup || hasGlossary || hasReferenceNote
    }

    private func shouldSearchReferenceNotesOnFastDefine(term: String, loadIfNeeded: Bool = true) -> Bool {
        let normalized = normalizedLookupKey(term)
        guard !normalized.isEmpty else { return false }
        let phraseCoreKey = phraseCoreLookupKey(for: term)

        if referenceNotesStore == nil && referenceNotesIndex == nil {
            if loadIfNeeded {
                loadReferenceNoteArtifacts()
            } else {
                return false
            }
        }

        if let referenceNotesStore {
            if referenceNotesStore.hasLookupKey(normalized) {
                return true
            }
            if phraseCoreKey != normalized, referenceNotesStore.hasPhraseCoreKey(phraseCoreKey) {
                return true
            }
            return false
        }

        if referenceNotesIndex == nil {
            if loadIfNeeded {
                referenceNotesIndex = loadReferenceNotesIndex()
            } else {
                return false
            }
        }
        if !((referenceNotesIndex?.entriesByLookupKey[normalized]) ?? []).isEmpty {
            return true
        }
        if phraseCoreKey != normalized, !((referenceNotesIndex?.entriesByPhraseCoreKey[phraseCoreKey]) ?? []).isEmpty {
            return true
        }
        return false
    }

    private func fastDefineCards(term: String, normalizedQuery: String) -> [SearchCard]? {
        guard !normalizedQuery.isEmpty else { return nil }

        let standardCandidates: [String]
        let matched: String?
        let matchedCards: [SearchCard]
        let exactCards = fastLookupCards(for: normalizedQuery, displayTerm: term)
        if !exactCards.isEmpty {
            standardCandidates = [normalizedQuery]
            matched = normalizedQuery
            matchedCards = exactCards
        } else {
            let candidates = standardLookupCandidates(for: normalizedQuery)
            standardCandidates = candidates
            let firstMatch = firstFastLookupMatch(in: candidates, displayTerm: term)
            matched = firstMatch?.headword
            matchedCards = firstMatch?.cards ?? []
        }
        guard let matched, !matchedCards.isEmpty else {
            return nil
        }

        return matchedCards.map { card in
            let matchChip = lookupMatchChip(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
            let chips = dedupePreservingOrder(card.chips + [matchChip])
            let summary: String
            let matchSummary = lookupMatchSummary(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
            if matchSummary.isEmpty {
                summary = card.summary
            } else {
                summary = card.summary + matchSummary
            }

            return SearchCard(
                title: card.title,
                source: card.source,
                summary: summary,
                chips: chips,
                counterparts: card.counterparts,
                antonyms: card.antonyms,
                relatedTerms: card.relatedTerms,
                topicTerms: card.topicTerms
            )
        }
    }

    private func fastSynonymCards(term: String, normalizedQuery: String) -> [SearchCard]? {
        guard !normalizedQuery.isEmpty else { return nil }
        loadSynonymLookupArtifacts()

        guard let store = synonymLookupStore else {
            return nil
        }

        if let rows = store.rows(for: normalizedQuery) {
            return hydratedFastIntentCards(
                rows: rows,
                query: normalizedQuery,
                matched: normalizedQuery,
                usedVariantCandidate: false
            )
        }

        let standardCandidates = standardLookupCandidates(for: normalizedQuery)
        guard let match = store.firstRows(forAny: standardCandidates.dropFirst()) else {
            return nil
        }

        return hydratedFastIntentCards(
            rows: match.rows,
            query: normalizedQuery,
            matched: match.key,
            usedVariantCandidate: true
        )
    }

    private func fastTranslationCards(term: String, normalizedQuery: String) -> [SearchCard]? {
        guard !normalizedQuery.isEmpty else { return nil }
        loadTranslationLookupArtifacts()

        guard let store = translationLookupStore else {
            return nil
        }

        if let rows = store.rows(for: normalizedQuery) {
            return hydratedFastIntentCards(
                rows: rows,
                query: normalizedQuery,
                matched: normalizedQuery,
                usedVariantCandidate: false
            )
        }

        let standardCandidates = standardLookupCandidates(for: normalizedQuery)
        guard let match = store.firstRows(forAny: standardCandidates.dropFirst()) else {
            return nil
        }

        return hydratedFastIntentCards(
            rows: match.rows,
            query: normalizedQuery,
            matched: match.key,
            usedVariantCandidate: true
        )
    }

    private func fastSlangCards(term: String, normalizedQuery: String) -> [SearchCard]? {
        guard !normalizedQuery.isEmpty else { return nil }

        let standardCandidates = standardLookupCandidates(for: normalizedQuery)

        if let matched = standardCandidates.first(where: { australianGlossary[$0] != nil }),
           let entry = australianGlossary[matched] {
            let matchChip = lookupMatchChip(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
            let matchSummary = lookupMatchSummary(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
            let summary = entry.description + matchSummary

            return [
                SearchCard(
                    title: matched == normalizedQuery ? term.capitalized : matched.capitalized,
                    source: "Australian usage notes",
                    summary: summary,
                    chips: [
                        "australian",
                        "usage",
                        matchChip,
                        "register: \(entry.register.rawValue)",
                        "slang-level: \(entry.slangLevel.rawValue)"
                    ]
                )
            ]
        }

        loadAustralianArtifacts()
        guard let aussieDictionaryIndex else { return nil }
        guard let matched = standardCandidates.first(where: { aussieDictionaryIndex.headwords.contains($0) }) else {
            return nil
        }

        let matchChip = lookupMatchChip(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
        let matchSummary = lookupMatchSummary(query: normalizedQuery, matched: matched, standardCandidates: standardCandidates)
        let summary = "Confirmed in the bundled Australian English headword list for local spelling and colloquial vocabulary coverage." + matchSummary

        return [
            SearchCard(
                title: matched == normalizedQuery ? term.capitalized : matched.capitalized,
                source: "Australian English Dictionary",
                summary: summary,
                chips: [
                    "australian english",
                    "headword",
                    matchChip
                ]
            )
        ]
    }

    private func hydratedFastIntentCards(
        rows: [StoredCardLookupRow],
        query: String,
        matched: String,
        usedVariantCandidate: Bool
    ) -> [SearchCard] {
        let matchChip = fastIntentMatchChip(query: query, matched: matched, usedVariantCandidate: usedVariantCandidate)
        let matchSummary = fastIntentMatchSummary(query: query, matched: matched, usedVariantCandidate: usedVariantCandidate)

        return rows.map { row in
            let chips = dedupePreservingOrder(row.chips + [matchChip])
            let summary = matchSummary.isEmpty ? row.summary : row.summary + matchSummary
            return SearchCard(
                title: row.title,
                source: row.source,
                summary: summary,
                chips: chips
            )
        }
    }

    private func fastIntentMatchChip(query: String, matched: String, usedVariantCandidate: Bool) -> String {
        if matched == query { return "exact hit" }
        return usedVariantCandidate ? "variant hit" : "typo-tolerant hit"
    }

    private func fastIntentMatchSummary(query: String, matched: String, usedVariantCandidate: Bool) -> String {
        guard matched != query else { return "" }
        if usedVariantCandidate {
            return " Matched through the variant form '\(matched)'."
        }
        return " Matched through the nearby spelling '\(matched)'."
    }

    private func firstFastLookupMatch(in headwords: [String], displayTerm: String) -> (headword: String, cards: [SearchCard])? {
        for headword in headwords {
            let cards = fastLookupCards(for: headword, displayTerm: displayTerm)
            if !cards.isEmpty {
                return (headword, cards)
            }
        }
        return nil
    }

    private func lookupMatchChip(query: String, matched: String, standardCandidates: [String]) -> String {
        if matched == query { return "exact hit" }
        if standardCandidates.contains(matched) { return "variant hit" }
        return "typo-tolerant hit"
    }

    private func lookupMatchSummary(query: String, matched: String, standardCandidates: [String]) -> String {
        guard matched != query else { return "" }
        if standardCandidates.contains(matched) {
            return " Matched through the variant form '\(matched)'."
        }
        return " Matched through the nearby spelling '\(matched)'."
    }

    private func inferredDerivedMeaning(for term: String) -> DerivedMeaning? {
        for candidate in derivationalBaseCandidates(for: term) {
            guard let context = definitionContext(for: candidate.base) else { continue }
            return DerivedMeaning(
                base: candidate.base,
                kind: candidate.kind,
                shortDefinition: candidate.kind.definition(for: term, base: candidate.base),
                baseDefinitions: context.definitions,
                relatedTerms: context.relatedTerms
            )
        }
        return nil
    }

    private func inferredDerivedMeaningClassicOnly(for term: String) -> DerivedMeaning? {
        for candidate in derivationalBaseCandidates(for: term) {
            guard let context = definitionContextClassicOnly(for: candidate.base) else { continue }
            return DerivedMeaning(
                base: candidate.base,
                kind: candidate.kind,
                shortDefinition: candidate.kind.definition(for: term, base: candidate.base),
                baseDefinitions: context.definitions,
                relatedTerms: context.relatedTerms
            )
        }
        return nil
    }

    private func fastDefinitionContext(for normalizedBase: String) -> DefinitionContext? {
        if fastLookupStore == nil && fastLookupIndex == nil {
            loadFastLookupArtifacts()
        }

        var definitions: [String] = []
        var relatedTerms: [String] = []

        if let fastLookupStore, let row = fastLookupStore.row(for: normalizedBase) {
            definitions.append(contentsOf: row.definitions.prefix(4))
            relatedTerms.append(contentsOf: row.relatedTerms)
        } else if let fastLookupIndex {
            if let modern = fastLookupIndex.modernEntriesByHeadword[normalizedBase] {
                definitions.append(contentsOf: modern.definitions.prefix(4))
                relatedTerms.append(contentsOf: modern.relatedTerms)
            }
            if let classic = fastLookupIndex.classicEntriesByHeadword[normalizedBase] {
                definitions.append(contentsOf: classic.definitions.prefix(4))
                relatedTerms.append(contentsOf: classic.relatedTerms)
            }
        }

        let dedupedDefinitions = dedupePreservingOrder(definitions)
        guard !dedupedDefinitions.isEmpty else { return nil }

        let dedupedRelated = dedupePreservingOrder(relatedTerms)
            .filter { normalizedLookupKey($0) != normalizedBase }

        return DefinitionContext(
            definitions: dedupedDefinitions,
            relatedTerms: dedupedRelated
        )
    }

    private func referenceNotesDefinitionContext(for normalizedBase: String, loadIfNeeded: Bool) -> DefinitionContext? {
        if loadIfNeeded {
            loadReferenceNoteArtifacts()
        } else if referenceNotesStore == nil && referenceNotesIndex == nil {
            return nil
        }

        var definitions: [String] = []
        var relatedTerms: [String] = []

        if let referenceNotesStore {
            let rows = dedupeStoredReferenceRows(referenceNotesStore.lookupRows(for: normalizedBase))
            if !rows.isEmpty {
                definitions.append(contentsOf: rows.map(\.entry.summary).prefix(4))
                relatedTerms.append(contentsOf: rows.flatMap { [$0.entry.title] + $0.entry.synonyms + $0.entry.seeAlso })
            }
        } else {
            if loadIfNeeded, referenceNotesIndex == nil {
                referenceNotesIndex = loadReferenceNotesIndex()
            }
            if let noteEntries = referenceNotesIndex?.entriesByLookupKey[normalizedBase],
               !noteEntries.isEmpty {
                definitions.append(contentsOf: noteEntries.map(\.summary).prefix(4))
                relatedTerms.append(contentsOf: noteEntries.flatMap { [$0.title] + $0.synonyms + $0.seeAlso })
            }
        }

        let dedupedDefinitions = dedupePreservingOrder(definitions)
        guard !dedupedDefinitions.isEmpty else { return nil }

        let dedupedRelated = dedupePreservingOrder(relatedTerms)
            .filter { normalizedLookupKey($0) != normalizedBase }

        return DefinitionContext(
            definitions: dedupedDefinitions,
            relatedTerms: dedupedRelated
        )
    }

    private func definitionContext(for normalizedBase: String) -> DefinitionContext? {
        if let cached = cacheLookup(
            cacheKey: normalizedBase,
            in: &definitionContextCache,
            order: &definitionContextCacheOrder
        ) {
            return cached
        }

        var definitions: [String] = []
        var relatedTerms: [String] = []

        if let fastContext = fastDefinitionContext(for: normalizedBase) {
            definitions.append(contentsOf: fastContext.definitions.prefix(4))
            relatedTerms.append(contentsOf: fastContext.relatedTerms)
        }

        if wordNetClassicIndex == nil, definitions.isEmpty {
            wordNetClassicIndex = loadWordNetClassicIndex()
        }
        if let index = wordNetClassicIndex,
           let classicDefinitions = index.definitionsByHeadword[normalizedBase],
           !classicDefinitions.isEmpty {
            definitions.append(contentsOf: classicDefinitions.prefix(4))
            relatedTerms.append(contentsOf: index.synonymsByHeadword[normalizedBase] ?? [])
        }

        if let referenceContext = referenceNotesDefinitionContext(
            for: normalizedBase,
            loadIfNeeded: definitions.isEmpty
        ) {
            definitions.append(contentsOf: referenceContext.definitions.prefix(4))
            relatedTerms.append(contentsOf: referenceContext.relatedTerms)
        }

        if wordNetIndex == nil, definitions.isEmpty {
            wordNetIndex = loadWordNetIndex()
        }
        if let index = wordNetIndex,
           let synsets = index.synsetsByHeadword[normalizedBase],
           !synsets.isEmpty {
            definitions.append(contentsOf: synsets.compactMap { index.definitionBySynset[$0] }.prefix(4))
            relatedTerms.append(contentsOf: synsets.flatMap { index.headwordsBySynset[$0] ?? [] })
        }

        let dedupedDefinitions = dedupePreservingOrder(definitions)
        guard !dedupedDefinitions.isEmpty else { return nil }

        let dedupedRelated = dedupePreservingOrder(relatedTerms)
            .filter { normalizedLookupKey($0) != normalizedBase }

        let context = DefinitionContext(
            definitions: dedupedDefinitions,
            relatedTerms: dedupedRelated
        )

        storeCache(
            cacheKey: normalizedBase,
            value: context,
            in: &definitionContextCache,
            order: &definitionContextCacheOrder,
            limit: CacheLimits.definitionContexts
        )
        return context
    }

    private func definitionContextClassicOnly(for normalizedBase: String) -> DefinitionContext? {
        if wordNetClassicIndex == nil { wordNetClassicIndex = loadWordNetClassicIndex() }

        var definitions: [String] = []
        var relatedTerms: [String] = []

        if let index = wordNetClassicIndex,
           let classicDefinitions = index.definitionsByHeadword[normalizedBase],
           !classicDefinitions.isEmpty {
            definitions.append(contentsOf: classicDefinitions.prefix(4))
            relatedTerms.append(contentsOf: index.synonymsByHeadword[normalizedBase] ?? [])
        }

        let dedupedDefinitions = dedupePreservingOrder(definitions)
        guard !dedupedDefinitions.isEmpty else { return nil }

        let dedupedRelated = dedupePreservingOrder(relatedTerms)
            .filter { normalizedLookupKey($0) != normalizedBase }

        return DefinitionContext(
            definitions: dedupedDefinitions,
            relatedTerms: dedupedRelated
        )
    }

    private func derivationalBaseCandidates(for term: String) -> [DerivationalCandidate] {
        var candidates: [DerivationalCandidate] = []

        if term.hasSuffix("iness"), term.count > 5 {
            let stem = String(term.dropLast(5))
            candidates.append(.init(base: stem + "y", kind: .nounNess))
        }

        if term.hasSuffix("ness"), term.count > 4 {
            let stem = String(term.dropLast(4))
            candidates.append(.init(base: stem, kind: .nounNess))
            if stem.hasSuffix("i"), stem.count > 1 {
                candidates.append(.init(base: String(stem.dropLast()) + "y", kind: .nounNess))
            }
        }

        if term.hasSuffix("ish"), term.count > 4 {
            candidates.append(.init(base: String(term.dropLast(3)), kind: .adjectiveIsh))
        }

        if term.hasSuffix("ful"), term.count > 4 {
            candidates.append(.init(base: String(term.dropLast(3)), kind: .adjectiveFul))
        }

        if term.hasSuffix("less"), term.count > 5 {
            candidates.append(.init(base: String(term.dropLast(4)), kind: .adjectiveLess))
        }

        if term.hasSuffix("like"), term.count > 5 {
            candidates.append(.init(base: String(term.dropLast(4)), kind: .adjectiveLike))
        }

        if term.hasSuffix("ily"), term.count > 4 {
            let stem = String(term.dropLast(3))
            candidates.append(.init(base: stem + "y", kind: .adverbLy))
            candidates.append(.init(base: stem, kind: .adverbLy))
        } else if term.hasSuffix("ly"), term.count > 3 {
            candidates.append(.init(base: String(term.dropLast(2)), kind: .adverbLy))
        }

        if term.hasSuffix("iest"), term.count > 5 {
            candidates.append(.init(base: String(term.dropLast(4)) + "y", kind: .superlativeEst))
        } else if term.hasSuffix("est"), term.count > 4 {
            candidates.append(.init(base: String(term.dropLast(3)), kind: .superlativeEst))
        }

        if term.hasSuffix("ier"), term.count > 4 {
            candidates.append(.init(base: String(term.dropLast(3)) + "y", kind: .comparativeEr))
        } else if term.hasSuffix("er"), term.count > 3 {
            candidates.append(.init(base: String(term.dropLast(2)), kind: .comparativeEr))
        }

        if term.hasSuffix("y"), term.count > 3 {
            let stem = String(term.dropLast())
            candidates.append(.init(base: stem, kind: .adjectiveY))
            if let undoubled = undoubledTerminalConsonant(in: stem) {
                candidates.append(.init(base: undoubled, kind: .adjectiveY))
            }
        }

        return dedupeDerivationalCandidates(candidates)
    }

    private func dedupeDerivationalCandidates(_ candidates: [DerivationalCandidate]) -> [DerivationalCandidate] {
        var seen = Set<String>()
        var out: [DerivationalCandidate] = []
        for candidate in candidates {
            let base = normalizedLookupKey(candidate.base)
            let key = "\(candidate.kind.label)|\(base)"
            guard !base.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(.init(base: base, kind: candidate.kind))
        }
        return out
    }

    private func undoubledTerminalConsonant(in stem: String) -> String? {
        guard stem.count >= 2 else { return nil }
        let chars = Array(stem)
        let last = chars[chars.count - 1]
        let penultimate = chars[chars.count - 2]
        let vowels = Set(["a", "e", "i", "o", "u"])
        guard last == penultimate,
              !vowels.contains(String(last).lowercased()) else {
            return nil
        }
        return String(chars.dropLast())
    }

    private func inflectionVariants(for term: String) -> [String] {
        var variants = Set<String>()

        if term.hasSuffix("ies"), term.count > 3 {
            variants.insert(String(term.dropLast(3)) + "y")
        }
        if term.hasSuffix("es"), term.count > 2 {
            variants.insert(String(term.dropLast(2)))
        }
        if term.hasSuffix("s"), term.count > 1 {
            variants.insert(String(term.dropLast(1)))
        }
        if term.hasSuffix("ing"), term.count > 4 {
            let stem = String(term.dropLast(3))
            variants.insert(stem)
            variants.insert(stem + "e")
        }
        if term.hasSuffix("ed"), term.count > 3 {
            let stem = String(term.dropLast(2))
            variants.insert(stem)
            variants.insert(stem + "e")
        }
        if term.hasSuffix("er"), term.count > 3 {
            variants.insert(String(term.dropLast(2)))
        }
        if term.hasSuffix("est"), term.count > 4 {
            variants.insert(String(term.dropLast(3)))
        }
        if term.hasSuffix("ly"), term.count > 3 {
            variants.insert(String(term.dropLast(2)))
        }

        return Array(variants)
    }

    private func regionalSpellingBaseCandidates(for term: String) -> [String] {
        var candidates: [String] = []

        let specialCases: [String: [String]] = [
            "licence": ["license"],
            "licences": ["licenses"],
            "practise": ["practice"],
            "practised": ["practiced"],
            "practising": ["practicing"],
            "programme": ["program"],
            "programmes": ["programs"],
            "cheque": ["check"],
            "cheques": ["checks"],
            "grey": ["gray"],
            "greyish": ["grayish"],
            "mould": ["mold"],
            "moulding": ["molding"],
            "pyjamas": ["pajamas"],
            "aluminium": ["aluminum"],
            "tyre": ["tire"],
            "tyres": ["tires"],
            "kerb": ["curb"],
            "kerbs": ["curbs"],
            "jewellery": ["jewelry"],
            "sulphur": ["sulfur"],
            "traveller": ["traveler"],
            "travellers": ["travelers"],
            "cosy": ["cozy"],
            "cosier": ["cozier"],
            "cosiest": ["coziest"]
        ]
        if let mapped = specialCases[term] {
            candidates.append(contentsOf: mapped)
        }

        let replacements: [(String, String)] = [
            ("isation", "ization"),
            ("ising", "izing"),
            ("ised", "ized"),
            ("ises", "izes"),
            ("ise", "ize"),
            ("ysation", "yzation"),
            ("ysing", "yzing"),
            ("ysed", "yzed"),
            ("yses", "yzes"),
            ("yse", "yze"),
            ("our", "or"),
            ("re", "er"),
            ("ence", "ense"),
            ("lled", "led"),
            ("lling", "ling"),
            ("ller", "ler"),
            ("lled", "led"),
            ("logue", "log")
        ]

        for (source, target) in replacements {
            guard term.contains(source) else { continue }
            if source == "re" {
                guard ["centre", "theatre", "metre", "litre", "fibre", "sabre"].contains(term) else { continue }
                candidates.append(String(term.dropLast(2)) + target)
                continue
            }
            if source == "ence" {
                guard ["defence", "offence", "pretence", "licence"].contains(term) else { continue }
            }
            candidates.append(term.replacingOccurrences(of: source, with: target))
        }

        return dedupePreservingOrder(candidates)
    }

    private func regionalSpellingLabel(for regions: [String]) -> String {
        if regions.contains("British"), regions.count > 1 {
            return "British/Commonwealth"
        }
        if regions.contains("British") {
            return "British"
        }
        return "Commonwealth"
    }

    private func rankReferenceEntries(_ entries: [ReferenceEntry], query: String, candidates: [String]) -> [ReferenceEntry] {
        let candidateOrder = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { (normalizedLookupKey($0.element), $0.offset) })

        return entries.sorted { lhs, rhs in
            let leftScore = referenceEntryScore(lhs, query: query, candidateOrder: candidateOrder)
            let rightScore = referenceEntryScore(rhs, query: query, candidateOrder: candidateOrder)
            if leftScore == rightScore {
                return lhs.title < rhs.title
            }
            return leftScore > rightScore
        }
    }

    private func rankReferenceRecoveryEntries(_ entries: [ReferenceEntry], query: String, candidates: [String]) -> [ReferenceEntry] {
        let candidateOrder = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { (normalizedLookupKey($0.element), $0.offset) })

        return entries.sorted { lhs, rhs in
            let leftScore = referenceRecoveryScore(lhs, query: query, candidateOrder: candidateOrder)
            let rightScore = referenceRecoveryScore(rhs, query: query, candidateOrder: candidateOrder)
            if leftScore == rightScore {
                return lhs.title < rhs.title
            }
            return leftScore > rightScore
        }
    }

    private func referenceEntryScore(_ entry: ReferenceEntry, query: String, candidateOrder: [String: Int]) -> Int {
        let titleKey = normalizedLookupKey(entry.title)
        let aliasKeys = entry.aliases.map(normalizedLookupKey)
        let synonymKeys = entry.synonyms.map(normalizedLookupKey)
        let seeAlsoKeys = entry.seeAlso.map(normalizedLookupKey)

        var score = 0
        if titleKey == query { score += 120 }
        if aliasKeys.contains(query) { score += 100 }
        if synonymKeys.contains(query) { score += 60 }
        if seeAlsoKeys.contains(query) { score += 20 }
        if let order = candidateOrder[titleKey] {
            score += max(0, 40 - order)
        }
        if entry.isVariant { score += 6 }
        return score
    }

    private func referenceRecoveryScore(_ entry: ReferenceEntry, query: String, candidateOrder: [String: Int]) -> Int {
        let titleKey = normalizedLookupKey(entry.title)
        let aliasKeys = entry.aliases.map(normalizedLookupKey)

        var score = 0
        if titleKey == query { score += 120 }
        if aliasKeys.contains(query) { score += 100 }
        if let order = candidateOrder[titleKey] {
            score += max(0, 40 - order)
        }
        if entry.isVariant { score += 6 }
        return score
    }

    private func referenceRecoveryMatchedCandidate(
        for entry: ReferenceEntry,
        candidateKeys: [String],
        fallback: String
    ) -> String {
        let titleKey = normalizedLookupKey(entry.title)
        let aliasKeys = Set(entry.aliases.map(normalizedLookupKey))
        return candidateKeys.first(where: { candidate in
            candidate == titleKey || aliasKeys.contains(candidate)
        }) ?? fallback
    }

    private func referenceDirectMatchChips(
        for entry: ReferenceEntry,
        query: String,
        candidates: [String],
        standardCandidates: [String]
    ) -> [String] {
        let titleKey = normalizedLookupKey(entry.title)
        let aliasKeys = entry.aliases.map(normalizedLookupKey)
        let synonymKeys = entry.synonyms.map(normalizedLookupKey)

        if titleKey == query {
            return ["direct note hit", lookupMatchChip(query: query, matched: titleKey, standardCandidates: standardCandidates)]
        }

        if aliasKeys.contains(query) {
            return ["direct note hit", "variant hit"]
        }

        if synonymKeys.contains(query) {
            return ["direct note hit", "synonym-led hit"]
        }

        if let matchedCandidate = candidates.first(where: { candidate in
            candidate == titleKey || aliasKeys.contains(candidate)
        }) {
            return ["direct note hit", lookupMatchChip(query: query, matched: matchedCandidate, standardCandidates: standardCandidates)]
        }

        return ["direct note hit"]
    }

    private func referenceCompanionMatchChips(
        for entry: ReferenceEntry,
        counterpartTerms: Set<String>
    ) -> [String] {
        let titleKey = normalizedLookupKey(entry.title)
        if counterpartTerms.contains(titleKey) {
            return ["companion result", "dialect companion"]
        }
        return ["companion result", "related companion"]
    }

    private func referencePhraseCoreMatchChips(
        for entry: ReferenceEntry,
        phraseCoreKey: String
    ) -> [String] {
        let entryPhraseCoreKeys = Set(entry.lookupKeys.map(phraseCoreLookupKey(for:)))
        guard entryPhraseCoreKeys.contains(phraseCoreKey) else {
            return ["phrase-core hit"]
        }
        return ["phrase-core hit", "phrase recall"]
    }

    private func topicMeshTerms(
        for entry: ReferenceEntry,
        among entries: [ReferenceEntry],
        semanticTopicChipsByEntryKey: [String: Set<String>],
        excluding excludedKeys: Set<String>
    ) -> [String] {
        let sourceTopics = semanticTopicChipsByEntryKey[referenceEntryCacheKey(entry)] ?? []
        guard !sourceTopics.isEmpty else { return [] }

        struct ScoredTopic {
            let term: String
            let score: Int
        }

        let scored = entries.compactMap { candidate -> ScoredTopic? in
            let candidateKey = normalizedLookupKey(candidate.title)
            guard candidateKey != normalizedLookupKey(entry.title) else { return nil }
            guard !excludedKeys.contains(candidateKey) else { return nil }

            let candidateTopics = semanticTopicChipsByEntryKey[referenceEntryCacheKey(candidate)] ?? []
            let sharedTopics = sourceTopics.intersection(candidateTopics)
            guard !sharedTopics.isEmpty else { return nil }

            var score = sharedTopics.count * 100
            if !candidate.isVariant { score += 8 }
            if normalizedLookupKey(candidate.sourceTitle) != normalizedLookupKey(entry.sourceTitle) { score += 6 }
            if candidate.chips.contains(where: { sourceTopics.contains(normalizedLookupKey($0)) }) { score += 4 }
            return ScoredTopic(term: candidate.title, score: score)
        }

        return dedupePreservingOrder(
            scored
                .sorted {
                    if $0.score == $1.score { return $0.term < $1.term }
                    return $0.score > $1.score
                }
                .prefix(5)
                .map(\.term)
        )
    }

    private func referenceEntryCacheKey(_ entry: ReferenceEntry) -> String {
        "\(normalizedLookupKey(entry.title))::\(normalizedLookupKey(entry.sourceTitle))"
    }

    private func sanitizedReferenceNoteSummary(
        _ summary: String,
        sourceTitle: String,
        knownSourceTitles: Set<String>
    ) -> String {
        var cleaned = summary

        let attributionFragments = [
            "Adapted from \(sourceTitle).",
            "Adapted from \(sourceTitle)",
            "adapted from \(sourceTitle).",
            "adapted from \(sourceTitle)"
        ]
        for fragment in attributionFragments where !sourceTitle.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: fragment, with: " ")
        }

        for title in knownSourceTitles where !title.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: title, with: " ")
        }

        cleaned = cleaned.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+([,.;:])"#,
            with: "$1",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\.\s*\."#,
            with: ".",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadSearchLexicon() -> SearchLexicon {
        if let archive: SearchLexiconArchive = loadBundledArchive(fileName: "SearchLexicon.mgrt") {
            let australianHeadwords = Set(
                australianGlossary.keys
                    .lazy
                    .map(normalizedLookupKey)
                    .filter { !$0.isEmpty }
            )
            var headwords = Set(archive.sortedHeadwords)
            headwords.formUnion(australianHeadwords)
            let sortedHeadwords = headwords.sorted()

            return SearchLexicon(
                headwords: headwords,
                sortedHeadwords: sortedHeadwords
            )
        }

        if wordNetIndex == nil { wordNetIndex = loadWordNetIndex() }
        if wordNetClassicIndex == nil { wordNetClassicIndex = loadWordNetClassicIndex() }
        if aussieDictionaryIndex == nil { aussieDictionaryIndex = loadAussieDictionaryIndex() }
        if regionalEnglishIndex == nil { regionalEnglishIndex = loadRegionalEnglishIndex() }
        if referenceNotesIndex == nil { referenceNotesIndex = loadReferenceNotesIndex() }

        var headwords = Set<String>()
        headwords.formUnion(wordNetIndex?.sortedHeadwords ?? [])
        headwords.formUnion(wordNetClassicIndex?.sortedHeadwords ?? [])
        headwords.formUnion(aussieDictionaryIndex?.sortedHeadwords ?? [])
        headwords.formUnion(regionalEnglishIndex?.sortedHeadwords ?? [])
        headwords.formUnion(referenceNotesIndex?.sortedHeadwords ?? [])
        if let referenceLookupKeys = referenceNotesIndex?.entriesByLookupKey.keys {
            headwords.formUnion(referenceLookupKeys)
        }
        headwords.formUnion(australianGlossary.keys.map(normalizedLookupKey))

        let sortedHeadwords = headwords.sorted()
        return SearchLexicon(
            headwords: headwords,
            sortedHeadwords: sortedHeadwords
        )
    }

    private func loadFastLookupIndex() -> FastLookupIndex {
        if let archive: FastLookupArchive = loadBundledArchive(fileName: "FastLookup.mgrt") {
            return FastLookupIndex(
                modernEntriesByHeadword: archive.modernEntriesByHeadword,
                classicEntriesByHeadword: archive.classicEntriesByHeadword
            )
        }

        return FastLookupIndex(modernEntriesByHeadword: [:], classicEntriesByHeadword: [:])
    }

    private func openFastLookupStore() -> FastLookupStore? {
        let url = bundledResourceURL(fileName: "FastLookup.sqlite3") ?? offlineArchiveFallbackURL(fileName: "FastLookup.sqlite3")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return FastLookupStore(url: url)
    }

    private func fastLookupContains(headword: String) -> Bool {
        if fastLookupStore == nil && fastLookupIndex == nil {
            loadFastLookupArtifacts()
        }
        if let fastLookupStore {
            return fastLookupStore.contains(headword: headword)
        }
        return fastLookupIndex?.contains(headword: headword) ?? false
    }

    private func fastLookupCards(for headword: String, displayTerm: String) -> [SearchCard] {
        if fastLookupStore == nil && fastLookupIndex == nil {
            loadFastLookupArtifacts()
        }
        if let fastLookupStore, let row = fastLookupStore.row(for: headword) {
            return fastLookupCards(from: row, headword: headword, displayTerm: displayTerm)
        }
        return fastLookupIndex?.defineCards(for: headword, displayTerm: displayTerm) ?? []
    }

    private func fastLookupCards(
        from row: FastLookupDatabaseRow,
        headword: String,
        displayTerm: String
    ) -> [SearchCard] {
        let normalizedDisplayTerm = Self.normalizedLookupKeyStatic(displayTerm)
        let title = headword == normalizedDisplayTerm
            ? Self.displayTitleStatic(displayTerm)
            : Self.displayTitleStatic(headword)

        return [
            SearchCard(
                title: title,
                source: "WordNet 2025 (Open English WordNet)",
                summary: Self.fastLookupSummaryStatic(
                    definitions: row.definitions,
                    relatedTerms: row.relatedTerms,
                    relatedLimit: 6
                ),
                chips: [
                    Self.fastLookupPOSBreakdownStatic(row.posCounts, fallback: "core english"),
                    "synsets: \(row.synsetCount)",
                    "lemmas: \(max(1, row.lemmaCount))",
                    "wordnet",
                    "oewn",
                    "exact hit"
                ],
                relatedTerms: row.relatedTerms
            )
        ]
    }

    private func loadDeepLookupLexicon() -> SearchLexicon {
        if let archive: SearchLexiconArchive = loadBundledArchive(fileName: "DeepLookupLexicon.mgrt") {
            let headwords = Set(archive.sortedHeadwords)
            return SearchLexicon(
                headwords: headwords,
                sortedHeadwords: archive.sortedHeadwords
            )
        }

        if referenceNotesIndex == nil { referenceNotesIndex = loadReferenceNotesIndex() }
        if regionalEnglishIndex == nil { regionalEnglishIndex = loadRegionalEnglishIndex() }

        var headwords = Set<String>()
        headwords.formUnion(referenceNotesIndex?.sortedHeadwords ?? [])
        if let referenceLookupKeys = referenceNotesIndex?.entriesByLookupKey.keys {
            headwords.formUnion(referenceLookupKeys)
        }
        headwords.formUnion(regionalEnglishIndex?.sortedHeadwords ?? [])

        let sortedHeadwords = headwords.sorted()
        return SearchLexicon(
            headwords: headwords,
            sortedHeadwords: sortedHeadwords
        )
    }

    private func deletionSignatures(for term: String) -> [String] {
        guard term.count >= 2 else { return [] }
        let characters = Array(term)
        var signatures = Set<String>()
        for index in characters.indices {
            var copy = characters
            copy.remove(at: index)
            let value = String(copy).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                signatures.insert(value)
            }
        }
        return Array(signatures)
    }

    private func singleCharacterDuplicationVariants(for term: String) -> [String] {
        guard !term.isEmpty else { return [] }
        let characters = Array(term)
        var variants = Set<String>()
        for index in characters.indices {
            var copy = characters
            copy.insert(characters[index], at: index)
            let value = String(copy).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                variants.insert(value)
            }
        }
        return Array(variants)
    }

    private func collapsedRepeatVariants(for term: String) -> [String] {
        guard term.count >= 3 else { return [] }
        let characters = Array(term)
        var variants = Set<String>()

        var singleRunCollapsed: [Character] = []
        var doubleRunCollapsed: [Character] = []
        var index = 0
        while index < characters.count {
            let current = characters[index]
            var runLength = 1
            var cursor = index + 1
            while cursor < characters.count, characters[cursor] == current {
                runLength += 1
                cursor += 1
            }

            singleRunCollapsed.append(current)
            doubleRunCollapsed.append(current)
            if runLength > 1 {
                doubleRunCollapsed.append(current)
            }
            index = cursor
        }

        let single = String(singleRunCollapsed).trimmingCharacters(in: .whitespacesAndNewlines)
        if !single.isEmpty, single != term {
            variants.insert(single)
        }

        let double = String(doubleRunCollapsed).trimmingCharacters(in: .whitespacesAndNewlines)
        if !double.isEmpty, double != term {
            variants.insert(double)
        }

        return Array(variants)
    }

    private func adjacentTranspositions(for term: String) -> [String] {
        guard term.count >= 2 else { return [] }
        var characters = Array(term)
        var transpositions = Set<String>()
        for index in 0..<(characters.count - 1) {
            characters.swapAt(index, index + 1)
            transpositions.insert(String(characters))
            characters.swapAt(index, index + 1)
        }
        return Array(transpositions)
    }

    private func typoEditLimit(for term: String) -> Int {
        if term.count <= 4 { return 1 }
        if term.count <= 8 { return 2 }
        return 3
    }

    private func sharedPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private func compactLookupKey(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private func semanticTopicChips(from chips: [String]) -> Set<String> {
        Set(
            chips
                .map(normalizedLookupKey)
                .filter {
                    !$0.isEmpty &&
                    !ignoredTopicChips.contains($0) &&
                    !$0.hasPrefix("base:")
                }
        )
    }

    // Rank synonyms by cross-source presence (in both OO+Moby = highest priority),
    // single-word preference, and lexical proximity to the query.
    private func rankSynonyms(_ synonyms: [String], against query: String, ooSet: Set<String>, mobySet: Set<String>) -> [String] {
        struct Scored { let term: String; let score: Int }
        let queryPrefix4 = String(query.prefix(4))
        let scored: [Scored] = synonyms.map { term in
            var score = 0
            let norm = normalizedLookupKey(term)
            let inOO = ooSet.contains(norm)
            let inMoby = mobySet.contains(norm)
            if inOO && inMoby { score += 4 }        // cross-source consensus
            else if inOO || inMoby { score += 2 }   // single-source
            if !term.contains(" ") && !term.contains("-") { score += 1 }  // single-word
            if !queryPrefix4.isEmpty && norm.hasPrefix(queryPrefix4) { score += 2 }  // lexical proximity
            if term.count < 10 { score += 1 }       // prefer shorter forms
            return Scored(term: term, score: score)
        }
        return scored.sorted { $0.score > $1.score }.map { $0.term }
    }

    private func parseThesaurusSenseLine(_ line: String) -> [String] {
        line
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard !token.isEmpty else { return false }
                // Filter POS/metadata labels like "(adj.)"
                if token.hasPrefix("("), token.hasSuffix(")") { return false }
                return true
            }
    }

    private func dedupePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalizedLookupKey(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }

    private func dedupeReferenceEntries(_ values: [ReferenceEntry]) -> [ReferenceEntry] {
        var seen = Set<String>()
        var out: [ReferenceEntry] = []
        for value in values {
            let key = normalizedLookupKey(value.title)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    private func dedupeStoredReferenceRows(_ values: [StoredReferenceNoteRow]) -> [StoredReferenceNoteRow] {
        var seen = Set<String>()
        var out: [StoredReferenceNoteRow] = []
        for value in values {
            let key = referenceEntryCacheKey(value.entry)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    private func storedReferenceRows(
        for lookupKeys: [String],
        in store: ReferenceNotesStore
    ) -> [StoredReferenceNoteRow] {
        guard !lookupKeys.isEmpty else { return [] }
        return dedupeStoredReferenceRows(
            lookupKeys.flatMap { store.lookupRows(for: $0) }
        )
    }

    private func boundedLevenshtein(_ a: String, _ b: String, limit: Int) -> Int? {
        if a == b { return 0 }
        if abs(a.count - b.count) > limit { return nil }

        let ac = Array(a)
        let bc = Array(b)
        var prev = Array(0...bc.count)

        for i in 1...ac.count {
            var curr = Array(repeating: 0, count: bc.count + 1)
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...bc.count {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
                rowMin = min(rowMin, curr[j])
            }
            if rowMin > limit { return nil }
            prev = curr
        }
        return prev[bc.count] <= limit ? prev[bc.count] : nil
    }

}

private let australianGlossary: [String: AustralianUsageEntry] = [

    // MARK: Everyday colloquialisms
    "arvo": .init(description: "Afternoon. Common colloquial abbreviation in Australian English.", register: .informal, slangLevel: .common),
    "brekkie": .init(description: "Breakfast.", register: .informal, slangLevel: .common),
    "servo": .init(description: "Service station (petrol station).", register: .informal, slangLevel: .common),
    "bottleo": .init(description: "Liquor store / bottle shop.", register: .informal, slangLevel: .common),
    "esky": .init(description: "Portable cooler box used for drinks or food. A brand name that became a generic Australian term.", register: .neutral, slangLevel: .light),
    "ute": .init(description: "Utility vehicle (pickup-style). Core of Australian tradie and rural culture.", register: .neutral, slangLevel: .light),
    "thongs": .init(description: "Flip-flops / sandals. In Australia 'thongs' unambiguously means footwear, not underwear.", register: .neutral, slangLevel: .light),
    "trackies": .init(description: "Tracksuit pants.", register: .informal, slangLevel: .common),
    "sanger": .init(description: "Sandwich. Also spelt 'sanga'.", register: .informal, slangLevel: .common),
    "maccas": .init(description: "McDonald's (colloquial nickname). The chain itself uses the name in Australian marketing.", register: .informal, slangLevel: .common),
    "bogan": .init(description: "Informal term for an uncultured or working-class person. Can be affectionate among peers; offensive from outsiders.", register: .informal, slangLevel: .coarse),
    "no worries": .init(description: "It's fine / you're welcome / no problem. The quintessential Australian expression of laid-back affirmation.", register: .neutral, slangLevel: .light),
    "fair dinkum": .init(description: "Genuine, authentic, or true. 'Fair dinkum?' can mean 'Is that true?' or 'Are you serious?'", register: .informal, slangLevel: .common),
    "mate": .init(description: "Common informal form of address, used freely between friends and strangers alike.", register: .neutral, slangLevel: .light),
    "uni": .init(description: "University.", register: .neutral, slangLevel: .light),
    "ripper": .init(description: "Excellent; very good. 'You ripper!' is an exclamation of delight.", register: .informal, slangLevel: .common),
    "heaps": .init(description: "A lot / many. 'Heaps good' = very good.", register: .informal, slangLevel: .common),
    "mozzie": .init(description: "Mosquito.", register: .informal, slangLevel: .common),
    "snag": .init(description: "Sausage. Particularly associated with the 'sausage sizzle' outside Bunnings hardware stores.", register: .informal, slangLevel: .common),
    "avo": .init(description: "Avocado. Used widely in casual speech, particularly in the context of smashed avo on toast.", register: .informal, slangLevel: .common),
    "dodgy": .init(description: "Unreliable, suspicious, or of questionable quality. 'That looks dodgy' = that looks shady/untrustworthy.", register: .informal, slangLevel: .common),
    "chockers": .init(description: "Full to capacity; completely packed. Short for 'chock-a-block'.", register: .informal, slangLevel: .common),
    "sook": .init(description: "A timid, oversensitive, or easily upset person; a crybaby.", register: .informal, slangLevel: .common),
    "barbie": .init(description: "Barbecue (grill). Backyard barbecues are central to Australian social life.", register: .informal, slangLevel: .common),
    "tradie": .init(description: "A tradesperson — plumber, electrician, carpenter, bricklayer, etc.", register: .neutral, slangLevel: .light),
    "sunnies": .init(description: "Sunglasses.", register: .informal, slangLevel: .common),
    "tinnie": .init(description: "A can of beer, or a small aluminium dinghy (boat). Context determines which is meant.", register: .informal, slangLevel: .common),
    "bloke": .init(description: "A man; informally used to describe a typical or ordinary man.", register: .informal, slangLevel: .common),
    "stoked": .init(description: "Extremely enthusiastic or excited about something.", register: .informal, slangLevel: .common),
    "reckon": .init(description: "Used to mean 'think', 'believe', or 'suppose'. Very common in casual Australian speech.", register: .informal, slangLevel: .common),
    "sheila": .init(description: "Dated informal term for a woman. Old-fashioned; can be considered offensive in contemporary usage.", register: .informal, slangLevel: .rare),
    "argie-bargie": .init(description: "A heated argument or vigorous dispute.", register: .informal, slangLevel: .common),
    "tall poppy syndrome": .init(description: "The social tendency to cut down those who achieve too much or appear self-important. A powerful cultural force in Australian society.", register: .neutral, slangLevel: .light),
    "she'll be right": .init(description: "Everything will work out fine. Reflects a characteristically Australian optimism (or nonchalance) about problems.", register: .informal, slangLevel: .common),
    "gone walkabout": .init(description: "Originally refers to an Aboriginal tradition of temporary return to a nomadic lifestyle. Now used informally to mean someone has disappeared or wandered off without explanation. Use with cultural sensitivity.", register: .informal, slangLevel: .rare),

    // MARK: Sports
    "footy": .init(description: "Australian Rules Football (AFL) in Victoria, SA, WA and Tasmania. Rugby League (NRL) in Queensland and NSW. Rugby Union in ACT. Which code 'footy' means depends strongly on geography.", register: .neutral, slangLevel: .light),
    "afl": .init(description: "Australian Football League — the national competition for Australian Rules Football (18-a-side, oval field, no offside).", register: .neutral, slangLevel: .light),
    "nrl": .init(description: "National Rugby League — the national competition for rugby league, dominant in Queensland and NSW.", register: .neutral, slangLevel: .light),
    "googly": .init(description: "A cricket delivery that spins the opposite way to a standard leg-break, bowled by a right-arm leg-spin bowler. Notoriously difficult to 'read' from the bowler's hand.", register: .neutral, slangLevel: .light),
    "yorker": .init(description: "A cricket delivery that pitches right at the batsman's feet, typically bowled at high pace. Highly effective at the death overs.", register: .neutral, slangLevel: .light),
    "baggy green": .init(description: "The iconic Australian Test cricket cap. Being awarded the baggy green is considered one of the highest honours in Australian sport.", register: .neutral, slangLevel: .light),

    // MARK: Government and institutions
    "ato": .init(description: "Australian Taxation Office — the federal body administering Australia's tax, superannuation, and excise systems.", register: .neutral, slangLevel: .light),
    "centrelink": .init(description: "Services Australia (colloquially known as Centrelink) — delivers social security payments including JobSeeker, Youth Allowance, aged pension, and family payments.", register: .neutral, slangLevel: .light),
    "medicare": .init(description: "Australia's universal public health insurance scheme, covering GP visits, hospital care, and subsidised medicines via the Pharmaceutical Benefits Scheme (PBS).", register: .neutral, slangLevel: .light),
    "hecs": .init(description: "Higher Education Contribution Scheme — now formally the Higher Education Loan Program (HELP). Government-backed deferred student loan for Australian university tuition fees, repaid through the tax system.", register: .neutral, slangLevel: .light),
    "super": .init(description: "Superannuation — compulsory employer contributions (currently 11.5%) into an employee's retirement savings account. One of Australia's defining financial policy frameworks.", register: .neutral, slangLevel: .light),

    // MARK: Place names and demonyms
    "brissy": .init(description: "Informal name for Brisbane, capital of Queensland.", register: .informal, slangLevel: .common),
    "melbs": .init(description: "Informal name for Melbourne, capital of Victoria.", register: .informal, slangLevel: .common),
    "freo": .init(description: "Informal name for Fremantle, the historic port city near Perth, Western Australia.", register: .informal, slangLevel: .common),
    "tassie": .init(description: "Informal name for Tasmania, Australia's island state. Also used to refer to Tasmanians themselves.", register: .informal, slangLevel: .common),
    "gong": .init(description: "Informal name for Wollongong, a coastal city in NSW south of Sydney.", register: .informal, slangLevel: .common),

    // MARK: Aboriginal and Torres Strait Islander English — handled with cultural respect
    "yarning": .init(description: "Yarning is a culturally safe, conversational form of communication in Aboriginal communities for sharing stories, knowledge, and building relationships. Yarning circles are used in education, health, and community contexts.", register: .neutral, slangLevel: .light),
    "bush tucker": .init(description: "Traditional Aboriginal and Torres Strait Islander food — native plants (wattleseed, quandong, finger lime), animals, and insects from the Australian bush. Central to cultural knowledge and connection to Country.", register: .neutral, slangLevel: .light),
    "mob": .init(description: "In Aboriginal English, 'mob' refers to one's family, community, or people. A deeply significant concept of belonging and cultural identity — not merely a crowd.", register: .neutral, slangLevel: .light),
    "country": .init(description: "'Country' (often capitalised) in Aboriginal culture refers to a person's ancestral homeland — encompassing land, water, sky, spiritual relationships, and custodial obligations. Far more than mere geography.", register: .neutral, slangLevel: .light),
    "sorry business": .init(description: "Aboriginal term for the mourning practices and funeral obligations following a death. Sorry business is a significant cultural and spiritual commitment that may require travel and extended absence from work.", register: .neutral, slangLevel: .light),
    "dreamtime": .init(description: "The Dreaming (or Dreamtime) is the foundational spiritual and cosmological framework of Aboriginal culture — the time when ancestral beings shaped the land, sea, and all life. Treat with deep cultural respect.", register: .neutral, slangLevel: .light),

    // MARK: Food and culture
    "vegemite": .init(description: "A dark, intensely salty yeast-extract spread eaten on toast or in sandwiches. An iconic Australian food product and cultural touchstone.", register: .neutral, slangLevel: .light),
    "pavlova": .init(description: "A meringue dessert topped with whipped cream and fresh fruit. Both Australians and New Zealanders claim its invention; the debate is a national sport in itself.", register: .neutral, slangLevel: .light),
    "lamington": .init(description: "A cube of sponge cake dipped in chocolate icing and coated in desiccated coconut. A classic Australian bake-sale and school-fete staple.", register: .neutral, slangLevel: .light),
    "tim tam": .init(description: "A popular Australian chocolate biscuit by Arnott's — two malt biscuits sandwiching chocolate cream, coated in chocolate. Famous for the 'Tim Tam Slam' (drinking through it like a straw).", register: .neutral, slangLevel: .light),
    "anzac biscuit": .init(description: "A rolled oat biscuit historically sent to ANZAC soldiers. Still baked widely on ANZAC Day (25 April) as a commemorative tradition. Legally, cannot be sold as 'ANZAC' without permission.", register: .neutral, slangLevel: .light),
]

private struct AustralianUsageEntry {
    let description: String
    let register: AustralianRegister
    let slangLevel: AustralianSlangLevel
}

private enum AustralianRegister: String {
    case neutral
    case informal
    case coarse
}

private enum AustralianSlangLevel: String {
    case light
    case common
    case rare
    case coarse
}

private struct FreeDictPair {
    let name: String
    let shortName: String
    let translationsByHeadword: [String: [String]]
}

private struct ZAMafokoEntry: Codable {
    let values: [String: String]
}

private extension String {
    func decodedXMLEntities() -> String {
        self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

// MARK: - WordNet support types

private struct WordNetIndex {
    let synsetsByHeadword: [String: [String]]
    let posByHeadword: [String: String]
    let definitionBySynset: [String: String]
    let headwordsBySynset: [String: [String]]
    let sortedHeadwords: [String]
    /// headword → POS abbreviation → sense count across all LexicalEntries.
    let synsetCountByPOSByHeadword: [String: [String: Int]]
}

private struct WordNetClassicIndex {
    let definitionsByHeadword: [String: [String]]
    let synonymsByHeadword: [String: [String]]
    let sortedHeadwords: [String]
    let senseCountByPOSByHeadword: [String: [String: Int]]
}

private struct AussieDictionaryIndex {
    let headwords: Set<String>
    let sortedHeadwords: [String]
}

private struct RegionalEnglishIndex {
    let regionsByHeadword: [String: [String]]
    let sortedHeadwords: [String]
}

private struct ReferenceNotesIndex {
    let notes: [ReferenceNote]
    let entries: [ReferenceEntry]
    let entriesByLookupKey: [String: [ReferenceEntry]]
    let entriesByPhraseCoreKey: [String: [ReferenceEntry]]
    let sortedHeadwords: [String]
    let topicTermsByEntryKey: [String: [String]]
    let sourceTitles: Set<String>
}

private struct SearchLexicon {
    let headwords: Set<String>
    let sortedHeadwords: [String]
}

private struct WordListArchive: Codable {
    let version: Int
    let headwords: [String]
}

private struct RegionalEnglishArchive: Codable {
    let version: Int
    let regionsByHeadword: [String: [String]]
    let sortedHeadwords: [String]
    let regionCounts: [String: Int]
}

private struct ThesaurusArchive: Codable {
    let version: Int
    let entries: [String: [String]]
}

private struct ZAMafokoArchive: Codable {
    let version: Int
    let entries: [ZAMafokoEntry]
}

private struct SearchLexiconArchive: Codable {
    let version: Int
    let sortedHeadwords: [String]
}

private struct FastLookupArchive: Codable {
    let version: Int
    let modernEntriesByHeadword: [String: FastLookupEntry]
    let classicEntriesByHeadword: [String: FastLookupEntry]
}

private struct WordNetClassicArchive: Codable {
    let version: Int
    let definitionsByHeadword: [String: [String]]
    let synonymsByHeadword: [String: [String]]
    let sortedHeadwords: [String]
    let senseCountByPOSByHeadword: [String: [String: Int]]
}

private struct WordNet2025Archive: Codable {
    let version: Int
    let synsetsByHeadword: [String: [String]]
    let posByHeadword: [String: String]
    let definitionBySynset: [String: String]
    let headwordsBySynset: [String: [String]]
    let sortedHeadwords: [String]
    let synsetCountByPOSByHeadword: [String: [String: Int]]
}

private struct FastLookupIndex {
    let modernEntriesByHeadword: [String: FastLookupEntry]
    let classicEntriesByHeadword: [String: FastLookupEntry]

    func contains(headword: String) -> Bool {
        modernEntriesByHeadword[headword] != nil || classicEntriesByHeadword[headword] != nil
    }

    func defineCards(for headword: String, displayTerm: String) -> [DictionaryRepository.SearchCard] {
        var cards: [DictionaryRepository.SearchCard] = []
        let title = headword == DictionaryRepository.normalizedLookupKeyStatic(displayTerm)
            ? DictionaryRepository.displayTitleStatic(displayTerm)
            : DictionaryRepository.displayTitleStatic(headword)

        if let modern = modernEntriesByHeadword[headword] {
            cards.append(
                DictionaryRepository.SearchCard(
                    title: title,
                    source: "WordNet 2025 (Open English WordNet)",
                    summary: DictionaryRepository.fastLookupSummaryStatic(
                        definitions: modern.definitions,
                        relatedTerms: modern.relatedTerms,
                        relatedLimit: 8
                    ),
                    chips: [
                        DictionaryRepository.fastLookupPOSBreakdownStatic(modern.posCounts, fallback: "core english"),
                        "synsets: \(modern.synsetCount ?? modern.definitions.count)",
                        "lemmas: \(modern.lemmaCount ?? max(1, modern.relatedTerms.count + 1))",
                        "wordnet",
                        "oewn",
                        "exact hit"
                    ],
                    relatedTerms: modern.relatedTerms
                )
            )
        }

        if let classic = classicEntriesByHeadword[headword] {
            cards.append(
                DictionaryRepository.SearchCard(
                    title: title,
                    source: "WordNet 3.x (Princeton dict)",
                    summary: DictionaryRepository.fastLookupSummaryStatic(
                        definitions: classic.definitions,
                        relatedTerms: classic.relatedTerms,
                        relatedLimit: 10
                    ),
                    chips: [
                        DictionaryRepository.fastLookupPOSBreakdownStatic(classic.posCounts, fallback: "classic core"),
                        "classic",
                        "wordnet",
                        "princeton",
                        "exact hit"
                    ],
                    relatedTerms: classic.relatedTerms
                )
            )
        }

        return cards
    }
}

private struct FastLookupEntry: Codable {
    let definitions: [String]
    let relatedTerms: [String]
    let posCounts: [String: Int]
    let synsetCount: Int?
    let lemmaCount: Int?
}

private struct FastLookupDatabaseRow {
    let definitions: [String]
    let relatedTerms: [String]
    let posCounts: [String: Int]
    let synsetCount: Int
    let lemmaCount: Int
}

private struct StoredReferenceNoteRow {
    let entry: ReferenceEntry
    let topicTerms: [String]
}

private final class FastLookupStore {
    private let database: OpaquePointer
    private let existsStatement: OpaquePointer
    private let rowStatement: OpaquePointer

    init?(url: URL) {
        guard let database = Self.openDatabase(url: url) else {
            return nil
        }

        guard let existsStatement = Self.prepareStatement(
            """
            SELECT 1
            FROM define_entries
            WHERE headword = ?
            LIMIT 1;
            """,
            in: database
        ) else {
            sqlite3_close(database)
            return nil
        }

        guard let rowStatement = Self.prepareStatement(
            """
            SELECT definitions_blob, related_terms_blob, pos_counts_blob, synset_count, lemma_count
            FROM define_entries
            WHERE headword = ?
            LIMIT 1;
            """,
            in: database
        ) else {
            sqlite3_finalize(existsStatement)
            sqlite3_close(database)
            return nil
        }

        self.database = database
        self.existsStatement = existsStatement
        self.rowStatement = rowStatement
    }

    deinit {
        sqlite3_finalize(existsStatement)
        sqlite3_finalize(rowStatement)
        sqlite3_close(database)
    }

    func contains(headword: String) -> Bool {
        bind(headword, to: existsStatement)
        defer { reset(existsStatement) }
        return sqlite3_step(existsStatement) == SQLITE_ROW
    }

    func row(for headword: String) -> FastLookupDatabaseRow? {
        bind(headword, to: rowStatement)
        defer { reset(rowStatement) }
        guard sqlite3_step(rowStatement) == SQLITE_ROW else {
            return nil
        }

        let definitions = sqliteColumnString(rowStatement, index: 0)
            .split(separator: fastLookupBlobSeparator, omittingEmptySubsequences: true)
            .map(String.init)
        let relatedTerms = sqliteColumnString(rowStatement, index: 1)
            .split(separator: fastLookupBlobSeparator, omittingEmptySubsequences: true)
            .map(String.init)
        let posCounts = parseFastLookupPOSBlob(sqliteColumnString(rowStatement, index: 2))
        let synsetCount = Int(sqlite3_column_int(rowStatement, 3))
        let lemmaCount = Int(sqlite3_column_int(rowStatement, 4))

        return FastLookupDatabaseRow(
            definitions: definitions,
            relatedTerms: relatedTerms,
            posCounts: posCounts,
            synsetCount: synsetCount,
            lemmaCount: lemmaCount
        )
    }

    private static func openDatabase(url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        let immutableURI = url.absoluteString + "?immutable=1&mode=ro"

        if sqlite3_open_v2(immutableURI, &database, flags, nil) != SQLITE_OK {
            if let database {
                sqlite3_close(database)
            }
            database = nil

            if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
                if let database {
                    sqlite3_close(database)
                }
                return nil
            }
        }

        sqlite3_exec(database, "PRAGMA query_only = ON;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA mmap_size = 268435456;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA cache_size = -8192;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        return database
    }

    private static func prepareStatement(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }

    private func bind(_ headword: String, to statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, headword, -1, sqliteTransient)
    }

    private func reset(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }
}

private final class ReferenceNotesStore {
    private let database: OpaquePointer
    private let lookupStatement: OpaquePointer
    private let phraseCoreStatement: OpaquePointer
    private let lookupExistsStatement: OpaquePointer
    private let phraseCoreExistsStatement: OpaquePointer
    private let decoder = JSONDecoder()
    static let rowCacheLimit = 512
    private var rowCache = BoundedLookupCache<String, StoredReferenceNoteRow>(limit: rowCacheLimit)
    var cachedRowCount: Int { rowCache.count }

    let entryCount: Int
    let sourceTitles: Set<String>

    init?(url: URL) {
        guard let database = Self.openDatabase(url: url) else {
            return nil
        }

        guard let lookupStatement = Self.prepareStatement(
            """
            SELECT entries.entry_id, entries.entry_json, entries.topic_terms_json
            FROM lookup_map
            JOIN entries ON entries.entry_id = lookup_map.entry_id
            WHERE lookup_map.lookup_key = ?;
            """,
            in: database
        ) else {
            sqlite3_close(database)
            return nil
        }

        guard let phraseCoreStatement = Self.prepareStatement(
            """
            SELECT entries.entry_id, entries.entry_json, entries.topic_terms_json
            FROM phrase_core_map
            JOIN entries ON entries.entry_id = phrase_core_map.entry_id
            WHERE phrase_core_map.phrase_core_key = ?;
            """,
            in: database
        ) else {
            sqlite3_finalize(lookupStatement)
            sqlite3_close(database)
            return nil
        }

        guard let lookupExistsStatement = Self.prepareStatement(
            """
            SELECT 1
            FROM lookup_map
            WHERE lookup_key = ?
            LIMIT 1;
            """,
            in: database
        ) else {
            sqlite3_finalize(phraseCoreStatement)
            sqlite3_finalize(lookupStatement)
            sqlite3_close(database)
            return nil
        }

        guard let phraseCoreExistsStatement = Self.prepareStatement(
            """
            SELECT 1
            FROM phrase_core_map
            WHERE phrase_core_key = ?
            LIMIT 1;
            """,
            in: database
        ) else {
            sqlite3_finalize(lookupExistsStatement)
            sqlite3_finalize(phraseCoreStatement)
            sqlite3_finalize(lookupStatement)
            sqlite3_close(database)
            return nil
        }

        self.database = database
        self.lookupStatement = lookupStatement
        self.phraseCoreStatement = phraseCoreStatement
        self.lookupExistsStatement = lookupExistsStatement
        self.phraseCoreExistsStatement = phraseCoreExistsStatement
        self.entryCount = Self.loadEntryCount(from: database)
        self.sourceTitles = Self.loadSourceTitles(from: database)
    }

    deinit {
        sqlite3_finalize(lookupStatement)
        sqlite3_finalize(phraseCoreStatement)
        sqlite3_finalize(lookupExistsStatement)
        sqlite3_finalize(phraseCoreExistsStatement)
        sqlite3_close(database)
    }

    func lookupRows(for key: String) -> [StoredReferenceNoteRow] {
        rows(for: key, statement: lookupStatement)
    }

    func phraseCoreRows(for key: String) -> [StoredReferenceNoteRow] {
        rows(for: key, statement: phraseCoreStatement)
    }

    func hasLookupKey(_ key: String) -> Bool {
        bind(key, to: lookupExistsStatement)
        defer { reset(lookupExistsStatement) }
        return sqlite3_step(lookupExistsStatement) == SQLITE_ROW
    }

    func hasPhraseCoreKey(_ key: String) -> Bool {
        bind(key, to: phraseCoreExistsStatement)
        defer { reset(phraseCoreExistsStatement) }
        return sqlite3_step(phraseCoreExistsStatement) == SQLITE_ROW
    }

    private func rows(for key: String, statement: OpaquePointer) -> [StoredReferenceNoteRow] {
        bind(key, to: statement)
        defer { reset(statement) }

        var rows: [StoredReferenceNoteRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let entryID = sqliteColumnString(statement, index: 0)
            if let cached = rowCache[entryID] {
                rows.append(cached)
                continue
            }

            let entryData = Data(sqliteColumnString(statement, index: 1).utf8)
            let topicData = Data(sqliteColumnString(statement, index: 2).utf8)
            guard !entryData.isEmpty,
                  !topicData.isEmpty,
                  let entry = try? decoder.decode(ReferenceEntry.self, from: entryData),
                  let topicTerms = try? decoder.decode([String].self, from: topicData) else {
                continue
            }

            let row = StoredReferenceNoteRow(entry: entry, topicTerms: topicTerms)
            rowCache[entryID] = row
            rows.append(row)
        }
        return rows
    }

    private static func loadEntryCount(from database: OpaquePointer) -> Int {
        guard let statement = prepareStatement(
            """
            SELECT COUNT(*)
            FROM entries;
            """,
            in: database
        ) else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func loadSourceTitles(from database: OpaquePointer) -> Set<String> {
        guard let statement = prepareStatement(
            """
            SELECT value
            FROM metadata
            WHERE key = 'source_titles_json'
            LIMIT 1;
            """,
            in: database
        ) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else {
            return []
        }
        let payload = Data(String(cString: cString).utf8)
        let titles = (try? JSONDecoder().decode([String].self, from: payload)) ?? []
        return Set(titles)
    }

    private static func openDatabase(url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        let immutableURI = url.absoluteString + "?immutable=1&mode=ro"

        if sqlite3_open_v2(immutableURI, &database, flags, nil) != SQLITE_OK {
            if let database {
                sqlite3_close(database)
            }
            database = nil

            if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
                if let database {
                    sqlite3_close(database)
                }
                return nil
            }
        }

        sqlite3_exec(database, "PRAGMA query_only = ON;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA mmap_size = 134217728;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA cache_size = -4096;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        return database
    }

    private static func prepareStatement(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, value, -1, sqliteTransient)
    }

    private func reset(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }
}

final class CardLookupStore {
    private let database: OpaquePointer
    private let rowsStatement: OpaquePointer
    private let decoder = JSONDecoder()
    static let rowCacheLimit = 256
    private var rowCache = BoundedLookupCache<String, [StoredCardLookupRow]>(limit: rowCacheLimit)
    var cachedRowCount: Int { rowCache.count }

    init?(url: URL, tableName: String) {
        guard let database = Self.openDatabase(url: url) else {
            return nil
        }

        guard let rowsStatement = Self.prepareStatement(
            """
            SELECT ordinal, source, title, summary, chips_json
            FROM \(tableName)
            WHERE headword = ?
            ORDER BY ordinal ASC;
            """,
            in: database
        ) else {
            sqlite3_close(database)
            return nil
        }

        self.database = database
        self.rowsStatement = rowsStatement
    }

    deinit {
        sqlite3_finalize(rowsStatement)
        sqlite3_close(database)
    }

    func rows(for key: String) -> [StoredCardLookupRow]? {
        if let cached = rowCache[key] {
            return cached.isEmpty ? nil : cached
        }

        bind(key, to: rowsStatement)
        defer { reset(rowsStatement) }

        var rows: [StoredCardLookupRow] = []
        while sqlite3_step(rowsStatement) == SQLITE_ROW {
            let source = sqliteColumnString(rowsStatement, index: 1)
            let title = sqliteColumnString(rowsStatement, index: 2)
            let summary = sqliteColumnString(rowsStatement, index: 3)
            let chipsData = Data(sqliteColumnString(rowsStatement, index: 4).utf8)
            let chips = (try? decoder.decode([String].self, from: chipsData)) ?? []
            rows.append(
                StoredCardLookupRow(
                    source: source,
                    title: title,
                    summary: summary,
                    chips: chips
                )
            )
        }
        rowCache[key] = rows
        return rows.isEmpty ? nil : rows
    }

    func firstRows<S: Sequence>(forAny keys: S) -> (key: String, rows: [StoredCardLookupRow])? where S.Element == String {
        for key in keys {
            if let rows = rows(for: key) {
                return (key, rows)
            }
        }
        return nil
    }

    private func bind(_ value: String, to statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, value, -1, sqliteTransient)
    }

    private func reset(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private static func openDatabase(url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        let immutableURI = url.absoluteString + "?immutable=1&mode=ro"

        if sqlite3_open_v2(immutableURI, &database, flags, nil) != SQLITE_OK {
            if let database {
                sqlite3_close(database)
            }
            database = nil

            if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
                if let database {
                    sqlite3_close(database)
                }
                return nil
            }
        }

        sqlite3_exec(database, "PRAGMA query_only = ON;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA mmap_size = 134217728;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA cache_size = -4096;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        return database
    }

    private static func prepareStatement(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }
}

private struct SearchCacheKey: Hashable {
    let term: String
    let intent: QueryIntent
}

private struct ReferenceNotesRecoveryResult {
    let normalized: String
    let standardCandidates: [String]
    let candidateKeys: [String]
    let entries: [ReferenceEntry]
    let usedDirectEntries: Bool
    let fuzzyCandidateCount: Int
    let phaseTimings: [DictionaryRepository.DeepRecoveryDiagnostics.PhaseTiming]
}

private struct DefinitionContext {
    let definitions: [String]
    let relatedTerms: [String]
}

private struct DerivationalCandidate {
    let base: String
    let kind: DerivationalKind
}

private struct DerivedMeaning {
    let base: String
    let kind: DerivationalKind
    let shortDefinition: String
    let baseDefinitions: [String]
    let relatedTerms: [String]
}

struct StoredCardLookupRow {
    let source: String
    let title: String
    let summary: String
    let chips: [String]
}

private struct ReferenceNote: Codable {
    let title: String
    let sourceTitle: String
    let summary: String
    let aliases: [String]
    let chips: [String]
    let counterparts: [ReferenceCounterpart]?
    let synonyms: [String]?
    let antonyms: [String]?
    let seeAlso: [String]?
    let forms: [ReferenceForm]?

    var expandedEntries: [ReferenceEntry] {
        let baseEntry = ReferenceEntry(
            title: title,
            sourceTitle: sourceTitle,
            summary: summary,
            aliases: aliases,
            chips: chips,
            counterparts: counterparts ?? [],
            synonyms: synonyms ?? [],
            antonyms: antonyms ?? [],
            seeAlso: seeAlso ?? [],
            lookupKeys: [title] + aliases + (synonyms ?? []) + (antonyms ?? []),
            isVariant: false
        )

        let variantEntries = (forms ?? []).map { form in
            ReferenceEntry(
                title: form.title,
                sourceTitle: sourceTitle,
                summary: form.summary,
                aliases: form.aliases,
                chips: dedupeReferenceStrings(chips + form.chips + ["variant entry", "base: \(title.lowercased())"]),
                counterparts: dedupeCounterparts((counterparts ?? []) + (form.counterparts ?? [])),
                synonyms: dedupeReferenceStrings((synonyms ?? []) + (form.synonyms ?? [])),
                antonyms: dedupeReferenceStrings((antonyms ?? []) + (form.antonyms ?? [])),
                seeAlso: dedupeReferenceStrings([title] + (seeAlso ?? []) + (form.seeAlso ?? [])),
                lookupKeys: [form.title] + form.aliases + (form.synonyms ?? []) + (form.antonyms ?? []),
                isVariant: true
            )
        }

        return [baseEntry] + variantEntries
    }

    var lookupKeys: [String] {
        [title] + aliases
    }
}

private struct ReferenceForm: Codable {
    let title: String
    let summary: String
    let aliases: [String]
    let chips: [String]
    let counterparts: [ReferenceCounterpart]?
    let synonyms: [String]?
    let antonyms: [String]?
    let seeAlso: [String]?

    init(
        title: String,
        summary: String,
        aliases: [String] = [],
        chips: [String] = [],
        counterparts: [ReferenceCounterpart] = [],
        synonyms: [String] = [],
        antonyms: [String] = [],
        seeAlso: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.aliases = aliases
        self.chips = chips
        self.counterparts = counterparts
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.seeAlso = seeAlso
    }
}

private struct ReferenceCounterpart: Codable {
    let label: String
    let term: String
}

private struct ReferenceEntry: Codable {
    let title: String
    let sourceTitle: String
    let summary: String
    let aliases: [String]
    let chips: [String]
    let counterparts: [ReferenceCounterpart]
    let synonyms: [String]
    let antonyms: [String]
    let seeAlso: [String]
    let lookupKeys: [String]
    let isVariant: Bool
}

private struct ReferenceNotesArchive: Codable {
    let version: Int
    let notes: [ReferenceNote]
    let entries: [ReferenceEntry]
    let entriesByLookupKey: [String: [ReferenceEntry]]
    let entriesByPhraseCoreKey: [String: [ReferenceEntry]]
    let sortedHeadwords: [String]
    let topicTermsByEntryKey: [String: [String]]
    let sourceTitles: [String]
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let fastLookupBlobSeparator: Character = "\u{1F}"

private func sqliteColumnString(_ statement: OpaquePointer?, index: Int32) -> String {
    guard let cString = sqlite3_column_text(statement, index) else {
        return ""
    }
    return String(cString: cString)
}

private func parseFastLookupPOSBlob(_ blob: String) -> [String: Int] {
    guard !blob.isEmpty else { return [:] }
    var result: [String: Int] = [:]
    for segment in blob.split(separator: "|", omittingEmptySubsequences: true) {
        let parts = segment.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let count = Int(parts[1]) else { continue }
        result[String(parts[0])] = count
    }
    return result
}

private let ignoredTopicChips: Set<String> = [
    "adjective",
    "adverb",
    "american english",
    "american politics",
    "australian english",
    "british english",
    "canadian english",
    "colloquial",
    "commonwealth",
    "cross-dialect",
    "culture",
    "dialect",
    "etymology",
    "everyday speech",
    "figurative use",
    "historical",
    "informal",
    "irish english",
    "new zealand english",
    "noun",
    "participle",
    "plural",
    "plural form",
    "regional usage",
    "scots",
    "south african english",
    "spelling",
    "usage note",
    "variant entry",
    "variant spelling",
    "word origins"
]

private let phraseCoreStopwords: Set<String> = [
    "a",
    "an",
    "the",
    "of",
    "in",
    "to",
    "for",
    "at",
    "my",
    "your",
    "his",
    "her",
    "our",
    "their",
    "ones",
    "someone",
    "someones",
    "somebody",
    "somebodys"
]

private func dedupeReferenceStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let key = normalizedReferenceLookupKey(trimmed)
        guard !key.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        out.append(trimmed)
    }
    return out
}

private func dedupeCounterparts(_ values: [ReferenceCounterpart]) -> [ReferenceCounterpart] {
    var seen = Set<String>()
    var out: [ReferenceCounterpart] = []
    for value in values {
        let label = value.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let term = value.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelKey = normalizedReferenceLookupKey(label)
        let termKey = normalizedReferenceLookupKey(term)
        guard !labelKey.isEmpty, !termKey.isEmpty else { continue }
        let key = "\(labelKey)|\(termKey)"
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        out.append(.init(label: label, term: term))
    }
    return out
}

private func normalizedReferenceLookupKey(_ string: String) -> String {
    string
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

private enum DerivationalKind {
    case adjectiveY
    case adjectiveIsh
    case adjectiveFul
    case adjectiveLess
    case adjectiveLike
    case adverbLy
    case nounNess
    case comparativeEr
    case superlativeEst

    var label: String {
        switch self {
        case .adjectiveY: return "-y adjective"
        case .adjectiveIsh: return "-ish adjective"
        case .adjectiveFul: return "-ful adjective"
        case .adjectiveLess: return "-less adjective"
        case .adjectiveLike: return "-like adjective"
        case .adverbLy: return "-ly adverb"
        case .nounNess: return "-ness noun"
        case .comparativeEr: return "comparative"
        case .superlativeEst: return "superlative"
        }
    }

    func definition(for term: String, base: String) -> String {
        switch self {
        case .adjectiveY:
            return "characterized by, suggestive of, or full of \(base)"
        case .adjectiveIsh:
            return "somewhat like \(base), or marked by a touch of \(base)"
        case .adjectiveFul:
            return "full of \(base), or marked by \(base)"
        case .adjectiveLess:
            return "without \(base), or lacking \(base)"
        case .adjectiveLike:
            return "like \(base), or resembling \(base)"
        case .adverbLy:
            return "in a \(base)-like or \(base)-marked way"
        case .nounNess:
            return "the quality, condition, or state of being \(base)"
        case .comparativeEr:
            return "more \(base)"
        case .superlativeEst:
            return "most \(base)"
        }
    }
}

private let regionalEnglishSources: [(label: String, relativePath: String)] = [
    ("American", "01MAY2026_Resources/Dictionaries-master/English (American).dic"),
    ("Australian", "01MAY2026_Resources/Dictionaries-master/English (Australian).dic"),
    ("British", "01MAY2026_Resources/Dictionaries-master/English (British).dic"),
    ("Canadian", "01MAY2026_Resources/Dictionaries-master/English (Canadian).dic"),
    ("New Zealand", "01MAY2026_Resources/Dictionaries-master/English (New Zealand).dic"),
    ("South African", "01MAY2026_Resources/Dictionaries-master/English (South African).dic")
]

// SAX-style delegate that extracts LexicalEntry and Synset data from the LMF XML.
// Stops accumulating entries after a generous cap to avoid over-allocating on 85 MB files.
private final class WordNetXMLDelegate: NSObject, XMLParserDelegate {
    var synsetsByHeadword: [String: [String]] = [:]
    var posByHeadword: [String: String] = [:]
    var definitionBySynset: [String: String] = [:]
    var headwordsBySynset: [String: [String]] = [:]
    var synsetCountByPOSByHeadword: [String: [String: Int]] = [:]

    private var currentHeadword: String?
    private var currentPOS: String?
    private var currentSynsets: [String] = []
    private var currentSynsetID: String?
    private var inDefinition = false
    private var definitionBuffer = ""
    private var entryCount = 0
    private let entryLimit = 200_000

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "LexicalEntry":
            currentHeadword = nil
            currentPOS = nil
            currentSynsets = []
        case "Lemma":
            currentHeadword = attributes["writtenForm"]
            currentPOS = attributes["partOfSpeech"]
        case "Sense":
            if let synset = attributes["synset"] {
                currentSynsets.append(synset)
            }
        case "Synset":
            currentSynsetID = attributes["id"]
            inDefinition = false
            definitionBuffer = ""
        case "Definition":
            inDefinition = true
            definitionBuffer = ""
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "LexicalEntry":
            if let headword = currentHeadword,
               !headword.isEmpty,
               entryCount < entryLimit {
                let trimmedHeadword = headword.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = headword
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
                synsetsByHeadword[key] = currentSynsets
                for synset in currentSynsets {
                    var lemmas = headwordsBySynset[synset] ?? []
                    if !lemmas.contains(trimmedHeadword) {
                        lemmas.append(trimmedHeadword)
                        headwordsBySynset[synset] = lemmas
                    }
                }
                if let pos = currentPOS {
                    posByHeadword[key] = pos
                    var posMap = synsetCountByPOSByHeadword[key] ?? [:]
                    posMap[pos, default: 0] += currentSynsets.count
                    synsetCountByPOSByHeadword[key] = posMap
                }
                entryCount += 1
            }
        case "Synset":
            if let id = currentSynsetID,
               !definitionBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                definitionBySynset[id] = definitionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentSynsetID = nil
            inDefinition = false
        case "Definition":
            inDefinition = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inDefinition {
            definitionBuffer += string
        }
    }
}
