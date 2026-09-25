import Foundation

/// An opt-in, isolated preference domain for testing the signed application.
/// A UUID prevents a test launch from selecting an unrelated application's domain.
public enum DictionaryPreferences {
    public static let current: UserDefaults = {
        guard let profile = UserDefaults.standard.string(forKey: "MongrelVerificationProfile") else {
            return .standard
        }
        guard UUID(uuidString: profile) != nil,
              let defaults = UserDefaults(suiteName: "com.mongrel.dictionary.verification.\(profile)") else {
            preconditionFailure("MongrelVerificationProfile must be a UUID")
        }
        return defaults
    }()
}
