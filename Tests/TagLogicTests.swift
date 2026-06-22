import XCTest
@testable import BabyBuddy

final class TagLogicTests: XCTestCase {
    // MARK: add / merge

    func testAddTrimsWhitespace() {
        XCTAssertEqual(TagLogic.add("  hungry  ", to: []), ["hungry"])
    }

    func testAddIgnoresEmpty() {
        XCTAssertEqual(TagLogic.add("   ", to: ["a"]), ["a"])
    }

    func testAddDeduplicatesCaseInsensitively() {
        XCTAssertEqual(TagLogic.add("Hungry", to: ["hungry"]), ["hungry"])
        XCTAssertEqual(TagLogic.add("night", to: ["day"]), ["day", "night"])
    }

    // MARK: suggestions

    func testSuggestionsSubstringMatchExcludesSelected() {
        let all = ["hungry", "night", "fussy", "milestone"]
        let result = TagLogic.suggestions(query: "ni", all: all, selected: ["night"])
        XCTAssertFalse(result.contains("night"))      // already selected
    }

    func testSuggestionsPrefixRanksFirst() {
        let all = ["midnight", "night"]               // both contain "night"
        let result = TagLogic.suggestions(query: "night", all: all, selected: [])
        XCTAssertEqual(result.first, "night")          // prefix match ranks above substring
    }

    func testEmptyQueryReturnsAllUnselected() {
        let all = ["a", "b", "c"]
        let result = TagLogic.suggestions(query: "", all: all, selected: ["b"])
        XCTAssertEqual(Set(result), Set(["a", "c"]))
    }

    func testSuggestionsRespectLimit() {
        let all = (0..<20).map { "tag\($0)" }
        XCTAssertEqual(TagLogic.suggestions(query: "tag", all: all, selected: [], limit: 5).count, 5)
    }

    // MARK: canCreate

    func testCanCreateNewName() {
        XCTAssertTrue(TagLogic.canCreate(query: "brandnew", all: ["hungry"], selected: []))
    }

    func testCannotCreateExistingNameCaseInsensitive() {
        XCTAssertFalse(TagLogic.canCreate(query: "Hungry", all: ["hungry"], selected: []))
        XCTAssertFalse(TagLogic.canCreate(query: "Night", all: [], selected: ["night"]))
    }

    func testCannotCreateEmpty() {
        XCTAssertFalse(TagLogic.canCreate(query: "  ", all: [], selected: []))
    }

    // MARK: color helpers

    func testTextColorUsesYIQContrast() {
        // Light yellow background → dark text; dark blue → light text.
        XCTAssertEqual(TagColor.textColor(forHex: "#ffff7f"), TagColor.textColor(forHex: "#ffffff"))
        XCTAssertEqual(TagColor.textColor(forHex: "#00007f"), TagColor.textColor(forHex: "#000000"))
        XCTAssertNotEqual(TagColor.textColor(forHex: "#ffffff"), TagColor.textColor(forHex: "#000000"))
    }

    func testColorFromHexMalformedFallsBackToDefault() {
        XCTAssertEqual(TagColor.color(forHex: "not-a-color"), TagColor.color(forHex: TagColor.defaultHex))
    }
}
