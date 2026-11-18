import XCTest

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var url: URL!
    private var store: LibraryStore!
    private var first: NoteDetail!
    private var unreadable: NoteDetail!
    private var other: NoteDetail!

    override func setUp() async throws {
        let (url, database) = try Fixture.importedLibrary()
        self.url = url
        first = try database.createNote(folderID: nil)
        unreadable = try database.createNote(folderID: nil)
        other = try database.createNote(folderID: nil)
        store = LibraryStore()
        store.load(file: url)
        XCTAssertNil(store.loadError)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: url)
    }

    func testFailedSelectionKeepsPreviousNote() throws {
        XCTAssertTrue(store.selectNote(first.id))
        // The list still shows the note, but its row is gone, so reading it fails.
        try Fixture.write(url, "DELETE FROM notes WHERE id = '\(unreadable.id)';")
        XCTAssertTrue(store.notes.contains { $0.id == unreadable.id })

        XCTAssertFalse(store.selectNote(unreadable.id))

        XCTAssertEqual(store.selectedNoteID, first.id)
        XCTAssertEqual(store.openNote?.id, first.id)
        XCTAssertFalse(store.status.isEmpty)
        XCTAssertFalse(store.isLoadingNote)
    }

    func testSelectingAnotherNoteOpensIt() {
        XCTAssertTrue(store.selectNote(first.id))

        XCTAssertTrue(store.selectNote(other.id))

        XCTAssertEqual(store.selectedNoteID, other.id)
        XCTAssertEqual(store.openNote?.id, other.id)
        XCTAssertEqual(store.status, "")
        XCTAssertFalse(store.isLoadingNote)
    }

    func testSavingRefreshesOnlyThatNotesSummaryAndSearch() throws {
        store.saveNote(id: other.id, title: "Groceries", bodyHTML: "<p>Pineapple and rye</p>", createdAtSource: "")
        let unrelated = try XCTUnwrap(store.notes.first { $0.id == other.id })
        try Fixture.write(url, """
        INSERT INTO audio_display_names (storage_path, display_name, updated_at)
        VALUES ('user/clip.mp3', 'Closer bit', '2020-01-01T00:00:00Z');
        """)
        let body = """
        <p>Banana opener</p><ul data-type="taskList"><li data-type="taskItem"><p>tag</p></li></ul>\
        <figure data-nn-storage-path="user/clip.mp3" data-nn-file-name="clip.mp3" class="nn-audio-embed"></figure>
        """

        store.saveNote(id: first.id, title: " Set list ", bodyHTML: body, createdAtSource: "2024-05-01T09:00:00Z")

        XCTAssertEqual(store.status, "")
        XCTAssertEqual(store.notes.first?.id, first.id)
        let edited = try XCTUnwrap(store.notes.first { $0.id == first.id })
        XCTAssertEqual(edited.title, "Set list")
        XCTAssertEqual(edited.createdAtSource, "2024-05-01T09:00:00Z")
        XCTAssertEqual(edited.modifiedAtSource, first.modifiedAtSource)
        XCTAssertTrue(edited.opening.hasPrefix("Banana opener"))
        XCTAssertTrue(edited.hasChecklist)
        XCTAssertTrue(edited.hasAttachment)
        XCTAssertEqual(store.notes.first { $0.id == other.id }, unrelated)
        let fullReload = try LibraryDatabase.open(file: url).loadLibrarySnapshot()
        XCTAssertEqual(Set(store.notes), Set(fullReload.notes))

        store.searchText = "banana"
        XCTAssertEqual(store.notesMatchingSearch().map(\.id), [first.id])
        store.searchText = "closer bit"
        XCTAssertEqual(store.notesMatchingSearch().map(\.id), [first.id])
        store.searchText = "pineapple"
        XCTAssertEqual(store.notesMatchingSearch().map(\.id), [other.id])
        store.searchText = ""
        store.searchScope = .checklists
        XCTAssertEqual(store.notesMatchingSearch().map(\.id), [first.id])
        store.searchScope = .attachments
        XCTAssertEqual(store.notesMatchingSearch().map(\.id), [first.id])
    }
}
