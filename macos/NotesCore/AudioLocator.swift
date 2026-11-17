import Foundation

enum AudioLocator {
    static let audioRoot = URL(
        fileURLWithPath: "/Users/johnnyhammond/Documents/notesnursery/notes-export/note-audio",
        isDirectory: true
    )

    /// Copies made by Duplicate Note. The imported export folder is left unchanged.
    static var copyRoot: URL {
        LibraryDatabase.libraryURL
            .deletingLastPathComponent()
            .appendingPathComponent("note-audio", isDirectory: true)
    }

    /// The first root that contains the clip. A duplicate is found before the imported original.
    static func fileURL(storagePath: String, roots: [URL]) throws -> URL {
        for root in roots {
            do {
                return try fileURL(storagePath: storagePath, root: root)
            } catch AudioPathError.missing {
                continue
            }
        }
        throw AudioPathError.missing
    }

    /// Copies the clip into `copyRoot` and returns the new storage path.
    static func duplicateClip(storagePath: String, from roots: [URL], into copyRoot: URL) throws -> String {
        let source = try fileURL(storagePath: storagePath, roots: roots)
        let ext = source.pathExtension
        let name = ext.isEmpty
            ? UUID().uuidString.lowercased()
            : "\(UUID().uuidString.lowercased()).\(ext)"
        try FileManager.default.createDirectory(at: copyRoot, withIntermediateDirectories: true)
        let destination = copyRoot.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }

    static func fileURL(storagePath: String, root: URL) throws -> URL {
        let unescaped = unescape(storagePath.trimmingCharacters(in: .whitespacesAndNewlines))
        let segment = unescaped.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        guard isFileName(segment) else {
            throw AudioPathError.invalid
        }
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        var rootIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue
        else {
            throw AudioPathError.missing
        }
        let candidate = rootURL.appendingPathComponent(segment, isDirectory: false)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw AudioPathError.missing
        }
        let file = candidate.resolvingSymlinksInPath()
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard file.path == rootURL.path || file.path.hasPrefix(rootPrefix) else {
            throw AudioPathError.escapes
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw AudioPathError.missing
        }
        return file
    }

    static func isFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
    }

    static func unescape(_ input: String) -> String {
        var output = ""
        var rest = Substring(input)
        while let start = rest.firstIndex(of: "&") {
            output.append(contentsOf: rest[..<start])
            let after = rest[rest.index(after: start)...]
            if let end = after.firstIndex(of: ";"),
               let decoded = decodeEntity(String(after[..<end])) {
                output.append(decoded)
                rest = after[after.index(after: end)...]
                continue
            }
            output.append("&")
            rest = after
        }
        output.append(contentsOf: rest)
        return output
    }

    private static func decodeEntity(_ entity: String) -> String? {
        switch entity {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return "\u{00a0}"
        default:
            return decodeNumeric(entity)
        }
    }

    private static func decodeNumeric(_ entity: String) -> String? {
        let code: UInt32?
        if entity.lowercased().hasPrefix("#x") {
            code = UInt32(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            code = UInt32(entity.dropFirst())
        } else {
            code = nil
        }
        guard let code, let scalar = Unicode.Scalar(code) else {
            return nil
        }
        return String(Character(scalar))
    }
}

/// A byte range from an HTTP `Range` header, for audio playback.
struct AudioByteRange: Equatable {
    var status: Int
    var start: Int
    var end: Int
    var total: Int

    var contentRange: String? {
        switch status {
        case 206:
            "bytes \(start)-\(end)/\(total)"
        case 416:
            "bytes */\(total)"
        default:
            nil
        }
    }

    func body(from data: Data) -> Data {
        guard status == 206, start >= 0, end >= start, end < data.count else { return Data() }
        return data.subdata(in: start..<(end + 1))
    }

    /// Parses one `bytes=` range. Returns nil when the request has no range header.
    static func parse(header: String?, total: Int) -> AudioByteRange? {
        guard total > 0, let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        let first = spec.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        let parts = first.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return AudioByteRange(status: 416, start: 0, end: 0, total: total)
        }
        let startText = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let endText = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if startText.isEmpty {
            guard let suffix = Int(endText), suffix > 0 else {
                return AudioByteRange(status: 416, start: 0, end: 0, total: total)
            }
            let length = min(suffix, total)
            return AudioByteRange(status: 206, start: total - length, end: total - 1, total: total)
        }
        guard let parsedStart = Int(startText), parsedStart >= 0, parsedStart < total else {
            return AudioByteRange(status: 416, start: 0, end: 0, total: total)
        }
        let end: Int
        if endText.isEmpty {
            end = total - 1
        } else if let parsedEnd = Int(endText), parsedEnd >= parsedStart {
            end = min(parsedEnd, total - 1)
        } else {
            return AudioByteRange(status: 416, start: 0, end: 0, total: total)
        }
        return AudioByteRange(status: 206, start: parsedStart, end: end, total: total)
    }
}
