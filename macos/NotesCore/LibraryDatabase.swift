import Foundation
import SQLite3

final class LibraryDatabase {
    static let comedyFolderID = "4102f124-0352-4bb6-afef-05f745b0bd82"
    static let noteDragType = "com.pythonidaer.notes.note"
    static let folderDragType = "com.pythonidaer.notes.folder"

    static var libraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.pythonidaer.notes/notes.sqlite")
    }

    var handle: OpaquePointer?
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    static func open(file url: URL) throws -> LibraryDatabase {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw LibraryError.missingDatabase
        }
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK, let connection else {
            if let connection {
                sqlite3_close(connection)
            }
            throw LibraryError.missingDatabase
        }
        sqlite3_busy_timeout(connection, 3000)
        let library = LibraryDatabase(handle: connection)
        try library.validateExistingLibrary()
        return library
    }

    func loadLibrarySnapshot() throws -> LibrarySnapshot {
        LibrarySnapshot(profile: try profile(), folders: try folders(), notes: try notes())
    }

    func note(id: String) throws -> NoteDetail {
        let rows = try query(
            """
            SELECT title, body_html, created_at_source, modified_at_source, folder_id
            FROM notes WHERE id = ?1
            """,
            [.text(id)]
        )
        guard let row = rows.first else {
            throw LibraryError.message("That note is not in the library.")
        }
        return NoteDetail(
            id: id,
            title: text(row, 0) ?? "",
            bodyHTML: text(row, 1) ?? "",
            createdAtSource: text(row, 2) ?? "",
            modifiedAtSource: text(row, 3) ?? "",
            folderID: text(row, 4)
        )
    }

    func createNote(folderID: String?) throws -> NoteDetail {
        let chosen = try resolveCreateFolder(folderID)
        let id = UUID().uuidString.lowercased()
        let now = Date()
        let stored = Self.timestamp(now, timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let source = Self.timestamp(now, timeZone: .current)
        try execute(
            """
            INSERT INTO notes (
                id, title, body_html, created_at, updated_at,
                created_at_source, modified_at_source, folder_id
            ) VALUES (?1, '', '<p></p>', ?2, ?2, ?3, ?3, ?4)
            """,
            [.text(id), .text(stored), .text(source), chosen.map(Bound.text) ?? .null]
        )
        return try note(id: id)
    }

    /// A new note with the same title, body, and folder. Each audio clip is its own file.
    func duplicateNote(
        id: String,
        audioRoots: [URL] = [AudioLocator.copyRoot, AudioLocator.audioRoot],
        copyRoot: URL = AudioLocator.copyRoot
    ) throws -> NoteDetail {
        let source = try note(id: id)
        let prepared = try copiedAudioBody(source.bodyHTML, audioRoots: audioRoots, copyRoot: copyRoot)
        let copyID = UUID().uuidString.lowercased()
        let now = Date()
        let stored = Self.timestamp(now, timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let sourceStamp = Self.timestamp(now, timeZone: .current)
        do {
            try transaction {
                try execute(
                    """
                    INSERT INTO notes (
                        id, title, body_html, created_at, updated_at,
                        created_at_source, modified_at_source, folder_id
                    ) VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?5, ?6)
                    """,
                    [
                        .text(copyID),
                        .text(source.title),
                        .text(prepared.html),
                        .text(stored),
                        .text(sourceStamp),
                        source.folderID.map(Bound.text) ?? .null
                    ]
                )
                for name in prepared.displayNames {
                    try execute(
                        """
                        INSERT INTO audio_display_names (storage_path, display_name, updated_at)
                        VALUES (?1, ?2, ?3)
                        """,
                        [.text(name.path), .text(name.display), .text(stored)]
                    )
                }
            }
        } catch {
            for file in prepared.files {
                try? FileManager.default.removeItem(at: file)
            }
            throw error
        }
        return try note(id: copyID)
    }

    /// Rewrites audio paths so the copy plays its own files. A missing clip keeps the original path.
    private func copiedAudioBody(
        _ html: String,
        audioRoots: [URL],
        copyRoot: URL
    ) throws -> (html: String, files: [URL], displayNames: [(path: String, display: String)]) {
        var result = html
        var files: [URL] = []
        var displayNames: [(path: String, display: String)] = []
        var copied: [String: String] = [:]
        do {
            for clip in ReadingHTML.embeddedAudio(in: html) where !clip.storagePath.isEmpty {
                let path = clip.storagePath
                let newPath: String
                if let existing = copied[path] {
                    newPath = existing
                } else {
                    do {
                        newPath = try AudioLocator.duplicateClip(storagePath: path, from: audioRoots, into: copyRoot)
                    } catch is AudioPathError {
                        continue
                    }
                    copied[path] = newPath
                    files.append(copyRoot.appendingPathComponent(newPath, isDirectory: false))
                    if let display = try displayName(storagePath: path), !display.isEmpty {
                        displayNames.append((newPath, display))
                    }
                }
                result = result.replacingOccurrences(
                    of: "data-nn-storage-path=\"\(path)\"",
                    with: "data-nn-storage-path=\"\(newPath)\""
                )
            }
        } catch {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            throw error
        }
        return (result, files, displayNames)
    }

    func saveNote(id: String, title: String, bodyHTML: String, createdAtSource: String) throws -> NoteDetail {
        let updated = Self.timestamp(Date(), timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let changed = try execute(
            """
            UPDATE notes
            SET title = ?1, body_html = ?2, created_at_source = ?3, updated_at = ?4
            WHERE id = ?5
            """,
            [.text(title), .text(bodyHTML), .text(createdAtSource), .text(updated), .text(id)]
        )
        guard changed > 0 else {
            throw LibraryError.message("That note is not in the library.")
        }
        return try note(id: id)
    }

    func deleteNote(id: String) throws {
        let changed = try execute("DELETE FROM notes WHERE id = ?1", [.text(id)])
        guard changed > 0 else {
            throw LibraryError.message("That note is not in the library.")
        }
    }

    func moveNote(id: String, folderID: String?) throws -> NoteDetail {
        if let folderID, !folderID.isEmpty {
            guard try folderExists(folderID) else {
                throw LibraryError.message("That folder is not in the library.")
            }
        }
        let folder = folderID.flatMap { $0.isEmpty ? nil : $0 }
        let changed = try execute(
            "UPDATE notes SET folder_id = ?1 WHERE id = ?2",
            [folder.map(Bound.text) ?? .null, .text(id)]
        )
        guard changed > 0 else {
            throw LibraryError.message("That note is not in the library.")
        }
        return try note(id: id)
    }

    func createFolder(name: String, parentID: String? = nil) throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryError.message("Enter a folder name.")
        }
        if let parentID {
            guard try folderExists(parentID) else {
                throw LibraryError.message("That folder is not in the library.")
            }
        }
        let id = UUID().uuidString.lowercased()
        let created = Self.timestamp(Date(), timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let position = try nextPosition(parentID: parentID)
        try execute(
            """
            INSERT INTO folders (id, name, parent_id, position, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            """,
            [
                .text(id),
                .text(trimmed),
                parentID.map(Bound.text) ?? .null,
                .int(position),
                .text(created)
            ]
        )
        return try folder(id: id)
    }

    func renameFolder(id: String, name: String) throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryError.message("Enter a folder name.")
        }
        let changed = try execute(
            "UPDATE folders SET name = ?1 WHERE id = ?2",
            [.text(trimmed), .text(id)]
        )
        guard changed > 0 else {
            throw LibraryError.message("That folder is not in the library.")
        }
        return try folder(id: id)
    }

    /// Deletes the folder, every folder inside it, and the notes in those folders.
    ///
    /// Audio files on disk are left where they are.
    func deleteFolder(id: String) throws {
        guard try folderExists(id) else {
            throw LibraryError.message("That folder is not in the library.")
        }
        let folderIDs = try containedFolderIDs(id)
        try transaction {
            for folderID in folderIDs {
                try execute("DELETE FROM notes WHERE folder_id = ?1", [.text(folderID)])
            }
            for folderID in folderIDs.reversed() {
                let changed = try execute("DELETE FROM folders WHERE id = ?1", [.text(folderID)])
                guard changed > 0 else {
                    throw LibraryError.message("That folder is not in the library.")
                }
            }
        }
    }

    /// `id` and every folder nested inside it, with a folder before the folders it contains.
    private func containedFolderIDs(_ id: String) throws -> [String] {
        var ids = [id]
        var index = 0
        while index < ids.count {
            ids.append(contentsOf: try siblingIDs(parentID: ids[index], excluding: ""))
            index += 1
        }
        return ids
    }

    func moveFolder(id: String, parentID: String?, position: Int) throws {
        guard try folderExists(id) else {
            throw LibraryError.message("That folder is not in the library.")
        }
        let parent = parentID.flatMap { $0.isEmpty ? nil : $0 }
        if let parent {
            let inside = try folderContains(ancestor: id, maybeChild: parent)
            if parent == id || inside {
                throw LibraryError.message("A folder cannot move inside itself.")
            }
            guard try folderExists(parent) else {
                throw LibraryError.message("That folder is not in the library.")
            }
        }
        let oldParent = try parentOf(id)
        var siblings = try siblingIDs(parentID: parent, excluding: id)
        let index = min(max(position, 0), siblings.count)
        siblings.insert(id, at: index)
        try transaction {
            try setSiblingOrder(parentID: parent, ids: siblings)
            if oldParent != parent {
                let remaining = try siblingIDs(parentID: oldParent, excluding: id)
                try setSiblingOrder(parentID: oldParent, ids: remaining)
            }
        }
    }

    func displayName(storagePath: String) throws -> String? {
        let rows = try query(
            "SELECT display_name FROM audio_display_names WHERE storage_path = ?1",
            [.text(storagePath)]
        )
        return rows.first.flatMap { text($0, 0) }
    }

    func audioDisplayNames() throws -> [String: String] {
        try query(
            "SELECT storage_path, display_name FROM audio_display_names",
            []
        ).reduce(into: [:]) { names, row in
            guard let path = text(row, 0), let name = text(row, 1), !name.isEmpty else { return }
            names[path] = name
        }
    }

    func tableNames() throws -> [String] {
        try texts(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
            []
        )
    }

}

// MARK: - Drag and drop

extension LibraryDatabase {
    /// Decodes a sidebar drag payload and moves the note or folder it names.
    ///
    /// A payload that `DraggedItem` cannot decode changes nothing and does not throw.
    func performDrop(raw: String, on anchor: DropAnchor, zone: DropZone) throws {
        guard let item = DraggedItem(payload: raw) else { return }
        try drop(item, on: anchor, zone: zone)
    }

    /// Moves a dragged note or folder to `anchor`.
    ///
    /// A note goes into the anchor folder, or out of every folder on All Notes, whatever the zone.
    /// A folder dropped on All Notes goes last at the root. On a folder, `.child` nests it last
    /// inside, and `.before` or `.after` places it beside the anchor. A folder dropped on itself
    /// does nothing.
    func drop(_ item: DraggedItem, on anchor: DropAnchor, zone: DropZone) throws {
        switch (item, anchor) {
        case (.note(let id), .allNotes):
            _ = try moveNote(id: id, folderID: nil)
        case (.note(let id), .folder(let folderID)):
            _ = try moveNote(id: id, folderID: folderID)
        case (.folder(let id), .allNotes):
            try moveFolderToRoot(id: id)
        case (.folder(let id), .folder(let folderID)):
            try moveFolder(id: id, onto: folderID, zone: zone)
        }
    }

    /// Moves a nested folder to the end of the root folders. A root folder stays where it is.
    private func moveFolderToRoot(id: String) throws {
        guard try parentOf(id) != nil else { return }
        let position = try siblingIDs(parentID: nil, excluding: id).count
        try moveFolder(id: id, parentID: nil, position: position)
    }

    private func moveFolder(id: String, onto targetID: String, zone: DropZone) throws {
        guard id != targetID else { return }
        if zone == .child {
            let position = try siblingIDs(parentID: targetID, excluding: id).count
            try moveFolder(id: id, parentID: targetID, position: position)
            return
        }
        let parent = try parentOf(targetID)
        let siblings = try siblingIDs(parentID: parent, excluding: id)
        let index = siblings.firstIndex(of: targetID) ?? -1
        let position = zone == .before ? index : index + 1
        try moveFolder(id: id, parentID: parent, position: max(0, position))
    }
}
