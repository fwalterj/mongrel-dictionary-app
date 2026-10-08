import Foundation

/// Presentation follows the actual packaged edition, never a user preference.
public enum DictionaryCorpusEdition {
    private final class BundleLocator {}
    public static let isPublicCore = Bundle(for: BundleLocator.self)
        .url(forResource: "PUBLIC-CORPUS", withExtension: "json") != nil
    public static var availableIntents: [QueryIntent] {
        isPublicCore ? [.define, .synonyms] : QueryIntent.allCases
    }
    public static let coreDescription = "Core Beta: English definitions and synonyms from Open English Wordnet 2025 and Princeton WordNet 3.0. Translation, dedicated regional/slang collections, and reference notes are not included."
    public static var noticesURL: URL? {
        Bundle(for: BundleLocator.self).url(forResource: "CORPUS-NOTICES", withExtension: "txt")
    }
}
