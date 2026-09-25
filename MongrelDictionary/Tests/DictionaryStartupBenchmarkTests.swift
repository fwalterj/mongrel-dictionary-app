import Foundation
import XCTest
@testable import MongrelDictionaryCore

@MainActor
final class DictionaryStartupBenchmarkTests: XCTestCase {
    private struct Metric: Codable {
        let name: String
        let coldMS: Int
        let medianMS: Int
        let p95MS: Int
        let minMS: Int
        let maxMS: Int
        let samples: Int
    }

    private struct BenchmarkThreshold {
        let medianMS: Int
        let p95MS: Int
        let maxMS: Int
    }

    private struct Report: Codable {
        let timestamp: String
        let rounds: Int
        let metrics: [Metric]
    }

    func testStartupBenchmark() async throws {
        let rounds = 8

        var searchReadySamples: [Int] = []
        var archiveReadySamples: [Int] = []
        var firstDefineSamples: [Int] = []
        var firstTranslationSamples: [Int] = []

        searchReadySamples.reserveCapacity(rounds)
        archiveReadySamples.reserveCapacity(rounds)
        firstDefineSamples.reserveCapacity(rounds)
        firstTranslationSamples.reserveCapacity(rounds)

        for _ in 0..<rounds {
            let launch = try await measureLaunchMilestones()
            searchReadySamples.append(launch.searchReadyMS)
            archiveReadySamples.append(launch.archiveReadyMS)
        }

        for _ in 0..<rounds {
            firstDefineSamples.append(try await measureLaunchToFirstSearch(term: "dog", intent: .define))
        }

        for _ in 0..<rounds {
            firstTranslationSamples.append(try await measureLaunchToFirstSearch(term: "house", intent: .translation))
        }

        let metrics = [
            buildMetric(name: "launch_to_search_ready", samples: searchReadySamples),
            buildMetric(name: "launch_to_archive_ready", samples: archiveReadySamples),
            buildMetric(name: "launch_to_first_define_result", samples: firstDefineSamples),
            buildMetric(name: "launch_to_first_translation_result", samples: firstTranslationSamples)
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let report = Report(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            rounds: rounds,
            metrics: metrics
        )
        let payload = try encoder.encode(report)
        let json = String(decoding: payload, as: UTF8.self)
        print("MONGREL_STARTUP_BENCHMARK::\(json)")

        assertSafetyCeilings(metrics)
    }

    private func measureLaunchMilestones() async throws -> (searchReadyMS: Int, archiveReadyMS: Int) {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let launchStart = DispatchTime.now().uptimeNanoseconds
        let session = DictionarySession(
            repository: DictionaryRepository(),
            userDefaults: userDefaults
        )

        let searchReadyMS = try await elapsedUntil(
            since: launchStart,
            message: "startup reaches search-ready phase"
        ) {
            session.startup.searchReady
        }
        let archiveReadyMS = try await elapsedUntil(
            since: launchStart,
            message: "startup reaches archive-ready phase"
        ) {
            session.startup.inventoryReady
        }

        return (searchReadyMS, archiveReadyMS)
    }

    private func measureLaunchToFirstSearch(term: String, intent: QueryIntent) async throws -> Int {
        let (suiteName, userDefaults) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let launchStart = DispatchTime.now().uptimeNanoseconds
        let session = DictionarySession(
            repository: DictionaryRepository(),
            userDefaults: userDefaults
        )

        _ = try await elapsedUntil(
            since: launchStart,
            message: "startup reaches search-ready phase before first search"
        ) {
            session.startup.searchReady
        }

        session.selectIntent(intent)
        session.selectTerm(term)

        return try await elapsedUntil(
            since: launchStart,
            message: "first \(intent.rawValue) search returns results"
        ) {
            session.lastSearchedTerm == term &&
            session.lastResultCount > 0 &&
            !session.isSearching
        }
    }

    private func elapsedUntil(
        since startNanoseconds: UInt64,
        message: String,
        timeoutNanoseconds: UInt64 = 4_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Int {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return Int((DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1_000_000)
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Timed out waiting for \(message)")
        return Int((DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1_000_000)
    }

    private func buildMetric(name: String, samples: [Int]) -> Metric {
        let sorted = samples.sorted()
        return Metric(
            name: name,
            coldMS: samples.first ?? 0,
            medianMS: percentile(sorted, p: 0.50),
            p95MS: percentile(sorted, p: 0.95),
            minMS: sorted.first ?? 0,
            maxMS: sorted.last ?? 0,
            samples: sorted.count
        )
    }

    private func percentile(_ sortedValues: [Int], p: Double) -> Int {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(p, 0.0), 1.0)
        let position = Int(Double(sortedValues.count - 1) * clamped)
        return sortedValues[position]
    }

    private func assertSafetyCeilings(_ metrics: [Metric]) {
        // Startup is now expected to stay close to "native-feel" territory. These ceilings
        // still leave room for occasional scheduler noise, but they are tight enough to catch
        // a real regression in launch responsiveness.
        let thresholds: [String: BenchmarkThreshold] = [
            "launch_to_search_ready": .init(medianMS: 20, p95MS: 30, maxMS: 45),
            "launch_to_archive_ready": .init(medianMS: 20, p95MS: 30, maxMS: 45),
            "launch_to_first_define_result": .init(medianMS: 35, p95MS: 50, maxMS: 65),
            "launch_to_first_translation_result": .init(medianMS: 35, p95MS: 50, maxMS: 65)
        ]

        for metric in metrics {
            guard let threshold = thresholds[metric.name] else {
                XCTFail("Add a startup safety ceiling for metric '\(metric.name)'.")
                continue
            }

            XCTAssertLessThanOrEqual(
                metric.medianMS,
                threshold.medianMS,
                "\(metric.name) exceeded startup median ceiling (\(metric.medianMS)ms > \(threshold.medianMS)ms)."
            )

            XCTAssertLessThanOrEqual(
                metric.p95MS,
                threshold.p95MS,
                "\(metric.name) exceeded startup p95 ceiling (\(metric.p95MS)ms > \(threshold.p95MS)ms)."
            )

            XCTAssertLessThanOrEqual(
                metric.maxMS,
                threshold.maxMS,
                "\(metric.name) exceeded startup ceiling (\(metric.maxMS)ms > \(threshold.maxMS)ms)."
            )
        }
    }

    private func makeIsolatedDefaults() -> (suiteName: String, userDefaults: UserDefaults) {
        let suiteName = "mongrel.dictionary.startup-benchmark.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        return (suiteName, userDefaults)
    }
}
