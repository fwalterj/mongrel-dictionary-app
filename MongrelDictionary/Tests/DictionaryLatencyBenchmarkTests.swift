import Foundation
import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLatencyBenchmarkTests: XCTestCase {
    private struct BenchmarkOutcome {
        let resultCount: Int
        let elapsedMS: Int
        let sourceTimings: [SourceTimingSnapshot]
    }

    private struct SourceTimingSnapshot: Codable {
        let name: String
        let elapsedMS: Int
        let resultCount: Int
    }

    private struct SlowSample: Codable {
        let term: String
        let durationMS: Int
        let sourceTimings: [SourceTimingSnapshot]
    }

    private struct Metric: Codable {
        let name: String
        let mode: String
        let coldMS: Int
        let medianMS: Int
        let p95MS: Int
        let minMS: Int
        let maxMS: Int
        let samples: Int
        let worstSample: SlowSample?
    }

    private struct BenchmarkThreshold {
        let coldMS: Int?
        let p95MS: Int?
        let maxMS: Int
    }

    private struct Report: Codable {
        let timestamp: String
        let rounds: Int
        let metrics: [Metric]
    }

    private struct BenchmarkScenario {
        let name: String
        let profile: DictionaryRepository.PrewarmProfile
        let terms: [String]
        let run: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome
    }

    func testLatencyBenchmark() async throws {
        let rounds = 24

        let defineSearchRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let cards = await repository.search(term: term, intent: .define)
            let diagnostics = await repository.diagnostics()
            return BenchmarkOutcome(
                resultCount: cards.count,
                elapsedMS: diagnostics.lastSearchProfile?.totalElapsedMS ?? 0,
                sourceTimings: diagnostics.lastSearchProfile?.sourceTimings.map {
                    SourceTimingSnapshot(
                        name: $0.name,
                        elapsedMS: $0.elapsedMS,
                        resultCount: $0.resultCount
                    )
                } ?? []
            )
        }
        let synonymSearchRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let cards = await repository.search(term: term, intent: .synonyms)
            let diagnostics = await repository.diagnostics()
            return BenchmarkOutcome(
                resultCount: cards.count,
                elapsedMS: diagnostics.lastSearchProfile?.totalElapsedMS ?? 0,
                sourceTimings: diagnostics.lastSearchProfile?.sourceTimings.map {
                    SourceTimingSnapshot(
                        name: $0.name,
                        elapsedMS: $0.elapsedMS,
                        resultCount: $0.resultCount
                    )
                } ?? []
            )
        }
        let translationSearchRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let cards = await repository.search(term: term, intent: .translation)
            let diagnostics = await repository.diagnostics()
            return BenchmarkOutcome(
                resultCount: cards.count,
                elapsedMS: diagnostics.lastSearchProfile?.totalElapsedMS ?? 0,
                sourceTimings: diagnostics.lastSearchProfile?.sourceTimings.map {
                    SourceTimingSnapshot(
                        name: $0.name,
                        elapsedMS: $0.elapsedMS,
                        resultCount: $0.resultCount
                    )
                } ?? []
            )
        }
        let slangSearchRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let cards = await repository.search(term: term, intent: .slang)
            let diagnostics = await repository.diagnostics()
            return BenchmarkOutcome(
                resultCount: cards.count,
                elapsedMS: diagnostics.lastSearchProfile?.totalElapsedMS ?? 0,
                sourceTimings: diagnostics.lastSearchProfile?.sourceTimings.map {
                    SourceTimingSnapshot(
                        name: $0.name,
                        elapsedMS: $0.elapsedMS,
                        resultCount: $0.resultCount
                    )
                } ?? []
            )
        }
        let phraseNoteRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let timed = await repository.referenceNotesTimedProbe(term: term)
            return BenchmarkOutcome(resultCount: timed.cards.count, elapsedMS: timed.elapsedMS, sourceTimings: [])
        }
        let deepRecoveryRun: @Sendable (DictionaryRepository, String) async -> BenchmarkOutcome = { repository, term in
            let diagnostics = await repository.referenceNotesRecoveryDiagnosticsProbe(term: term)
            return BenchmarkOutcome(
                resultCount: diagnostics.recoveredEntryCount,
                elapsedMS: diagnostics.totalElapsedMS,
                sourceTimings: diagnostics.phaseTimings.map {
                    SourceTimingSnapshot(
                        name: $0.name,
                        elapsedMS: $0.elapsedMS,
                        resultCount: diagnostics.recoveredEntryCount
                    )
                }
            )
        }

        let reusedScenarios: [BenchmarkScenario] = [
            .init(
                name: "define_search",
                profile: .defineSearch,
                terms: ["dog", "colour", "arvo", "licence", "metre", "happily", "doomy", "ephemeral"],
                run: defineSearchRun
            ),
            .init(
                name: "synonym_search",
                profile: .defineSearch,
                terms: ["bright", "quick", "happy", "calm", "strong"],
                run: synonymSearchRun
            ),
            .init(
                name: "translation_search",
                profile: .defineSearch,
                terms: ["house", "water", "friend", "night", "book"],
                run: translationSearchRun
            ),
            .init(
                name: "slang_search",
                profile: .defineSearch,
                terms: ["arvo", "bogan", "servo", "mate", "footy"],
                run: slangSearchRun
            ),
        ]

        let freshScenarios: [BenchmarkScenario] = [
            .init(
                name: "define_variant_fresh_cold",
                profile: .defineSearch,
                terms: ["colour", "licence", "metre", "happily", "doomy"],
                run: defineSearchRun
            ),
            .init(
                name: "phrase_note_fresh_cold",
                profile: .referenceNotes,
                terms: ["one's cup of tea", "read between the lines", "in good faith", "face the music"],
                run: phraseNoteRun
            ),
            .init(
                name: "deep_recovery_fresh_cold",
                profile: .deepShared,
                terms: ["lorrry", "cofee break"],
                run: deepRecoveryRun
            ),
            .init(
                name: "synonym_fallback_fresh_cold",
                profile: .defineSearch,
                terms: ["lekker", "howzit", "babbelas", "bakkie"],
                run: synonymSearchRun
            ),
            .init(
                name: "translation_fallback_fresh_cold",
                profile: .defineSearch,
                terms: ["lekker", "howzit", "bakkie", "drookit"],
                run: translationSearchRun
            )
        ]

        var metrics: [Metric] = []

        for scenario in reusedScenarios {
            metrics.append(await benchmarkReusedScenario(scenario, rounds: rounds))
        }

        for scenario in freshScenarios {
            metrics.append(await benchmarkFreshScenario(scenario))
        }

        let suggestionRepository = DictionaryRepository()
        await suggestionRepository.prewarm(profile: .phraseAndSuggestion)
        let suggestionPrefix = "col"
        let suggestionCold = await elapsedMS {
            let suggestions = await suggestionRepository.suggestedTerms(prefix: suggestionPrefix)
            XCTAssertFalse(suggestions.isEmpty, "Expected suggestions for prefix '\(suggestionPrefix)'.")
        }
        var suggestionWarm: [Int] = []
        suggestionWarm.reserveCapacity(rounds)
        for _ in 0..<rounds {
            let duration = await elapsedMS {
                _ = await suggestionRepository.suggestedTerms(prefix: suggestionPrefix)
            }
            suggestionWarm.append(duration)
        }
        metrics.append(
            buildMetric(
                name: "suggested_terms",
                mode: "reuse_prewarmed",
                coldMS: suggestionCold,
                warmSamples: suggestionWarm,
                worstSample: SlowSample(term: suggestionPrefix, durationMS: suggestionWarm.max() ?? suggestionCold, sourceTimings: [])
            )
        )

        let didYouMeanRepository = DictionaryRepository()
        await didYouMeanRepository.prewarm(profile: .phraseAndSuggestion)
        let typo = "colur"
        let didYouMeanCold = await elapsedMS {
            let suggestions = await didYouMeanRepository.didYouMean(term: typo)
            XCTAssertFalse(suggestions.isEmpty, "Expected did-you-mean suggestions for '\(typo)'.")
        }
        var didYouMeanWarm: [Int] = []
        didYouMeanWarm.reserveCapacity(rounds)
        for _ in 0..<rounds {
            let duration = await elapsedMS {
                _ = await didYouMeanRepository.didYouMean(term: typo)
            }
            didYouMeanWarm.append(duration)
        }
        metrics.append(
            buildMetric(
                name: "did_you_mean",
                mode: "reuse_prewarmed",
                coldMS: didYouMeanCold,
                warmSamples: didYouMeanWarm,
                worstSample: SlowSample(term: typo, durationMS: didYouMeanWarm.max() ?? didYouMeanCold, sourceTimings: [])
            )
        )

        let timestampFormatter = ISO8601DateFormatter()
        let report = Report(
            timestamp: timestampFormatter.string(from: Date()),
            rounds: rounds,
            metrics: metrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = try encoder.encode(report)
        let json = String(decoding: payload, as: UTF8.self)
        print("MONGREL_BENCHMARK::\(json)")

        assertPerformanceBudgets(metrics)
    }

    private func elapsedMS(operation: () async -> Void) async -> Int {
        let start = DispatchTime.now().uptimeNanoseconds
        await operation()
        return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private func timedOutcome<T>(operation: () async -> T) async -> (result: T, elapsedMS: Int) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = await operation()
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        return (result, elapsed)
    }

    private func benchmarkReusedScenario(_ scenario: BenchmarkScenario, rounds: Int) async -> Metric {
        let repository = DictionaryRepository()
        await repository.prewarm(profile: scenario.profile)

        let coldRun = await scenario.run(repository, scenario.terms[0])
        XCTAssertGreaterThan(
            coldRun.resultCount,
            0,
            "Expected at least one result card in \(scenario.name) cold run."
        )

        var warmSamples: [Int] = []
        warmSamples.reserveCapacity(rounds)
        var worstSample = SlowSample(
            term: scenario.terms[0],
            durationMS: coldRun.elapsedMS,
            sourceTimings: coldRun.sourceTimings
        )
        for index in 0..<rounds {
            let term = scenario.terms[index % scenario.terms.count]
            let sample = await scenario.run(repository, term)
            XCTAssertGreaterThan(
                sample.resultCount,
                0,
                "Expected at least one result card in \(scenario.name) warm run."
            )
            warmSamples.append(sample.elapsedMS)
            if sample.elapsedMS > worstSample.durationMS {
                worstSample = SlowSample(
                    term: term,
                    durationMS: sample.elapsedMS,
                    sourceTimings: sample.sourceTimings
                )
            }
        }

        return buildMetric(
            name: scenario.name,
            mode: "reuse_prewarmed",
            coldMS: coldRun.elapsedMS,
            warmSamples: warmSamples,
            worstSample: worstSample
        )
    }

    private func benchmarkFreshScenario(_ scenario: BenchmarkScenario) async -> Metric {
        var freshSamples: [Int] = []
        freshSamples.reserveCapacity(scenario.terms.count)
        var worstSample: SlowSample?

        for term in scenario.terms {
            let repository = DictionaryRepository()
            await repository.prewarm(profile: scenario.profile)
            let sample = await scenario.run(repository, term)
            XCTAssertGreaterThan(
                sample.resultCount,
                0,
                "Expected at least one result card in \(scenario.name) fresh run for '\(term)'."
            )
            freshSamples.append(sample.elapsedMS)
            if worstSample == nil || sample.elapsedMS > worstSample?.durationMS ?? 0 {
                worstSample = SlowSample(
                    term: term,
                    durationMS: sample.elapsedMS,
                    sourceTimings: sample.sourceTimings
                )
            }
        }

        return buildMetric(
            name: scenario.name,
            mode: "fresh_prewarmed",
            coldMS: freshSamples.first ?? 0,
            warmSamples: freshSamples,
            worstSample: worstSample
        )
    }

    private func buildMetric(name: String, mode: String, coldMS: Int, warmSamples: [Int], worstSample: SlowSample?) -> Metric {
        let sorted = warmSamples.sorted()
        let median = percentile(sorted, p: 0.50)
        let p95 = percentile(sorted, p: 0.95)
        return Metric(
            name: name,
            mode: mode,
            coldMS: coldMS,
            medianMS: median,
            p95MS: p95,
            minMS: sorted.first ?? 0,
            maxMS: sorted.last ?? 0,
            samples: warmSamples.count,
            worstSample: worstSample
        )
    }

    private func percentile(_ sortedValues: [Int], p: Double) -> Int {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(p, 0.0), 1.0)
        let position = Int(Double(sortedValues.count - 1) * clamped)
        return sortedValues[position]
    }

    private func assertPerformanceBudgets(_ metrics: [Metric]) {
        // These p95 budgets intentionally leave a few milliseconds of wall-clock headroom
        // for scheduler noise on shared developer machines. The max budget remains the
        // hard guardrail for real regressions.
        let thresholds: [String: BenchmarkThreshold] = [
            "define_search": .init(coldMS: 30, p95MS: 12, maxMS: 30),
            "synonym_search": .init(coldMS: 25, p95MS: 14, maxMS: 25),
            "translation_search": .init(coldMS: 30, p95MS: 18, maxMS: 30),
            "slang_search": .init(coldMS: 20, p95MS: 10, maxMS: 20),
            "define_variant_fresh_cold": .init(coldMS: 25, p95MS: 16, maxMS: 25),
            "phrase_note_fresh_cold": .init(coldMS: 20, p95MS: 12, maxMS: 20),
            "deep_recovery_fresh_cold": .init(coldMS: 20, p95MS: 12, maxMS: 20),
            "synonym_fallback_fresh_cold": .init(coldMS: 35, p95MS: 28, maxMS: 35),
            "translation_fallback_fresh_cold": .init(coldMS: 35, p95MS: 28, maxMS: 35),
            "suggested_terms": .init(coldMS: 15, p95MS: 8, maxMS: 15),
            "did_you_mean": .init(coldMS: 20, p95MS: 12, maxMS: 20),
        ]

        let metricNames = Set(metrics.map(\.name))
        let missingBudgets = Set(thresholds.keys).subtracting(metricNames)
        XCTAssertTrue(
            missingBudgets.isEmpty,
            "Missing benchmark metrics for: \(missingBudgets.sorted().joined(separator: ", "))"
        )

        for metric in metrics {
            guard let threshold = thresholds[metric.name] else {
                XCTFail("Add a performance budget for benchmark metric '\(metric.name)'.")
                continue
            }

            if let coldMS = threshold.coldMS {
                XCTAssertLessThanOrEqual(
                    metric.coldMS,
                    coldMS,
                    "\(metric.name) cold run exceeded budget (\(metric.coldMS)ms > \(coldMS)ms)."
                )
            }
            if let p95MS = threshold.p95MS {
                XCTAssertLessThanOrEqual(
                    metric.p95MS,
                    p95MS,
                    "\(metric.name) p95 exceeded budget (\(metric.p95MS)ms > \(p95MS)ms)."
                )
            }
            XCTAssertLessThanOrEqual(
                metric.maxMS,
                threshold.maxMS,
                "\(metric.name) max exceeded budget (\(metric.maxMS)ms > \(threshold.maxMS)ms)."
            )
        }
    }
}
