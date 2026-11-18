import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmTitle: String
        /// A destructive confirm button is red. Folder delete uses the accent button.
        var isDestructive = true
        let action: () -> Void
    }

    @Published private(set) var snapshot: LibrarySnapshot?
    @Published var folderID: String?
    @Published var selectedNoteID: String?
    @Published var note: NoteDetail?
    @Published var editing = false
    @Published var status = ""
    @Published var loadError: String?
    @Published var confirmation: Confirmation?
    @Published var listArrangement = NoteListArrangement.stored {
        didSet { listArrangement.store() }
    }
    @Published var searchText = ""
    @Published var searchScope: NoteSearchScope?

    private var database: LibraryDatabase?

    var folders: [Folder] { snapshot?.folders ?? [] }
    var notes: [NoteSummary] { snapshot?.notes ?? [] }
    var colorSchemeName: String { snapshot?.profile.colorScheme ?? "light" }

    var selectedFolder: Folder? {
        guard let folderID else { return nil }
        return folders.first { $0.id == folderID }
    }

    /// The selected note once its detail has loaded, or nil while it is loading or nothing is selected.
    var openNote: NoteDetail? {
        guard let note, note.id == selectedNoteID else { return nil }
        return note
    }

    /// A note is selected but its detail has not loaded yet.
    var isLoadingNote: Bool {
        selectedNoteID != nil && openNote == nil
    }

    func load(file url: URL = LibraryDatabase.libraryURL) {
        guard snapshot == nil, loadError == nil else { return }
        do {
            let opened = try LibraryDatabase.open(file: url)
            database = opened
            snapshot = try opened.loadLibrarySnapshot()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// The stored note for `id`, or nil when that note is not in the library.
    ///
    /// Reads the open database. Callers use this for a second window so the main window's
    /// selected note stays where it is.
    func note(id: String) -> NoteDetail? {
        guard notes.contains(where: { $0.id == id }) else { return nil }
        return try? database?.note(id: id)
    }

    func notesInSelectedFolder() -> [NoteSummary] {
        guard let folderID else { return notes }
        return notes.filter { $0.folderID == folderID }
    }

    /// The note list is showing search results.
    var isSearching: Bool {
        NoteSearch.isActive(query: searchText, scope: searchScope)
    }

    /// Notes in the selected folder that match the search field.
    ///
    /// An empty search returns the whole folder. All notes is the folder when none is selected.
    /// A suggestion keeps notes of that kind. The suggestion title is not a text query.
    func notesMatchingSearch() -> [NoteSummary] {
        notesInSelectedFolder().filter {
            NoteSearch.matches($0, query: searchText, scope: searchScope)
        }
    }

    func count(in folderID: String) -> Int {
        notes.filter { $0.folderID == folderID }.count
    }

    /// Creates a note when the open folder has none, so a click in the blank note column can start typing.
    func startNoteInEmptyFolder() {
        guard !isSearching, selectedNoteID == nil, notesInSelectedFolder().isEmpty else { return }
        createNote()
    }

    /// Shows this folder, or every note when `id` is nil.
    ///
    /// The open note stays when it is in the folder. Otherwise the first note in the list opens.
    /// An empty folder clears the note, so the detail column is blank until it is clicked.
    func selectFolder(_ id: String?) {
        guard folderID != id else { return }
        folderID = id
        showNoteInCurrentFolder()
    }

    /// Opens the note with `id` and returns whether it opened.
    ///
    /// When the note cannot be read, the open note stays selected and `status` shows the error.
    @discardableResult
    func selectNote(_ id: String) -> Bool {
        guard let database else { return false }
        do {
            let detail = try database.note(id: id)
            selectedNoteID = id
            note = detail
            editing = false
            status = ""
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    func createNote() {
        perform { database in
            let created = try database.createNote(folderID: folderID)
            try reload(database)
            selectedNoteID = created.id
            note = created
            editing = true
        }
    }

    func saveNote(id: String, title: String, bodyHTML: String, createdAtSource: String) {
        perform { database in
            let saved = try database.saveNote(
                id: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyHTML: bodyHTML,
                createdAtSource: createdAtSource.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try refreshSavedNote(id: id, in: database)
            if note?.id == id {
                note = saved
            }
        }
    }

    func createFolder(name: String) {
        let parentID = folderID
        perform { database in
            let created = try database.createFolder(name: name, parentID: parentID)
            try reload(database)
            folderID = created.id
            showNoteInCurrentFolder()
        }
    }

    func renameFolder(id: String, name: String) {
        perform { database in
            _ = try database.renameFolder(id: id, name: name)
            try reload(database)
        }
    }

    func askToDeleteFolder() {
        guard let folder = selectedFolder else { return }
        confirmation = Confirmation(
            title: "Are you sure you want to delete this folder?",
            message: "All notes and any subfolders will be deleted.",
            confirmTitle: "Delete",
            isDestructive: false
        ) { [weak self] in
            self?.deleteFolder(id: folder.id)
        }
    }

    func duplicateNote(_ id: String) {
        let keptFolder = folderID
        perform { database in
            let copy = try database.duplicateNote(id: id)
            try reload(database)
            folderID = keptFolder
            selectedNoteID = copy.id
            note = copy
            editing = false
        }
    }

    func moveNote(_ id: String, to folderID: String) {
        guard notes.first(where: { $0.id == id })?.folderID != folderID else { return }
        let keptFolder = self.folderID
        perform { database in
            let moved = try database.moveNote(id: id, folderID: folderID)
            try reload(database)
            self.folderID = keptFolder
            if note?.id == id {
                note = moved
            }
            showNoteInCurrentFolder()
        }
    }

    func askToDeleteNote() {
        guard let note else { return }
        confirmation = Confirmation(
            title: "Delete note",
            message: note.deleteConfirmationMessage,
            confirmTitle: "Delete"
        ) { [weak self] in
            self?.deleteNote(id: note.id)
        }
    }

    func receiveDrop(raw: String, on anchor: DropAnchor, zone: DropZone) {
        perform { database in
            try database.performDrop(raw: raw, on: anchor, zone: zone)
            try reload(database)
            showNoteInCurrentFolder()
            if let selectedNoteID, note?.id == selectedNoteID {
                note = try database.note(id: selectedNoteID)
            }
        }
    }

    private func deleteFolder(id: String) {
        let parent = folders.first { $0.id == id }?.parentID
        perform { database in
            try database.deleteFolder(id: id)
            if folderID == id {
                folderID = parent
            }
            try reload(database)
            showNoteInCurrentFolder()
        }
    }

    private func deleteNote(id: String) {
        let keptFolder = folderID
        let successor = NoteCalendar.noteIDAfterDelete(
            notesInSelectedFolder(),
            deletedID: id,
            arrangement: listArrangement
        )
        perform { database in
            try database.deleteNote(id: id)
            try reload(database)
            folderID = keptFolder
            guard selectedNoteID == id else { return }
            editing = false
            selectedNoteID = successor
            if let successor {
                note = try database.note(id: successor)
            } else {
                note = nil
            }
        }
    }

    /// Opens a note that belongs in the current folder, or clears the column when none does.
    private func showNoteInCurrentFolder() {
        var arrangement = listArrangement
        if isSearching {
            arrangement.grouping = .groupsOff
        }
        let nextID = NoteCalendar.noteIDForSelection(
            in: notesMatchingSearch(),
            selectedID: selectedNoteID,
            arrangement: arrangement
        )
        if nextID == selectedNoteID, note?.id == nextID {
            return
        }
        if let nextID {
            selectNote(nextID)
        } else {
            clearOpenNote()
        }
    }

    private func clearOpenNote() {
        selectedNoteID = nil
        note = nil
        editing = false
        status = ""
    }

    private func reload(_ database: LibraryDatabase) throws {
        snapshot = try database.loadLibrarySnapshot()
    }

    /// Updates only the saved note's summary, because a full reload parses every note body.
    ///
    /// Falls back to a full reload when the note is missing from the snapshot.
    private func refreshSavedNote(id: String, in database: LibraryDatabase) throws {
        let summary = try database.noteSummary(id: id)
        guard var refreshed = snapshot, refreshed.replaceSavedNote(with: summary) else {
            try reload(database)
            return
        }
        snapshot = refreshed
    }

    private func perform(_ work: (LibraryDatabase) throws -> Void) {
        guard let database else { return }
        do {
            try work(database)
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }
}
