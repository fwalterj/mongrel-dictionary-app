import XCTest
@testable import MongrelDictionaryCore

final class DictionaryLongmanCoverageSmokeTests: DictionarySmokeTestCase {
    override class var prewarmProfile: DictionaryRepository.PrewarmProfile { .referenceNotes }

    func testReferenceNotesIncludeLongmanAndExpandedComparativeCoverage() async {
        let repository = await makeRepository()

        let acidTestCards = await repository.search(term: "acid test", intent: .define)
        XCTAssertTrue(
            acidTestCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("decisive trial or proof")
            }),
            "Expected a Longman-derived phrase note for 'acid test'."
        )

        let hemAndHawCards = await repository.search(term: "hem and haw", intent: .define)
        XCTAssertTrue(
            hemAndHawCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("hesitate") &&
                $0.summary.localizedCaseInsensitiveContains("clear answer")
            }),
            "Expected a Longman-derived phrase note for 'hem and haw'."
        )

        let chemistCards = await repository.search(term: "chemist", intent: .define)
        XCTAssertTrue(
            chemistCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("pharmacy or drugstore") &&
                $0.counterparts.contains(where: { $0.label == "North American counterpart" && $0.term == "drugstore" })
            }),
            "Expected expanded Commonwealth retail vocabulary for 'chemist'."
        )

        let parkadeCards = await repository.search(term: "parkade", intent: .define)
        XCTAssertTrue(
            parkadeCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("parking garage")
            }),
            "Expected expanded Canadian transport/public-space vocabulary for 'parkade'."
        )

        let craicCards = await repository.search(term: "craic", intent: .define)
        XCTAssertTrue(
            craicCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("shared amusement")
            }),
            "Expected expanded Irish social vocabulary for 'craic'."
        )

        let eightBallCards = await repository.search(term: "behind the eight ball", intent: .define)
        XCTAssertTrue(
            eightBallCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("disadvantaged position")
            }),
            "Expected a Longman-derived phrase note for 'behind the eight ball'."
        )

        let branchOutCards = await repository.search(term: "branch out", intent: .define)
        XCTAssertTrue(
            branchOutCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("widen your activities")
            }),
            "Expected a Longman-derived phrase note for 'branch out'."
        )

        let coffeeBreakCards = await repository.search(term: "coffee break", intent: .define)
        XCTAssertTrue(
            coffeeBreakCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("short pause in work")
            }),
            "Expected a Longman-derived phrase note for 'coffee break'."
        )

        let offTheCuffCards = await repository.search(term: "off the cuff", intent: .define)
        XCTAssertTrue(
            offTheCuffCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("without preparation")
            }),
            "Expected a Longman-derived phrase note for 'off the cuff'."
        )

        let coldComfortCards = await repository.search(term: "cold comfort", intent: .define)
        XCTAssertTrue(
            coldComfortCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("little real reassurance")
            }),
            "Expected a Longman-derived phrase note for 'cold comfort'."
        )

        let coffeeTableBookCards = await repository.search(term: "coffee-table book", intent: .define)
        XCTAssertTrue(
            coffeeTableBookCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("visually impressive book")
            }),
            "Expected a Longman-derived phrase note for 'coffee-table book'."
        )

        let takeCognizanceCards = await repository.search(term: "take cognizance of", intent: .define)
        XCTAssertTrue(
            takeCognizanceCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("serious consideration") &&
                $0.summary.localizedCaseInsensitiveContains("official attention")
            }),
            "Expected a Longman-derived phrase note for 'take cognizance of'."
        )

        let leftOutInTheColdCards = await repository.search(term: "left out in the cold", intent: .define)
        XCTAssertTrue(
            leftOutInTheColdCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("ignored") &&
                $0.summary.localizedCaseInsensitiveContains("excluded")
            }),
            "Expected a Longman-derived phrase note for 'left out in the cold'."
        )

        let cupOfTeaCards = await repository.search(term: "not my cup of tea", intent: .define)
        XCTAssertTrue(
            cupOfTeaCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "one's cup of tea" &&
                $0.summary.localizedCaseInsensitiveContains("suits one's taste")
            }),
            "Expected alias lookup to reach the Longman-derived phrase note for 'one's cup of tea'."
        )

        let culDeSacCards = await repository.search(term: "cul de sac", intent: .define)
        XCTAssertTrue(
            culDeSacCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "cul-de-sac" &&
                $0.summary.localizedCaseInsensitiveContains("closed at one end")
            }),
            "Expected alias lookup to reach the Longman-derived note for 'cul-de-sac'."
        )

        let coldBloodedCards = await repository.search(term: "cold blooded", intent: .define)
        XCTAssertTrue(
            coldBloodedCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.title == "cold-blooded" &&
                $0.summary.localizedCaseInsensitiveContains("callous")
            }),
            "Expected alias lookup to reach the Longman-derived note for 'cold-blooded'."
        )

        let withoutDemurCards = await repository.search(term: "without demur", intent: .define)
        XCTAssertTrue(
            withoutDemurCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("without objection")
            }),
            "Expected a Longman-derived phrase note for 'without demur'."
        )

        let cupboardLoveCards = await repository.search(term: "cupboard love", intent: .define)
        XCTAssertTrue(
            cupboardLoveCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("hope of getting some reward")
            }),
            "Expected a Longman-derived phrase note for 'cupboard love'."
        )

        let bufferStateCards = await repository.search(term: "buffer state", intent: .define)
        XCTAssertTrue(
            bufferStateCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("smaller independent country") &&
                $0.summary.localizedCaseInsensitiveContains("hostile powers")
            }),
            "Expected a Longman-derived phrase note for 'buffer state'."
        )

        let faceTheMusicCards = await repository.search(term: "face the music", intent: .define)
        XCTAssertTrue(
            faceTheMusicCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("accept the unpleasant consequences")
            }),
            "Expected a Longman-derived phrase note for 'face the music'."
        )

        let readBetweenTheLinesCards = await repository.search(term: "read between the lines", intent: .define)
        XCTAssertTrue(
            readBetweenTheLinesCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("infer") &&
                $0.summary.localizedCaseInsensitiveContains("not stated openly")
            }),
            "Expected a Longman-derived phrase note for 'read between the lines'."
        )

        let inGoodFaithCards = await repository.search(term: "in good faith", intent: .define)
        XCTAssertTrue(
            inGoodFaithCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("honestly") &&
                $0.summary.localizedCaseInsensitiveContains("sincere intent")
            }),
            "Expected a Longman-derived phrase note for 'in good faith'."
        )

        let ruleOfThumbCards = await repository.search(term: "rule of thumb", intent: .define)
        XCTAssertTrue(
            ruleOfThumbCards.contains(where: {
                $0.source == "Mongrel reference notes" &&
                $0.summary.localizedCaseInsensitiveContains("practical guide") &&
                $0.summary.localizedCaseInsensitiveContains("rough")
            }),
            "Expected a Longman-derived phrase note for 'rule of thumb'."
        )
    }
}
