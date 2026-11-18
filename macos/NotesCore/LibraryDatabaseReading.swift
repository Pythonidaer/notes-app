import Foundation
import SQLite3

extension LibraryDatabase {
    func validateExistingLibrary() throws {
        let hasLabels = try tableExists("labels")
        let hasLinks = try tableExists("note_labels")
        if hasLabels || hasLinks {
            throw LibraryError.legacyLabels
        }
        let imported = try query("SELECT value FROM app_meta WHERE key = 'imported'")
        guard !imported.isEmpty else {
            throw LibraryError.notImported
        }
    }

    func profile() throws -> Profile {
        let rows = try query(
            "SELECT id, username, color_scheme, default_folder_id FROM profile LIMIT 1"
        )
        guard let row = rows.first else {
            throw LibraryError.notImported
        }
        return Profile(
            id: text(row, 0) ?? "",
            username: text(row, 1) ?? "",
            colorScheme: text(row, 2) ?? "light",
            defaultFolderID: text(row, 3) ?? ""
        )
    }

    func folders() throws -> [Folder] {
        try query(
            """
            SELECT id, name, parent_id, position, created_at
            FROM folders
            ORDER BY position ASC, name COLLATE NOCASE
            """
        ).map { row in
            Folder(
                id: text(row, 0) ?? "",
                name: text(row, 1) ?? "",
                parentID: text(row, 2),
                position: int(row, 3),
                createdAt: text(row, 4) ?? ""
            )
        }
    }

    /// Every note's list summary, most recently updated first.
    ///
    /// Parses each note body, so the cost grows with the size of the whole library.
    func notes() throws -> [NoteSummary] {
        let names = try audioDisplayNames()
        return try query(
            """
            SELECT id, title, created_at_source, modified_at_source, folder_id, body_html
            FROM notes
            ORDER BY updated_at DESC
            """
        ).map { makeSummary(row: $0, displayNames: names) }
    }

    /// The list summary for one note, built the same way as `notes()`.
    func noteSummary(id: String) throws -> NoteSummary {
        let rows = try query(
            """
            SELECT id, title, created_at_source, modified_at_source, folder_id, body_html
            FROM notes WHERE id = ?1
            """,
            [.text(id)]
        )
        guard let row = rows.first else {
            throw LibraryError.message("That note is not in the library.")
        }
        return makeSummary(row: row, displayNames: try audioDisplayNames())
    }

    private func makeSummary(row: [Bound], displayNames: [String: String]) -> NoteSummary {
        let html = text(row, 5) ?? ""
        return NoteSummary(
            id: text(row, 0) ?? "",
            title: text(row, 1) ?? "",
            createdAtSource: text(row, 2) ?? "",
            modifiedAtSource: text(row, 3) ?? "",
            folderID: text(row, 4),
            opening: ReadingHTML.opening(in: html),
            searchText: ReadingHTML.searchText(in: html, displayNames: displayNames),
            hasChecklist: ReadingHTML.containsChecklist(in: html),
            hasAttachment: ReadingHTML.containsAttachment(in: html)
        )
    }

    func folder(id: String) throws -> Folder {
        guard let found = try folders().first(where: { $0.id == id }) else {
            throw LibraryError.message("That folder is not in the library.")
        }
        return found
    }

    func resolveCreateFolder(_ folderID: String?) throws -> String? {
        if let folderID, !folderID.isEmpty {
            guard try folderExists(folderID) else {
                throw LibraryError.message("That folder is not in the library.")
            }
            return folderID
        }
        let profile = try profile()
        if try folderExists(profile.defaultFolderID) {
            return profile.defaultFolderID
        }
        return nil
    }
}
