import XCTest
import SwiftTreeSitter
import TreeSitterFerrule

final class TreeSitterFerruleTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_ferrule())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading ferrule grammar")
    }
}
