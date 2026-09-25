import Foundation

public struct DictionaryLookupRequest: Equatable, Sendable {
    public static let urlScheme = "mongrel-dictionary"
    public static let maximumTermLength = 240

    public let term: String
    public let intent: QueryIntent

    public init?(term: String, intent: QueryIntent = .define) {
        guard let normalizedTerm = Self.normalizedTerm(term) else { return nil }
        self.term = normalizedTerm
        self.intent = intent
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let queryTerm = queryItems.first(where: { item in
            item.name.caseInsensitiveCompare("term") == .orderedSame ||
                item.name.caseInsensitiveCompare("q") == .orderedSame
        })?.value
        let pathTerm = components.path
            .split(separator: "/")
            .first
            .map(String.init)
        let hostTerm = components.host.flatMap { host -> String? in
            host.caseInsensitiveCompare("lookup") == .orderedSame ? nil : host
        }

        guard let normalizedTerm = Self.normalizedTerm(queryTerm ?? pathTerm ?? hostTerm ?? "") else {
            return nil
        }

        let rawIntent = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("intent") == .orderedSame
        })?.value

        term = normalizedTerm
        intent = Self.resolveIntent(rawIntent) ?? .define
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = "lookup"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "intent", value: intent.rawValue.lowercased())
        ]
        return components.url
    }

    public static func normalizedTerm(_ rawValue: String) -> String? {
        let collapsed = rawValue
            .precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumTermLength))
    }

    private static func resolveIntent(_ rawValue: String?) -> QueryIntent? {
        guard let rawValue else { return nil }
        return QueryIntent.allCases.first {
            $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame
        }
    }
}
