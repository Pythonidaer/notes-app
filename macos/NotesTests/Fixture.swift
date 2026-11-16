import Foundation
import SQLite3

enum Fixture {
    static let baseSQL = """
    CREATE TABLE profile (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      color_scheme TEXT NOT NULL,
      default_folder_id TEXT NOT NULL
    );
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      body_html TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      created_at_source TEXT NOT NULL,
      modified_at_source TEXT NOT NULL,
      folder_id TEXT
    );
    CREATE TABLE folders (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      parent_id TEXT,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE audio_display_names (
      storage_path TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE app_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    INSERT INTO profile (id, username, color_scheme, default_folder_id)
    VALUES ('profile', 'Pythonidaer', 'dark', '\(LibraryDatabase.comedyFolderID)');
    INSERT INTO folders (id, name, parent_id, position, created_at)
    VALUES ('\(LibraryDatabase.comedyFolderID)', 'Comedy', NULL, 0, '2020-01-01T00:00:00Z');
    INSERT INTO app_meta (key, value) VALUES ('imported', 'profile');
    """

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-swift-\(UUID().uuidString).sqlite")
    }

    static func importedLibrary() throws -> (URL, LibraryDatabase) {
        let url = temporaryURL()
        try write(url, baseSQL)
        return (url, try LibraryDatabase.open(file: url))
    }

    static func write(_ url: URL, _ sql: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let connection else {
            throw LibraryError.message("The fixture database did not open.")
        }
        defer { sqlite3_close(connection) }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "The fixture SQL failed."
            sqlite3_free(error)
            throw LibraryError.message(message)
        }
    }

    static func tableNames(_ url: URL) throws -> [String] {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw LibraryError.message("The fixture database did not open.")
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection,
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw LibraryError.message("The fixture database did not list tables.")
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                names.append(String(cString: value))
            }
        }
        return names
    }
}
