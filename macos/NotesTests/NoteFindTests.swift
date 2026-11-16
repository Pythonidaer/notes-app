import XCTest

final class NoteFindTests: XCTestCase {
    private let session = EditorSession()

    @MainActor
    func testFindReplaceKeepsTheNewTextAndClearsHighlights() async throws {
        let webView = try await session.load(session.page)
        let html = "<p>A haircut and my hair and this hairline.</p>"
        try await session.evaluate(
            "window.notesEditor.setNote(\"Barber\", \(try session.json(html)))",
            in: webView
        )
        let found = try await session.string("window.notesEditor.find(\"hair\")", in: webView)
        XCTAssertTrue(found.contains("\"count\":3"), found)
        let highlighted = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(highlighted.contains("find-match"), highlighted)
        XCTAssertTrue(highlighted.contains("haircut"), highlighted)

        _ = try await session.string("window.notesEditor.findNext()", in: webView)
        _ = try await session.string("window.notesEditor.findPrevious()", in: webView)
        let once = try await session.string("window.notesEditor.replaceCurrent(\"wig\")", in: webView)
        XCTAssertTrue(once.contains("\"count\":2"), once)
        let afterOne = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(afterOne.contains("wigcut"), afterOne)

        _ = try await session.string("window.notesEditor.replaceAll(\"fur\")", in: webView)
        try await session.evaluate("window.notesEditor.clearFind()", in: webView)
        let saved = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(saved.contains("wigcut"), saved)
        XCTAssertTrue(saved.contains("fur"), saved)
        XCTAssertFalse(saved.localizedCaseInsensitiveContains("hair"), saved)
        XCTAssertFalse(saved.contains("find-match"), saved)
    }
}
