import XCTest
@testable import MongrelDictionaryCore

final class DictionaryRegionalCoverageSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .referenceNotes }

    func testReferenceNotesIncludeOxfordAndHistoricalScotsSources() async {
        let repository = await makeRepository()

        let commonwealthCards = await repository.search(term: "lorry", intent: .define)
        XCTAssertTrue(
            commonwealthCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("large motor vehicle") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "truck" })
            }),
            "Expected a Commonwealth English note for 'lorry'."
        )

        let oxfordCards = await repository.search(term: "dab hand", intent: .define)
        XCTAssertTrue(
            oxfordCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("notably skilful")
            }),
            "Expected an Oxford-backed British usage note for 'dab hand'."
        )

        let jamiesonCards = await repository.search(term: "daberlack", intent: .define)
        XCTAssertTrue(
            jamiesonCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("long strip of seaweed")
            }),
            "Expected a Jamieson-backed historical Scots note for 'daberlack'."
        )
    }

    func testReferenceNotesIncludeNorthAmericanCounterparts() async {
        let repository = await makeRepository()

        let truckCards = await repository.search(term: "truck", intent: .define)
        XCTAssertTrue(
            truckCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("motor vehicle for carrying goods") &&
                $0.counterparts.contains(where: { $0.label == "Commonwealth counterpart" && $0.term == "lorry" })
            }),
            "Expected a North American counterpart note for 'truck'."
        )

        let diaperCards = await repository.search(term: "diaper", intent: .define)
        XCTAssertTrue(
            diaperCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("baby's absorbent garment")
            }),
            "Expected a North American counterpart note for 'diaper'."
        )
    }

    func testReferenceNotesIncludeAustralianEnglishSources() async {
        let repository = await makeRepository()

        let bottleoCards = await repository.search(term: "bottleo", intent: .define)
        XCTAssertTrue(
            bottleoCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "bottle-o" &&
                $0.summary.localizedCaseInsensitiveContains("shop that sells alcohol") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "liquor store" })
            }),
            "Expected an Australian English note for 'bottle-o', reachable through the 'bottleo' alias."
        )

        let uteCards = await repository.search(term: "ute", intent: .define)
        XCTAssertTrue(
            uteCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("light utility vehicle") &&
                $0.counterparts.contains(where: { $0.label == "South African counterpart" && $0.term == "bakkie" })
            }),
            "Expected an Australian English note for 'ute' with a South African counterpart."
        )
    }

    func testReferenceNotesIncludeSouthAfricanEnglishSources() async {
        let repository = await makeRepository()

        let robotCards = await repository.search(term: "robot", intent: .define)
        XCTAssertTrue(
            robotCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("traffic light") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "traffic light" })
            }),
            "Expected a South African English note for 'robot'."
        )

        let bakkieCards = await repository.search(term: "bakkies", intent: .define)
        XCTAssertTrue(
            bakkieCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "bakkie" &&
                $0.summary.localizedCaseInsensitiveContains("pickup-style vehicle") &&
                $0.counterparts.contains(where: { $0.label == "Australian counterpart" && $0.term == "ute" })
            }),
            "Expected alias lookup to reach the South African English note for 'bakkie'."
        )
    }

    func testReferenceNotesIncludeNewZealandEnglishSources() async {
        let repository = await makeRepository()

        let jandalCards = await repository.search(term: "jandals", intent: .define)
        XCTAssertTrue(
            jandalCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "jandal" &&
                $0.summary.localizedCaseInsensitiveContains("flip-flops") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "flip-flops" })
            }),
            "Expected alias lookup to reach the New Zealand English note for 'jandal'."
        )

        let whanauCards = await repository.search(term: "whanau", intent: .define)
        XCTAssertTrue(
            whanauCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("extended family")
            }),
            "Expected a New Zealand English note for 'whanau'."
        )
    }

    func testReferenceNotesIncludeCanadianEnglishSources() async {
        let repository = await makeRepository()

        let tuqueCards = await repository.search(term: "tuque", intent: .define)
        XCTAssertTrue(
            tuqueCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "tuque" &&
                $0.summary.localizedCaseInsensitiveContains("knitted winter hat") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "beanie" })
            }),
            "Expected a Canadian English form entry for 'tuque'."
        )

        let hydroCards = await repository.search(term: "hydro", intent: .define)
        XCTAssertTrue(
            hydroCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("electricity service")
            }),
            "Expected a Canadian English note for 'hydro'."
        )
    }

    func testReferenceNotesIncludeIrishEnglishSources() async {
        let repository = await makeRepository()

        let gardaiCards = await repository.search(term: "Gardai", intent: .define)
        XCTAssertTrue(
            gardaiCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "Gardai" &&
                $0.summary.localizedCaseInsensitiveContains("national police service") &&
                $0.counterparts.contains(where: { $0.label == "Approximate counterpart" && $0.term == "police officers" })
            }),
            "Expected a real Irish English form entry for 'Gardai'."
        )

        let taoiseachCards = await repository.search(term: "Taoiseach", intent: .define)
        XCTAssertTrue(
            taoiseachCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("head of government") &&
                $0.counterparts.contains(where: { $0.label == "Approximate counterpart" && $0.term == "prime minister" })
            }),
            "Expected an Irish English public-life note for 'Taoiseach'."
        )
    }

    func testReferenceNotesExposeStructuredCrossDialectLinks() async {
        let repository = await makeRepository()

        let lorryCards = await repository.search(term: "lorry", intent: .define)
        XCTAssertTrue(
            lorryCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.relatedTerms.contains("ute") &&
                $0.relatedTerms.contains("bakkie")
            }),
            "Expected structured related-term links from 'lorry' into Australian and South African transport vocabulary."
        )

        let washroomCards = await repository.search(term: "washroom", intent: .define)
        XCTAssertTrue(
            washroomCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.relatedTerms.contains("loo")
            }),
            "Expected structured related-term links from 'washroom' to other English-country bathroom vocabulary."
        )
    }
}
