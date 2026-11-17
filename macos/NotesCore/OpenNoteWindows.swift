import Foundation

/// Notes that have their own window.
///
/// Opening a note shows that same note. It does not copy the note or remove it from its folder.
/// Opening a note that already has a window asks for that window again. A note that is not in
/// the library does not open. A note that disappears closes its window.
struct OpenNoteWindows: Equatable {
    private(set) var noteIDs: [String] = []

    enum Result: Equatable {
        /// `noteID` was not open. Show a window for that same note.
        case present(String)
        /// `noteID` already has a window. Bring that window forward.
        case alreadyOpen(String)
        /// `noteID` is not in the library. Do not show a window.
        case missing
    }

    /// Records a window for `noteID` when that id is in `availableIDs`.
    ///
    /// The returned id is the requested note. This does not create another note.
    mutating func open(noteID: String, availableIDs: some Sequence<String>) -> Result {
        let available = Set(availableIDs)
        guard available.contains(noteID) else { return .missing }
        if noteIDs.contains(noteID) { return .alreadyOpen(noteID) }
        noteIDs.append(noteID)
        return .present(noteID)
    }

    /// Drops the window for `noteID`. The note itself stays where it is.
    mutating func close(noteID: String) {
        noteIDs.removeAll { $0 == noteID }
    }

    /// Closes windows whose notes are no longer in `availableIDs`, in the order the windows opened.
    mutating func closeNotesMissing(from availableIDs: some Sequence<String>) -> [String] {
        let available = Set(availableIDs)
        let closed = noteIDs.filter { !available.contains($0) }
        if !closed.isEmpty {
            noteIDs.removeAll { !available.contains($0) }
        }
        return closed
    }

    /// The window title for a stored note title.
    ///
    /// An empty title displays "New Note". That word is not a title to write back to the note.
    static func title(for storedTitle: String) -> String {
        NoteCalendar.listTitle(storedTitle)
    }
}

/// Decides when a stored note should replace the text in an open editor.
///
/// The editor that typed the text keeps its caret. Another editor showing that same note
/// takes the stored text once the save lands.
struct NoteEditorSync: Equatable {
    private var hasLoaded = false
    private var appliedTitle = ""
    private var appliedHTML = ""
    private var postedTitle: String?
    private var postedHTML: String?
    private var pendingTitle: String?
    private var pendingHTML: String?

    /// The editor is showing `title` and `html`.
    mutating func didLoad(title: String, html: String) {
        hasLoaded = true
        appliedTitle = title
        appliedHTML = html
        postedTitle = title
        postedHTML = html
        pendingTitle = nil
        pendingHTML = nil
    }

    /// The editor reported new typing. The stored note may still be the previous text.
    mutating func didEdit(title: String, html: String) {
        postedTitle = title
        postedHTML = html
    }

    /// A load did not land. The same stored note can be tried again.
    mutating func didFailToLoad() {
        pendingTitle = nil
        pendingHTML = nil
    }

    /// The stored note to load, or nil when this editor should keep what it is showing.
    ///
    /// A second call with the same new text returns nil until `didLoad` or `didFailToLoad`,
    /// so one save is not loaded twice. Typing that this editor has not saved stays put.
    /// The title is compared the way it is stored, with surrounding space removed.
    mutating func noteToApply(storedTitle: String, storedHTML: String) -> (title: String, html: String)? {
        guard hasLoaded else { return nil }
        if storedTitle == appliedTitle && storedHTML == appliedHTML {
            pendingTitle = nil
            pendingHTML = nil
            return nil
        }
        if isOwnSave(title: storedTitle, html: storedHTML) {
            appliedTitle = storedTitle
            appliedHTML = storedHTML
            postedTitle = storedTitle
            pendingTitle = nil
            pendingHTML = nil
            return nil
        }
        if hasUnsavedEdit { return nil }
        if pendingTitle == storedTitle && pendingHTML == storedHTML { return nil }
        pendingTitle = storedTitle
        pendingHTML = storedHTML
        return (storedTitle, storedHTML)
    }

    private func isOwnSave(title: String, html: String) -> Bool {
        guard let postedTitle, let postedHTML, html == postedHTML else { return false }
        if title == postedTitle { return true }
        return title == postedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedEdit: Bool {
        guard let postedTitle, let postedHTML else { return false }
        if postedHTML != appliedHTML { return true }
        let posted = postedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let applied = appliedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return posted != applied
    }
}
