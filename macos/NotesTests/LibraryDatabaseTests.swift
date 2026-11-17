import XCTest

final class LibraryDatabaseTests: XCTestCase {
    func testMissingFileIsNotCreated() {
        let url = Fixture.temporaryURL()
        XCTAssertThrowsError(try LibraryDatabase.open(file: url)) { error in
            XCTAssertEqual(error as? LibraryError, .missingDatabase)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOpenRefusesLabelTablesAndDoesNotMigrate() throws {
        let url = Fixture.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Fixture.write(
            url,
            Fixture.baseSQL + """
            CREATE TABLE labels (id TEXT PRIMARY KEY);
            CREATE TABLE note_labels (note_id TEXT, label_id TEXT);
            """
        )
        let before = try Fixture.tableNames(url)
        XCTAssertThrowsError(try LibraryDatabase.open(file: url)) { error in
            XCTAssertEqual(error as? LibraryError, .legacyLabels)
        }
        XCTAssertEqual(try Fixture.tableNames(url), before)
    }

    func testOpenRefusesALibraryThatWasNotImported() throws {
        let url = Fixture.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Fixture.write(url, "CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);")
        let before = try Fixture.tableNames(url)
        XCTAssertThrowsError(try LibraryDatabase.open(file: url)) { error in
            XCTAssertEqual(error as? LibraryError, .notImported)
        }
        XCTAssertEqual(try Fixture.tableNames(url), before)
    }

    func testLiveLibraryOpensWithoutChangingTables() throws {
        let url = LibraryDatabase.libraryURL
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        let before = try Fixture.tableNames(url)
        let database = try LibraryDatabase.open(file: url)
        let library = try database.library()
        XCTAssertTrue(library.folders.contains { $0.id == LibraryDatabase.comedyFolderID })
        XCTAssertFalse(library.notes.isEmpty)
        XCTAssertEqual(try Fixture.tableNames(url), before)
        XCTAssertFalse(before.contains("labels"))
        XCTAssertFalse(before.contains("note_labels"))
    }

    func testNewNoteUsesComedyWhenNoFolderIsSelected() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let note = try database.createNote(folderID: nil)
        XCTAssertEqual(note.folderID, LibraryDatabase.comedyFolderID)
        XCTAssertEqual(note.bodyHTML, "<p></p>")
        XCTAssertEqual(note.title, "")
    }

    func testDuplicateNoteCopiesContentAndLeavesTheOriginal() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = try database.createFolder(name: "Draft")
        let created = try database.createNote(folderID: draft.id)
        let saved = try database.saveNote(
            id: created.id,
            title: "Set list",
            bodyHTML: "<p>Hello there</p>",
            createdAtSource: "Wednesday, June 3, 2026 at 8:10:03 PM"
        )
        let copy = try database.duplicateNote(id: saved.id)
        XCTAssertNotEqual(copy.id, saved.id)
        XCTAssertEqual(copy.title, "Set list")
        XCTAssertEqual(copy.bodyHTML, "<p>Hello there</p>")
        XCTAssertEqual(copy.folderID, draft.id)
        XCTAssertNotEqual(copy.createdAtSource, saved.createdAtSource)
        let original = try database.note(id: saved.id)
        XCTAssertEqual(original.title, saved.title)
        XCTAssertEqual(original.bodyHTML, saved.bodyHTML)
        XCTAssertEqual(original.createdAtSource, saved.createdAtSource)
        XCTAssertEqual(original.folderID, draft.id)
        XCTAssertEqual(try database.library().notes.filter { $0.title == "Set list" }.count, 2)
    }

    func testDuplicateNoteKeepsAnUnfiledNoteUnfiled() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let created = try database.createNote(folderID: nil)
        try database.performDrop(raw: "note:\(created.id)", on: .allNotes, zone: .child)
        let copy = try database.duplicateNote(id: created.id)
        XCTAssertNil(copy.folderID)
        XCTAssertNil(try database.note(id: created.id).folderID)
    }

    func testDuplicateNoteCopiesTheAudioFileAndLeavesTheOriginal() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-src-\(UUID().uuidString)", isDirectory: true)
        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-copy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        defer { try? FileManager.default.removeItem(at: copyRoot) }
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let clip = sourceRoot.appendingPathComponent("Confidence.mp3")
        let bytes = Data("audio-bytes".utf8)
        try bytes.write(to: clip)
        let created = try database.createNote(folderID: nil)
        let html = """
        <figure data-nn-storage-path="user/Confidence.mp3" data-nn-file-name="Confidence.mp3" \
        class="nn-audio-embed"></figure><p>Hello</p>
        """
        _ = try database.saveNote(
            id: created.id,
            title: "Set list",
            bodyHTML: html,
            createdAtSource: created.createdAtSource
        )
        try database.execute(
            "INSERT INTO audio_display_names (storage_path, display_name, updated_at) VALUES (?1, ?2, ?3)",
            [.text("user/Confidence.mp3"), .text("Stage whisper"), .text("2020-01-01T00:00:00Z")]
        )
        let copy = try database.duplicateNote(id: created.id, audioRoots: [sourceRoot], copyRoot: copyRoot)
        let clips = ReadingHTML.embeddedAudio(in: copy.bodyHTML)
        XCTAssertEqual(clips.count, 1)
        let newPath = clips[0].storagePath
        XCTAssertNotEqual(newPath, "user/Confidence.mp3")
        XCTAssertFalse(copy.bodyHTML.contains("user/Confidence.mp3"))
        XCTAssertEqual(try Data(contentsOf: copyRoot.appendingPathComponent(newPath)), bytes)
        XCTAssertEqual(try Data(contentsOf: clip), bytes)
        XCTAssertEqual(try database.note(id: created.id).bodyHTML, html)
        XCTAssertEqual(try database.displayName(storagePath: newPath), "Stage whisper")
        XCTAssertEqual(try database.displayName(storagePath: "user/Confidence.mp3"), "Stage whisper")
    }

    func testDuplicateNoteKeepsAMissingAudioPath() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-empty-\(UUID().uuidString)", isDirectory: true)
        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-copy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        defer { try? FileManager.default.removeItem(at: copyRoot) }
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let created = try database.createNote(folderID: nil)
        let html = #"<figure data-nn-storage-path="clip.mp3" class="nn-audio-embed"></figure>"#
        _ = try database.saveNote(
            id: created.id,
            title: "Set list",
            bodyHTML: html,
            createdAtSource: created.createdAtSource
        )
        let copy = try database.duplicateNote(id: created.id, audioRoots: [emptyRoot], copyRoot: copyRoot)
        XCTAssertEqual(copy.bodyHTML, html)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyRoot.path))
    }

    func testDeleteConfirmationMentionsAudioOnlyWhenTheNoteHasAClip() {
        let plain = NoteDetail(
            id: "plain",
            title: "",
            bodyHTML: "<p>Hi</p>",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil
        )
        XCTAssertEqual(plain.deleteConfirmationMessage, "Delete this note?")
        let clip = NoteDetail(
            id: "clip",
            title: "",
            bodyHTML: #"<figure data-nn-storage-path="clip.mp3" class="nn-audio-embed"></figure>"#,
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil
        )
        XCTAssertEqual(clip.deleteConfirmationMessage, "Delete this note? Audio files stay.")
    }

    func testDuplicateNoteRejectsAMissingNote() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try database.duplicateNote(id: "missing")) { error in
            XCTAssertEqual(error as? LibraryError, .message("That note is not in the library."))
        }
    }

    func testDropMovesANoteIntoAFolderAndAllNotesClearsIt() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = try database.createFolder(name: "Draft")
        let note = try database.createNote(folderID: draft.id)
        XCTAssertEqual(note.folderID, draft.id)
        try database.performDrop(
            raw: "note:\(note.id)",
            on: .folder(LibraryDatabase.comedyFolderID),
            zone: .before
        )
        XCTAssertEqual(try database.note(id: note.id).folderID, LibraryDatabase.comedyFolderID)
        try database.performDrop(raw: "note:\(note.id)", on: .allNotes, zone: .child)
        XCTAssertNil(try database.note(id: note.id).folderID)
    }

    func testFolderDropsReorderAndNestWithoutEnteringThemselves() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let alpha = try database.createFolder(name: "Alpha")
        let zeta = try database.createFolder(name: "Zeta")
        try database.performDrop(raw: "folder:\(zeta.id)", on: .folder(alpha.id), zone: .before)
        let rootIDs = try database.library().folders.filter { $0.parentID == nil }.map(\.id)
        XCTAssertEqual(rootIDs, [LibraryDatabase.comedyFolderID, zeta.id, alpha.id])

        try database.performDrop(raw: "folder:\(zeta.id)", on: .folder(alpha.id), zone: .child)
        let nested = try database.library().folders.first { $0.id == zeta.id }
        XCTAssertEqual(nested?.parentID, alpha.id)

        XCTAssertThrowsError(
            try database.performDrop(raw: "folder:\(alpha.id)", on: .folder(zeta.id), zone: .child)
        ) { error in
            XCTAssertEqual(error as? LibraryError, .message("A folder cannot move inside itself."))
        }
    }

    func testDeleteFolderDeletesNotesAndSubfolders() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let parent = try database.createFolder(name: "Parent")
        let child = try database.createFolder(name: "Child")
        try database.moveFolder(id: child.id, parentID: parent.id, position: 0)
        let grandchild = try database.createFolder(name: "Grandchild")
        try database.moveFolder(id: grandchild.id, parentID: child.id, position: 0)
        let keptFolder = try database.createFolder(name: "Kept")
        let inParent = try database.createNote(folderID: parent.id)
        let inChild = try database.createNote(folderID: child.id)
        let inGrandchild = try database.createNote(folderID: grandchild.id)
        let kept = try database.createNote(folderID: keptFolder.id)
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("stays-\(UUID().uuidString).mp3")
        try Data("audio".utf8).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }

        try database.deleteFolder(id: parent.id)

        for id in [parent.id, child.id, grandchild.id] {
            XCTAssertNil(try database.library().folders.first { $0.id == id })
        }
        for id in [inParent.id, inChild.id, inGrandchild.id] {
            XCTAssertThrowsError(try database.note(id: id))
        }
        XCTAssertEqual(try database.note(id: kept.id).folderID, keptFolder.id)
        XCTAssertNotNil(try database.library().folders.first { $0.id == keptFolder.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testCreateFolderGoesInsideTheSelectedFolder() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let parent = try database.createFolder(name: "Parent")
        let first = try database.createFolder(name: "First", parentID: parent.id)
        let second = try database.createFolder(name: "Second", parentID: parent.id)
        XCTAssertEqual(first.parentID, parent.id)
        XCTAssertEqual(second.parentID, parent.id)
        XCTAssertEqual(first.position, 0)
        XCTAssertGreaterThan(second.position, first.position)
        let root = try database.createFolder(name: "Root")
        XCTAssertNil(root.parentID)
        XCTAssertThrowsError(try database.createFolder(name: "Missing", parentID: "nope")) { error in
            XCTAssertEqual(error as? LibraryError, .message("That folder is not in the library."))
        }
    }

    func testRenameRejectsABlankName() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try database.renameFolder(id: LibraryDatabase.comedyFolderID, name: "  ")) { error in
            XCTAssertEqual(error as? LibraryError, .message("Enter a folder name."))
        }
        let renamed = try database.renameFolder(id: LibraryDatabase.comedyFolderID, name: " Bits ")
        XCTAssertEqual(renamed.name, "Bits")
    }

    func testSiblingDropUsesTheRowUnderThePointer() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(SiblingDrop.placement(siblingIDs: ids, draggedID: "a", index: 2)?.targetID, "c")
        XCTAssertEqual(SiblingDrop.placement(siblingIDs: ids, draggedID: "a", index: 2)?.zone, .before)
        XCTAssertEqual(SiblingDrop.placement(siblingIDs: ids, draggedID: "a", index: 3)?.zone, .after)
        XCTAssertEqual(SiblingDrop.placement(siblingIDs: ids, draggedID: "c", index: 0)?.targetID, "a")
        XCTAssertEqual(SiblingDrop.placement(siblingIDs: ids, draggedID: "c", index: 1)?.targetID, "b")
        XCTAssertNil(SiblingDrop.placement(siblingIDs: [], draggedID: "a", index: 0))
    }

    func testLoadedNotesCanBeFoundByAnAttachmentName() throws {
        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let created = try database.createNote(folderID: nil)
        let path = "user/scope/Confidence.mp3"
        let html = """
        <figure data-nn-storage-path="\(path)" data-nn-file-name="Confidence.mp3" \
        class="nn-audio-embed"></figure><p>Hello there</p>
        """
        _ = try database.saveNote(
            id: created.id,
            title: "Set list",
            bodyHTML: html,
            createdAtSource: created.createdAtSource
        )
        try database.execute(
            "INSERT INTO audio_display_names (storage_path, display_name, updated_at) VALUES (?1, ?2, ?3)",
            [.text(path), .text("Stage whisper"), .text("2020-01-01T00:00:00Z")]
        )
        let note = try database.library().notes.first { $0.id == created.id }
        XCTAssertEqual(note?.title, "Set list")
        XCTAssertTrue(note?.matchesSearch("Confidence.mp3") == true)
        XCTAssertTrue(note?.matchesSearch("Stage whisper") == true)
        XCTAssertFalse(note?.matchesSearch("Locked Notes") == true)
    }

    func testSearchMatchesAnyWordAndQuotesThePlaceItWasFound() {
        let phrase = NoteSummary(
            id: "phrase",
            title: "Long hair extended ideas",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil,
            opening: "This was the bit idea",
            searchText: "This was the bit idea about a long lost relative and the train"
        )
        let onlyLong = NoteSummary(
            id: "long",
            title: "Monday",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil,
            opening: "Opening that does not have the word",
            searchText: "Opening that does not have the word. A long session later"
        )
        XCTAssertTrue(phrase.matchesSearch("long hair"))
        XCTAssertTrue(onlyLong.matchesSearch("long hair"))
        XCTAssertFalse(onlyLong.matchesSearch("hair"))
        let excerpt = NoteSearch.excerpt(in: phrase.searchText, query: "long hair")
        XCTAssertTrue(excerpt.hasPrefix("..."), excerpt)
        XCTAssertTrue(excerpt.localizedStandardContains("long"), excerpt)
        XCTAssertFalse(excerpt.hasPrefix("This was"), excerpt)
        let ball = "The opening stays out of the preview. Ball hair hits lady pic"
        let ballExcerpt = NoteSearch.excerpt(in: ball, query: "long hair")
        XCTAssertTrue(ballExcerpt.hasPrefix("...Ball hair"), ballExcerpt)
        let ranges = NoteSearch.highlightRanges(in: "Long hair extended", query: "long hair")
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(String("Long hair extended"[ranges[0]]), "Long hair")
        XCTAssertEqual(NoteSearch.resultSubtitle(matchCount: 0), "No Results")
    }

    func testSuggestedSearchKeepsChecklistsAndAttachments() {
        let namedOnly = NoteSummary(
            id: "named",
            title: "Notes with Checklists",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil
        )
        let checklist = NoteSummary(
            id: "tasks",
            title: "Errands",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil,
            hasChecklist: true
        )
        let attachment = NoteSummary(
            id: "clip",
            title: "Set",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil,
            searchText: "Confidence.mp3",
            hasAttachment: true
        )
        XCTAssertTrue(namedOnly.matchesSearch("Checklists"))
        XCTAssertFalse(NoteSearch.matches(namedOnly, query: "", scope: .checklists))
        XCTAssertTrue(NoteSearch.matches(checklist, query: "", scope: .checklists))
        XCTAssertFalse(NoteSearch.matches(attachment, query: "", scope: .checklists))
        XCTAssertTrue(NoteSearch.matches(attachment, query: "Confidence", scope: .attachments))
        XCTAssertEqual(NoteSearchScope.menuScopes, [.checklists, .attachments])
        XCTAssertFalse(attachment.matches(.sharedNotes))
        XCTAssertFalse(attachment.matches(.lockedNotes))
        XCTAssertFalse(attachment.matches(.tags))
        XCTAssertFalse(attachment.matches(.drawings))
        XCTAssertFalse(attachment.matches(.scannedDocuments))
        XCTAssertTrue(NoteSearch.isActive(query: "", scope: .attachments))
        XCTAssertFalse(NoteSearch.isActive(query: "  ", scope: nil))
        let tasks = "<ul data-type=\"taskList\"><li data-type=\"taskItem\">Buy milk</li></ul>"
        let audio = "<figure data-nn-storage-path=\"user/clip.mp3\" class=\"nn-audio-embed\"></figure>"
        XCTAssertTrue(ReadingHTML.containsChecklist(in: tasks))
        XCTAssertFalse(ReadingHTML.containsAttachment(in: tasks))
        XCTAssertTrue(ReadingHTML.containsAttachment(in: audio))
        XCTAssertTrue(ReadingHTML.containsAttachment(in: "<img src=\"data:image/jpeg;base64,a\">"))
        XCTAssertFalse(ReadingHTML.containsAttachment(in: "<a href=\"https://example.com\">Site</a>"))
        XCTAssertEqual(NoteSearch.resultSubtitle(matchCount: 0), "No Results")
        XCTAssertEqual(NoteSearch.resultSubtitle(matchCount: 1), "Found 1 note")
        XCTAssertEqual(NoteSearch.resultSubtitle(matchCount: 23), "Found 23 notes")
    }
}
