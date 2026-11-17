import XCTest

final class OpenNoteWindowsTests: XCTestCase {
    func testOpenNoteWindowReusesTheSameNoteAndClosesWhenItDisappears() {
        var windows = OpenNoteWindows()
        let library = ["one", "two"]

        XCTAssertEqual(windows.open(noteID: "missing", availableIDs: library), .missing)
        XCTAssertTrue(windows.noteIDs.isEmpty)

        XCTAssertEqual(windows.open(noteID: "one", availableIDs: library), .present("one"))
        XCTAssertEqual(windows.open(noteID: "one", availableIDs: library), .alreadyOpen("one"))
        XCTAssertEqual(windows.noteIDs, ["one"])

        XCTAssertEqual(windows.open(noteID: "two", availableIDs: library), .present("two"))
        XCTAssertEqual(windows.noteIDs, ["one", "two"])

        windows.close(noteID: "one")
        XCTAssertEqual(windows.noteIDs, ["two"])
        XCTAssertEqual(windows.open(noteID: "one", availableIDs: library), .present("one"))

        let closed = windows.closeNotesMissing(from: ["one"])
        XCTAssertEqual(closed, ["two"])
        XCTAssertEqual(windows.noteIDs, ["one"])

        XCTAssertEqual(OpenNoteWindows.title(for: ""), "New Note")
        XCTAssertEqual(OpenNoteWindows.title(for: "   "), "New Note")
        XCTAssertEqual(OpenNoteWindows.title(for: "Off limits material"), "Off limits material")
    }

    func testEditorKeepsLocalTypingAndShowsTheOtherWindowsSave() {
        var sync = NoteEditorSync()
        XCTAssertNil(sync.noteToApply(storedTitle: "A", storedHTML: "<p>A</p>"))

        sync.didLoad(title: "A", html: "<p>A</p>")
        XCTAssertNil(sync.noteToApply(storedTitle: "A", storedHTML: "<p>A</p>"))

        sync.didEdit(title: "AB", html: "<p>AB</p>")
        XCTAssertNil(sync.noteToApply(storedTitle: "A", storedHTML: "<p>A</p>"))
        XCTAssertNil(sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>"))

        XCTAssertNil(sync.noteToApply(storedTitle: "AB", storedHTML: "<p>AB</p>"))
        let incoming = sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>")
        XCTAssertEqual(incoming?.title, "Other")
        XCTAssertEqual(incoming?.html, "<p>Other</p>")
        XCTAssertNil(sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>"))

        sync.didFailToLoad()
        XCTAssertEqual(sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>")?.title, "Other")
        sync.didLoad(title: "Other", html: "<p>Other</p>")
        XCTAssertNil(sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>"))

        sync.didEdit(title: "Other ", html: "<p>Other</p>")
        XCTAssertNil(sync.noteToApply(storedTitle: "Other", storedHTML: "<p>Other</p>"))
        XCTAssertEqual(sync.noteToApply(storedTitle: "Next", storedHTML: "<p>Next</p>")?.title, "Next")
    }
}
