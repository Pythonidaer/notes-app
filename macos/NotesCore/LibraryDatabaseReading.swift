import Foundation
import SQLite3

extension LibraryDatabase {
    func draggedItem(from raw: String) -> (kind: String, id: String)? {
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let id = String(parts[1])
        guard !id.isEmpty else { return nil }
        return (kind: String(parts[0]), id: id)
    }

    func dropOnAllNotes(kind: String, id: String) throws {
        if kind == "note" {
            _ = try moveNote(id: id, folderID: nil)
            return
        }
        guard kind == "folder" else { return }
        guard try parentOf(id) != nil else { return }
        let position = try siblingIDs(parentID: nil, excluding: id).count
        try moveFolder(id: id, parentID: nil, position: position)
    }

    func drop(kind: String, id: String, into folderID: String, zone: DropZone) throws {
        if kind == "folder", id == folderID { return }
        if kind == "note" {
            _ = try moveNote(id: id, folderID: folderID)
            return
        }
        guard kind == "folder" else { return }
        if zone == .child {
            let position = try siblingIDs(parentID: folderID, excluding: id).count
            try moveFolder(id: id, parentID: folderID, position: position)
            return
        }
        let parent = try parentOf(folderID)
        let siblings = try siblingIDs(parentID: parent, excluding: id)
        let index = siblings.firstIndex(of: folderID) ?? -1
        let position = zone == .before ? index : index + 1
        try moveFolder(id: id, parentID: parent, position: max(0, position))
    }

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

    func notes() throws -> [NoteSummary] {
        let names = try audioDisplayNames()
        return try query(
            """
            SELECT id, title, created_at_source, modified_at_source, folder_id, body_html
            FROM notes
            ORDER BY updated_at DESC
            """
        ).map { row in
            let html = text(row, 5) ?? ""
            return NoteSummary(
                id: text(row, 0) ?? "",
                title: text(row, 1) ?? "",
                createdAtSource: text(row, 2) ?? "",
                modifiedAtSource: text(row, 3) ?? "",
                folderID: text(row, 4),
                opening: ReadingHTML.opening(in: html),
                searchText: ReadingHTML.searchText(in: html, displayNames: names),
                hasChecklist: ReadingHTML.containsChecklist(in: html),
                hasAttachment: ReadingHTML.containsAttachment(in: html)
            )
        }
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
