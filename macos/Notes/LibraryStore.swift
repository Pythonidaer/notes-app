import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmTitle: String
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

    func load() {
        guard snapshot == nil, loadError == nil else { return }
        do {
            let opened = try LibraryDatabase.open(file: LibraryDatabase.libraryURL)
            database = opened
            snapshot = try opened.library()
        } catch {
            loadError = error.localizedDescription
        }
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

    func selectNote(_ id: String) {
        do {
            let detail = try database?.note(id: id)
            selectedNoteID = id
            note = detail
            editing = false
            status = ""
        } catch {
            selectedNoteID = id
            status = error.localizedDescription
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
            try reload(database)
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
            title: "Delete folder",
            message: "Delete this folder? Notes stay.",
            confirmTitle: "Delete"
        ) { [weak self] in
            self?.deleteFolder(id: folder.id)
        }
    }

    func askToDeleteNote() {
        guard let note else { return }
        confirmation = Confirmation(
            title: "Delete note",
            message: "Delete this note? Audio files stay.",
            confirmTitle: "Delete"
        ) { [weak self] in
            self?.deleteNote(id: note.id)
        }
    }

    func receiveDrop(raw: String, on anchor: DropAnchor, zone: DropZone) {
        perform { database in
            try database.performDrop(raw: raw, on: anchor, zone: zone)
            try reload(database)
            if let selectedNoteID {
                self.note = try database.note(id: selectedNoteID)
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
            if let selectedNoteID {
                note = try? database.note(id: selectedNoteID)
            }
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

    private func reload(_ database: LibraryDatabase) throws {
        snapshot = try database.library()
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
