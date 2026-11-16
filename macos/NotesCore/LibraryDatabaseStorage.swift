import Foundation
import SQLite3

extension LibraryDatabase {
    func parentOf(_ id: String) throws -> String? {
        let rows = try query("SELECT parent_id FROM folders WHERE id = ?1", [.text(id)])
        guard let row = rows.first else {
            throw LibraryError.message("That folder is not in the library.")
        }
        return text(row, 0)
    }

    func folderContains(ancestor: String, maybeChild: String) throws -> Bool {
        var current: String? = maybeChild
        var seen = Set<String>()
        while let id = current {
            if id == ancestor { return true }
            if !seen.insert(id).inserted { return true }
            current = try parentOf(id)
        }
        return false
    }

    func folderExists(_ id: String) throws -> Bool {
        let rows = try query("SELECT COUNT(*) FROM folders WHERE id = ?1", [.text(id)])
        return int(rows.first ?? [], 0) > 0
    }

    func nextPosition(parentID: String?) throws -> Int64 {
        let rows: [[Bound]]
        if let parentID {
            rows = try query(
                "SELECT COALESCE(MAX(position), -1) FROM folders WHERE parent_id = ?1",
                [.text(parentID)]
            )
        } else {
            rows = try query(
                "SELECT COALESCE(MAX(position), -1) FROM folders WHERE parent_id IS NULL"
            )
        }
        return int(rows.first ?? [], 0) + 1
    }

    func siblingIDs(parentID: String?, excluding: String) throws -> [String] {
        if let parentID {
            return try texts(
                """
                SELECT id FROM folders
                WHERE parent_id = ?1 AND id <> ?2
                ORDER BY position ASC, name COLLATE NOCASE
                """,
                [.text(parentID), .text(excluding)]
            )
        }
        return try texts(
            """
            SELECT id FROM folders
            WHERE parent_id IS NULL AND id <> ?1
            ORDER BY position ASC, name COLLATE NOCASE
            """,
            [.text(excluding)]
        )
    }

    func setSiblingOrder(parentID: String?, ids: [String]) throws {
        for (index, id) in ids.enumerated() {
            try execute(
                "UPDATE folders SET parent_id = ?1, position = ?2 WHERE id = ?3",
                [parentID.map(Bound.text) ?? .null, .int(Int64(index)), .text(id)]
            )
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    enum Bound {
        case null
        case int(Int64)
        case text(String)
    }

    func tableExists(_ name: String) throws -> Bool {
        let rows = try query(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [.text(name)]
        )
        return !rows.isEmpty
    }

    func texts(_ sql: String, _ values: [Bound]) throws -> [String] {
        try query(sql, values).compactMap { text($0, 0) }
    }

    func text(_ row: [Bound], _ index: Int) -> String? {
        guard row.indices.contains(index) else { return nil }
        if case .text(let value) = row[index] { return value }
        return nil
    }

    func int(_ row: [Bound], _ index: Int) -> Int64 {
        guard row.indices.contains(index) else { return 0 }
        if case .int(let value) = row[index] { return value }
        return 0
    }

    @discardableResult
    func execute(_ sql: String, _ values: [Bound] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, values)
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw lastError()
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ values: [Bound] = []) throws -> [[Bound]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, values)
        var rows: [[Bound]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastError() }
            let count = sqlite3_column_count(statement)
            var row: [Bound] = []
            for index in 0..<count {
                switch sqlite3_column_type(statement, index) {
                case SQLITE_NULL:
                    row.append(.null)
                case SQLITE_INTEGER:
                    row.append(.int(sqlite3_column_int64(statement, index)))
                default:
                    if let value = sqlite3_column_text(statement, index) {
                        row.append(.text(String(cString: value)))
                    } else {
                        row.append(.null)
                    }
                }
            }
            rows.append(row)
        }
        return rows
    }

    func bind(_ statement: OpaquePointer?, _ values: [Bound]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .int(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .text(let text):
                result = text.withCString { pointer in
                    sqlite3_bind_text(statement, index, pointer, -1, transient)
                }
            }
            guard result == SQLITE_OK else { throw lastError() }
        }
    }

    func lastError() -> LibraryError {
        guard let handle else {
            return .message("The notes library is not open.")
        }
        return .message(String(cString: sqlite3_errmsg(handle)))
    }
}
