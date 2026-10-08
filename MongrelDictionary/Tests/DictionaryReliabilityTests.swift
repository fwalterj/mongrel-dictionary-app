import Foundation
import SQLite3
import XCTest
import Darwin
@testable import MongrelDictionaryCore

final class DictionaryReliabilityTests: XCTestCase {
    func testDiverseCorpusSoakReachesABoundedWorkingSet() async throws {
        let url = try XCTUnwrap(Bundle(for: DictionaryRepository.self)
            .url(forResource: "FastLookup", withExtension: "sqlite3"))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database,
            "SELECT headword FROM define_entries WHERE length(headword) BETWEEN 4 AND 20 ORDER BY headword LIMIT 5000", -1,
            &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var words: [String] = []
        var row = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            if row.isMultiple(of: 5), let text = sqlite3_column_text(statement, 0) {
                words.append(String(cString: text))
            }
            row += 1
        }
        XCTAssertEqual(words.count, 1000)
        let repository = DictionaryRepository()
        await repository.prewarm(profile: .interactiveSession)
        var samples: [UInt64] = []
        for round in 1...3 {
            var timings: [Double] = []
            for (index, word) in words.enumerated() {
                let start = DispatchTime.now().uptimeNanoseconds
                let intents = DictionaryCorpusEdition.availableIntents
                _ = await repository.search(term: word, intent: intents[index % intents.count],
                                            bypassCache: true, allowBackgroundEnrichment: false)
                timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            let snapshot = await repository.diagnostics()
            for cache in snapshot.cacheEntries {
                XCTAssertLessThanOrEqual(cache.count, cache.limit, cache.name)
            }
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            XCTAssertEqual(status, KERN_SUCCESS)
            samples.append(info.phys_footprint)
            timings.sort()
            print("MONGREL_DIVERSE_SOAK::round=\(round) queries=\(words.count) medianMS=\(timings[500]) p95MS=\(timings[950]) maxMS=\(timings.last ?? 0) processFootprintBytes=\(info.phys_footprint)")
        }
        // Permit allocator and XCTest bookkeeping noise, but catch another
        // large corpus-sized allocation on each repeated round.
        XCTAssertLessThan(samples[2], samples[1] + 32 * 1024 * 1024)
    }

    func testComposedAndDecomposedAccentedLookupsAgree() async {
        let repository = DictionaryRepository()
        for term in ["café", "naïve", "résumé"] {
            let composed = await repository.search(term: term, bypassCache: true)
            let decomposed = await repository.search(term: term.decomposedStringWithCanonicalMapping, bypassCache: true)
            XCTAssertFalse(composed.isEmpty, term)
            XCTAssertEqual(composed.map(\.summary), decomposed.map(\.summary), term)
        }
    }

    func testMissingAndMalformedRuntimeResourcesDoNotCrashOrFindWorkbenchData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = directory.appendingPathComponent("Empty.bundle/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try XCTUnwrap(Bundle(url: directory.appendingPathComponent("Empty.bundle")))
        for malformed in [false, true] {
            if malformed {
                for name in ["FastLookup.sqlite3", "SynonymLookup.sqlite3", "TranslationLookup.sqlite3",
                             "ReferenceNotes.sqlite3", "SearchLexicon.mgrt", "WordNet2025.mgrt", "ReferenceNotes.mgrt"] {
                    try Data("not a valid resource".utf8).write(to: resources.appendingPathComponent(name))
                }
            }
            let repository = DictionaryRepository(workspaceRootURL: directory, resourceBundle: bundle)
            await repository.prewarm(profile: .interactiveSession)
            for intent in QueryIntent.allCases {
                let cards = await repository.search(term: "harbor", intent: intent)
                XCTAssertTrue(cards.allSatisfy { $0.source.hasPrefix("No match") },
                              "Damaged package returned \(cards.map { $0.source + ": " + $0.title })")
            }
        }
    }

    func testMalformedDatabaseIsRejectedWithoutCreatingOrChangingIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("invalid database".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(CardLookupStore(url: url, tableName: "cards"))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(CardLookupStore(url: url.appendingPathExtension("missing"), tableName: "cards"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("missing").path))
    }

    func testLongUnicodeEntryAndMalformedChipsRemainReadable() throws {
        try withStore { store in
            let entry = try XCTUnwrap(store.rows(for: "long")?.first)
            XCTAssertEqual(entry.summary.count, 100_000)
            XCTAssertTrue(entry.summary.hasPrefix("é"))
            XCTAssertTrue(entry.chips.isEmpty)
        }
    }
    func testRowCacheEvictsLeastRecentlyUsedAndReleasesRemovedValues() {
        var cache = BoundedLookupCache<String, String>(limit: 2)
        cache["first"] = "one"
        cache["second"] = "two"
        XCTAssertEqual(cache["first"], "one")
        cache["third"] = "three"
        XCTAssertNil(cache["second"])
        XCTAssertEqual(cache["first"], "one")
        cache["first"] = "updated"
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache["first"], "updated")
        cache["first"] = nil
        XCTAssertEqual(cache.count, 1)
        var disabled = BoundedLookupCache<Int, Int>(limit: 0)
        disabled[1] = 1
        XCTAssertEqual(disabled.count, 0)
    }

    func testCachedMissKeepsLookingForFallbackOnEveryLookup() throws {
        try withStore { store in
            for _ in 0..<20 {
                let match = store.firstRows(forAny: ["missing", "harbor"])
                XCTAssertEqual(match?.key, "harbor")
                XCTAssertEqual(match?.rows.first?.summary, "A sheltered port.")
                XCTAssertNil(store.rows(for: "missing"))
            }
        }
    }

    func testThousandsOfUniqueDatabaseMissesKeepMemoryCacheBounded() throws {
        try withStore { store in
            for index in 0..<10_000 {
                XCTAssertNil(store.rows(for: "missing-\(index)"))
                XCTAssertLessThanOrEqual(store.cachedRowCount, CardLookupStore.rowCacheLimit)
                if index.isMultiple(of: 100) {
                    XCTAssertEqual(store.rows(for: "harbor")?.first?.summary, "A sheltered port.")
                }
            }
            XCTAssertEqual(store.cachedRowCount, CardLookupStore.rowCacheLimit)
            XCTAssertEqual(store.firstRows(forAny: ["missing-9999", "harbor"])?.key, "harbor")
        }
    }

    func testRepeatedMixedLookupsRemainConsistentAndCachesStayBounded() async {
        let repository = DictionaryRepository()
        await repository.prewarm(profile: .interactiveSession)
        let cases: [(String, QueryIntent)] = [
            ("harbor", .define), ("dog", .define), ("colour", .define),
            ("happy", .synonyms), ("good", .synonyms),
            ("hello", .translation), ("water", .translation),
            ("arvo", .slang)
        ].filter { DictionaryCorpusEdition.availableIntents.contains($0.1) }
        var baseline: [[String]] = []
        for (term, intent) in cases {
            let cards = await repository.search(term: term, intent: intent, bypassCache: true)
            XCTAssertFalse(cards.isEmpty, "\(term) in \(intent) should have results")
            baseline.append(cards.map { "\($0.source)|\($0.title)|\($0.summary)" })
        }
        var timings: [Double] = []
        for index in 0..<1_000 {
            let slot = index % cases.count
            let (term, intent) = cases[slot]
            let start = DispatchTime.now().uptimeNanoseconds
            let cards = await repository.search(term: term, intent: intent, bypassCache: true)
            timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            XCTAssertEqual(cards.map { "\($0.source)|\($0.title)|\($0.summary)" }, baseline[slot])
            if index.isMultiple(of: 50) {
                let snapshot = await repository.diagnostics()
                for cache in snapshot.cacheEntries {
                    XCTAssertLessThanOrEqual(cache.count, cache.limit, cache.name)
                }
            }
        }
        let sorted = timings.sorted()
        print("MONGREL_SOAK::lookups=1000 cache=bypassed medianMS=\(sorted[500]) p95MS=\(sorted[950]) maxMS=\(sorted[999])")
    }

    private func withStore(_ body: (CardLookupStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("Could not create fixture") }
        let status = sqlite3_exec(database, """
            CREATE TABLE cards (headword TEXT, ordinal INTEGER, source TEXT, title TEXT, summary TEXT, chips_json TEXT);
            CREATE INDEX headword_lookup ON cards(headword);
            INSERT INTO cards VALUES ('harbor', 0, 'Fixture', 'Harbor', 'A sheltered port.', '["noun"]');
            INSERT INTO cards VALUES ('long', 0, 'Fixture', 'Long', replace(hex(zeroblob(50000)), '0', 'é'), 'malformed');
            """, nil, nil, nil)
        sqlite3_close(database)
        XCTAssertEqual(status, SQLITE_OK)
        let store = try XCTUnwrap(CardLookupStore(url: url, tableName: "cards"))
        try body(store)
    }
}
