import XCTest
@testable import MongrelDictionaryCore

private actor SmokeRepositoryRegistry {
    static let shared = SmokeRepositoryRegistry()

    private var repositories: [String: DictionaryRepository] = [:]
    private var warmTasks: [String: Task<DictionaryRepository, Never>] = [:]

    func prepare(
        for shardKey: String,
        profile: DictionaryRepository.PrewarmProfile
    ) {
        guard repositories[shardKey] == nil, warmTasks[shardKey] == nil else {
            return
        }

        let task = Task<DictionaryRepository, Never> {
            let repository = DictionaryRepository()
            await repository.prewarm(profile: profile)
            return repository
        }
        warmTasks[shardKey] = task
    }

    func repository(
        for shardKey: String,
        profile: DictionaryRepository.PrewarmProfile
    ) async -> DictionaryRepository {
        if let repository = repositories[shardKey] {
            return repository
        }
        if warmTasks[shardKey] == nil {
            prepare(for: shardKey, profile: profile)
        }
        guard let task = warmTasks[shardKey] else {
            let repository = DictionaryRepository()
            repositories[shardKey] = repository
            return repository
        }

        let repository = await task.value
        repositories[shardKey] = repository
        warmTasks[shardKey] = nil
        return repository
    }
}

class DictionarySmokeTestCase: XCTestCase {
    class var prewarmProfile: DictionaryRepository.PrewarmProfile { .none }
    class var repositoryScopeKey: String { String(reflecting: self) }

    override class func setUp() {
        super.setUp()
        let shardKey = self.repositoryScopeKey
        let profile = self.prewarmProfile
        Task {
            await SmokeRepositoryRegistry.shared.prepare(for: shardKey, profile: profile)
        }
    }

    func makeRepository() async -> DictionaryRepository {
        await SmokeRepositoryRegistry.shared.repository(
            for: type(of: self).repositoryScopeKey,
            profile: type(of: self).prewarmProfile
        )
    }
}
