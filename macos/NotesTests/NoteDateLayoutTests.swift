import XCTest

@MainActor
final class NoteDateLayoutTests: XCTestCase {
    private let session = EditorSession()

    func testDateScrollsAboveTheTitleAndUndoRestoresTheNote() async throws {
        let webView = try await session.load(session.page)
        let body = (0..<40).map { "<p>Line \($0)</p>" }.joined()
        let heading = "July 31, 2025 at 7:09 PM"
        let load = "window.notesEditor.setNote(\(try session.json("Goals")), "
            + "\(try session.json(body)), \(try session.json(heading)))"
        try await session.evaluate(load, in: webView)
        let saved = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(saved.contains(heading))
        try await Task.sleep(nanoseconds: 700_000_000)
        try await session.evaluate("window.notesEditor.insertText(\"X\")", in: webView)
        try await session.evaluate("window.notesEditor.undo()", in: webView)
        let title = try await session.string("window.notesEditor.getTitle()", in: webView)
        XCTAssertEqual(title, "Goals")
        let layout = try await session.string(dateProbe, in: webView)
        XCTAssertEqual(layout, "ok")
    }
}

private let dateProbe = "(()=>{const d=document.querySelector('#note-date');"
    + "const t=document.querySelector('[data-note-title]');const s=getComputedStyle(d);"
    + "const y=d.getBoundingClientRect().top;document.scrollingElement.scrollTop=240;"
    + "const moved=d.getBoundingClientRect().top<y;const first=(d.compareDocumentPosition(t)&4)!==0;"
    + "return d.textContent==='July 31, 2025 at 7:09 PM'&&s.textAlign==='center'&&s.fontSize==='11px'"
    + "&&s.fontWeight==='400'&&first&&moved&&window.notesEditor.selectText('Line 3')?'ok':'no';})()"
