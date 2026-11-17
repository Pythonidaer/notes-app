import XCTest

@MainActor
final class NoteAutosaveTests: XCTestCase {
    func testUndoWithinTheDebounceReopensTheSavedText() async throws {
        try await withDisposableNote(title: "A", html: "<p>A</p>") { database, stored in
            let autosave = NoteAutosave()
            autosave.delay = .milliseconds(150)
            let save = persist(database)

            autosave.editorChanged(title: "B", html: "<p>B</p>", note: stored, save: save)
            let stillStored = try database.note(id: stored.id)
            XCTAssertEqual(stillStored.bodyHTML, "<p>A</p>")
            autosave.editorChanged(title: "A", html: "<p>A</p>", note: stillStored, save: save)

            try await Task.sleep(for: .milliseconds(400))
            let reopened = try database.note(id: stored.id)
            XCTAssertEqual(reopened.title, "A")
            XCTAssertEqual(reopened.bodyHTML, "<p>A</p>")
        }
    }

    func testTypingThenUndoInTheEditorReopensTheSavedText() async throws {
        let session = EditorSession()
        let webView = try await session.load(session.page)
        try await session.evaluate(
            "window.notesEditor.setNote(\(try session.json("A")), \(try session.json("<p>A</p>")))",
            in: webView
        )
        let savedTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
        let savedHTML = try await session.string("window.notesEditor.getHTML()", in: webView)

        try await withDisposableNote(title: savedTitle, html: savedHTML) { database, stored in
            try await session.evaluate("window.notesEditor.insertText(\"B\")", in: webView)
            let typedTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
            let typedHTML = try await session.string("window.notesEditor.getHTML()", in: webView)
            XCTAssertTrue(
                typedTitle != savedTitle || typedHTML != savedHTML,
                "Typing did not change the note."
            )

            let autosave = NoteAutosave()
            autosave.delay = .seconds(1)
            let save = persist(database)
            autosave.editorChanged(title: typedTitle, html: typedHTML, note: stored, save: save)

            try await session.evaluate("window.notesEditor.undo()", in: webView)
            let undoneTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
            let undoneHTML = try await session.string("window.notesEditor.getHTML()", in: webView)
            XCTAssertEqual(undoneTitle, savedTitle)
            XCTAssertEqual(undoneHTML, savedHTML)

            let stillStored = try database.note(id: stored.id)
            XCTAssertEqual(stillStored.bodyHTML, savedHTML)
            autosave.editorChanged(title: undoneTitle, html: undoneHTML, note: stillStored, save: save)

            try await Task.sleep(for: .milliseconds(1500))
            let reopened = try database.note(id: stored.id)
            XCTAssertEqual(reopened.title, savedTitle)
            XCTAssertEqual(reopened.bodyHTML, savedHTML)
        }
    }

    func testTypingInTheEditorPersistsAfterTheDebounce() async throws {
        let session = EditorSession()
        let webView = try await session.load(session.page)
        try await session.evaluate(
            "window.notesEditor.setNote(\(try session.json("A")), \(try session.json("<p>A</p>")))",
            in: webView
        )
        let savedTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
        let savedHTML = try await session.string("window.notesEditor.getHTML()", in: webView)
        try await withDisposableNote(title: savedTitle, html: savedHTML) { database, stored in
            try await session.evaluate("window.notesEditor.insertText(\"B\")", in: webView)
            let typedTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
            let typedHTML = try await session.string("window.notesEditor.getHTML()", in: webView)
            XCTAssertTrue(typedTitle != savedTitle || typedHTML != savedHTML)

            let autosave = NoteAutosave()
            autosave.delay = .milliseconds(200)
            autosave.editorChanged(
                title: typedTitle,
                html: typedHTML,
                note: stored,
                save: persist(database)
            )
            try await Task.sleep(for: .milliseconds(500))
            let reopened = try database.note(id: stored.id)
            XCTAssertEqual(reopened.title, typedTitle)
            XCTAssertEqual(reopened.bodyHTML, typedHTML)
        }
    }

    func testAnOrdinaryEditPersistsAfterTheDebounce() async throws {
        XCTAssertEqual(NoteAutosave().delay, .milliseconds(600))
        try await withDisposableNote(title: "A", html: "<p>A</p>") { database, stored in
            let autosave = NoteAutosave()
            autosave.delay = .milliseconds(150)

            autosave.editorChanged(title: "B", html: "<p>B</p>", note: stored, save: persist(database))
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(try database.note(id: stored.id).bodyHTML, "<p>A</p>")

            try await Task.sleep(for: .milliseconds(300))
            let reopened = try database.note(id: stored.id)
            XCTAssertEqual(reopened.title, "B")
            XCTAssertEqual(reopened.bodyHTML, "<p>B</p>")
        }
    }

    /// Opens a disposable library, runs `body`, closes the database, then deletes the file.
    private func withDisposableNote(
        title: String,
        html: String,
        _ body: (LibraryDatabase, NoteDetail) async throws -> Void
    ) async throws {
        let (url, _) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        try await useNote(at: url, title: title, html: html, body)
    }

    private func useNote(
        at url: URL,
        title: String,
        html: String,
        _ body: (LibraryDatabase, NoteDetail) async throws -> Void
    ) async throws {
        let database = try LibraryDatabase.open(file: url)
        let created = try database.createNote(folderID: nil)
        let note = try database.saveNote(
            id: created.id,
            title: title,
            bodyHTML: html,
            createdAtSource: created.createdAtSource
        )
        try await body(database, note)
    }

    private func persist(
        _ database: LibraryDatabase
    ) -> @MainActor (String, String, String, String) -> Void {
        { id, title, bodyHTML, createdAtSource in
            _ = try? database.saveNote(
                id: id,
                title: title,
                bodyHTML: bodyHTML,
                createdAtSource: createdAtSource
            )
        }
    }
}
