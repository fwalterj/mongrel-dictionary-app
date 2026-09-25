import Foundation

public enum QueryIntent: String, CaseIterable, Identifiable, Sendable {
    case define = "Define"
    case synonyms = "Synonyms"
    case translation = "Translation"
    case slang = "Slang"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .define: return "book"
        case .synonyms: return "arrow.triangle.2.circlepath"
        case .translation: return "globe"
        case .slang: return "bubble.left.and.bubble.right"
        }
    }
}
