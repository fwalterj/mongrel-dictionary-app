import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLookupRequestTests: XCTestCase {
    func testCoreDeepLinkUsesTheSameValidatedRequestParsing() throws {
        let url = try XCTUnwrap(URL(string: "mongrel-dictionary-core://lookup?term=bank&intent=synonyms"))
        XCTAssertEqual(DictionaryLookupRequest(url: url), DictionaryLookupRequest(term: "bank", intent: .synonyms))
    }
    func testNormalizesSelectedTextForServiceLookup() throws {
        let request = try XCTUnwrap(DictionaryLookupRequest(term: "  state\n  of   the art  "))
        XCTAssertEqual(request.term, "state of the art")
        XCTAssertEqual(request.intent, .define)
    }

    func testRoundTripsDeepLinkWithIntent() throws {
        let original = try XCTUnwrap(DictionaryLookupRequest(term: "fair dinkum", intent: .slang))
        let url = try XCTUnwrap(original.url)
        let decoded = try XCTUnwrap(DictionaryLookupRequest(url: url))
        XCTAssertEqual(decoded, original)
    }

    func testAcceptsCompactQueryAliasAndDefaultsToDefine() throws {
        let url = try XCTUnwrap(URL(string: "mongrel-dictionary://lookup?q=palimpsest"))
        let request = try XCTUnwrap(DictionaryLookupRequest(url: url))
        XCTAssertEqual(request.term, "palimpsest")
        XCTAssertEqual(request.intent, .define)
    }

    func testRejectsForeignSchemesAndEmptyTerms() {
        XCTAssertNil(DictionaryLookupRequest(url: URL(string: "https://example.com/?term=word")!))
        XCTAssertNil(DictionaryLookupRequest(term: " \n "))
    }
}
