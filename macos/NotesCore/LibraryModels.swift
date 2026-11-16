import AppKit
import Foundation

enum LibraryError: Error, Equatable, LocalizedError {
    case missingDatabase
    case legacyLabels
    case notImported
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase:
            "The notes library is not on this Mac."
        case .legacyLabels:
            "This library still has label tables."
        case .notImported:
            "Notes are not imported yet."
        case .message(let text):
            text
        }
    }
}

enum AudioPathError: Error, Equatable, LocalizedError {
    case invalid
    case escapes
    case missing

    var errorDescription: String? {
        switch self {
        case .invalid:
            "That audio path is not a file name."
        case .escapes:
            "That audio file is outside the audio folder."
        case .missing:
            "That audio file is missing."
        }
    }
}

enum LibraryDrag {
    static var current: String?
    static let pasteboardType = NSPasteboard.PasteboardType("com.pythonidaer.notes.drag")

    static func payload(noteID: String) -> String {
        "note:\(noteID)"
    }

    static func payload(folderID: String) -> String {
        "folder:\(folderID)"
    }

    static func writer(_ raw: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(raw, forType: pasteboardType)
        item.setString(raw, forType: .string)
        return item
    }
}

enum DropAnchor: Equatable {
    case allNotes
    case folder(String)
}

enum DropZone: Equatable {
    case before
    case child
    case after
}

enum SiblingDrop {
    static func placement(siblingIDs: [String], draggedID: String, index: Int) -> (targetID: String, zone: DropZone)? {
        guard !siblingIDs.isEmpty else { return nil }
        if index < siblingIDs.count {
            let target = siblingIDs[index]
            if target != draggedID {
                return (target, .before)
            }
            if index + 1 < siblingIDs.count {
                return (siblingIDs[index + 1], .before)
            }
            if index > 0 {
                return (siblingIDs[index - 1], .after)
            }
            return nil
        }
        guard let last = siblingIDs.last else { return nil }
        if last != draggedID {
            return (last, .after)
        }
        if siblingIDs.count >= 2 {
            return (siblingIDs[siblingIDs.count - 2], .after)
        }
        return nil
    }
}

struct Profile: Equatable {
    var id: String
    var username: String
    var colorScheme: String
    var defaultFolderID: String
}

struct Folder: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var parentID: String?
    var position: Int64
    var createdAt: String
}

/// One row in the menu that opens when the note bar search field is focused and empty.
enum NoteSearchScope: String, CaseIterable, Identifiable {
    case sharedNotes
    case lockedNotes
    case checklists
    case tags
    case drawings
    case scannedDocuments
    case attachments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sharedNotes:
            "Shared Notes"
        case .lockedNotes:
            "Locked Notes"
        case .checklists:
            "Notes with Checklists"
        case .tags:
            "Notes with Tags"
        case .drawings:
            "Notes with Drawings"
        case .scannedDocuments:
            "Notes with Scanned Documents"
        case .attachments:
            "Notes with Attachments"
        }
    }

    /// The symbol drawn beside the suggestion title.
    var symbolName: String {
        switch self {
        case .sharedNotes:
            "person.crop.circle"
        case .lockedNotes:
            "lock"
        case .checklists:
            "checklist"
        case .tags:
            "number"
        case .drawings:
            "pencil.tip.crop.circle"
        case .scannedDocuments:
            "doc.viewfinder"
        case .attachments:
            "paperclip"
        }
    }
}

struct NoteSummary: Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var createdAtSource: String
    var modifiedAtSource: String
    var folderID: String?
    var opening: String = ""
    /// Plain text of the note plus attachment names.
    ///
    /// Search uses this so a filename such as `Confidence.mp3` matches when it is not the title.
    var searchText: String = ""
    /// The body contains a checklist.
    var hasChecklist: Bool = false
    /// The body contains an audio embed, an image, a video, or a file link.
    var hasAttachment: Bool = false

    /// Whether this note matches a search query.
    ///
    /// An empty query matches every note. Each word is tried on its own, so "long hair"
    /// matches a note that contains the phrase and a note that only contains "long".
    /// Attachment names in `searchText` still match.
    func matchesSearch(_ query: String) -> Bool {
        NoteSearch.matches(title: title, text: searchText, query: query)
    }

    /// Whether this note belongs in a suggested search.
    ///
    /// Checklists and attachments are read from the note body. This library has no shared notes,
    /// locked notes, tags, drawings, or scanned documents, so those suggestions match nothing.
    func matches(_ scope: NoteSearchScope) -> Bool {
        switch scope {
        case .checklists:
            hasChecklist
        case .attachments:
            hasAttachment
        case .sharedNotes, .lockedNotes, .tags, .drawings, .scannedDocuments:
            false
        }
    }
}

/// Library search over note titles, note text, and attachment names.
enum NoteSearch {
    /// Words of a query, in order.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether a library search is showing results instead of the folder.
    static func isActive(query: String, scope: NoteSearchScope?) -> Bool {
        scope != nil || !terms(in: query).isEmpty
    }

    /// Whether `note` belongs in the current library search.
    ///
    /// The scope is not a text query. "Notes with Checklists" does not search for those words.
    /// An empty query matches every note that the scope allows.
    static func matches(_ note: NoteSummary, query: String, scope: NoteSearchScope?) -> Bool {
        guard note.matchesSearch(query) else { return false }
        guard let scope else { return true }
        return note.matches(scope)
    }

    /// Whether any query word occurs in the title or the searchable text.
    ///
    /// An empty query matches. Comparison is case and diacritic insensitive.
    static func matches(title: String, text: String, query: String) -> Bool {
        let words = terms(in: query)
        guard !words.isEmpty else { return true }
        return words.contains { word in
            contains(word, in: title) || contains(word, in: text)
        }
    }

    /// The subtitle under Search. Zero matches read "No Results".
    static func resultSubtitle(matchCount: Int) -> String {
        switch matchCount {
        case 0:
            "No Results"
        case 1:
            "Found 1 note"
        default:
            "Found \(matchCount) notes"
        }
    }

    /// Ranges to paint in a distinct color.
    ///
    /// A whole phrase is one range. A word that matched on its own is its own range.
    static func highlightRanges(in text: String, query: String) -> [Range<String.Index>] {
        let words = terms(in: query)
        guard !words.isEmpty, !text.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var ranges = phrase.contains(" ") ? occurrences(of: phrase, in: text) : []
        for word in words {
            for range in occurrences(of: word, in: text) where !ranges.contains(where: { $0.overlaps(range) }) {
                ranges.append(range)
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// A section of `text` around the first match.
    ///
    /// The result starts with "..." when the match is not at the beginning.
    /// An empty string means the query was not found in `text`.
    static func excerpt(in text: String, query: String) -> String {
        let ranges = highlightRanges(in: text, query: query)
        guard let match = ranges.first else { return "" }
        let start = excerptStart(in: text, match: match)
        let end = text.index(start, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        let snippet = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard start > text.startIndex else { return snippet }
        return "..." + snippet
    }

    /// Measured in Notes, dark mode. Matched letters in a search result.
    static func matchColor(in appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 206.0 / 255, green: 112.0 / 255, blue: 214.0 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 168.0 / 255, green: 40.0 / 255, blue: 168.0 / 255, alpha: 1)
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        text.range(of: term, options: matchOptions) != nil
    }

    private static func occurrences(of term: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: term, options: matchOptions, range: start..<text.endIndex) {
            found.append(range)
            start = range.upperBound
        }
        return found
    }

    /// The excerpt begins at the match, or at one short word before it.
    private static func excerptStart(in text: String, match: Range<String.Index>) -> String.Index {
        let matchStart = match.lowerBound
        guard matchStart > text.startIndex else { return matchStart }
        var index = text.index(before: matchStart)
        while index > text.startIndex, text[index].isWhitespace {
            index = text.index(before: index)
        }
        if ".!?".contains(text[index]) { return matchStart }
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            if character.isWhitespace || ".!?".contains(character) { break }
            index = previous
        }
        let previousWord = text[index..<matchStart].trimmingCharacters(in: .whitespacesAndNewlines)
        if previousWord.count > 12 { return matchStart }
        return index
    }

    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
}

struct NoteDetail: Equatable, Identifiable {
    var id: String
    var title: String
    var bodyHTML: String
    var createdAtSource: String
    var modifiedAtSource: String
    var folderID: String?
}

struct LibrarySnapshot: Equatable {
    var profile: Profile
    var folders: [Folder]
    var notes: [NoteSummary]
}

struct EmbeddedAudio: Equatable, Identifiable {
    var storagePath: String
    var fileName: String

    var id: String { storagePath }
}
