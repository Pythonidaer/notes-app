import Foundation

/// Debounces edits from the open note and writes them after the pause.
@MainActor
final class NoteAutosave {
    /// How long an edit waits before it is written. A newer edit starts this wait over.
    var delay: Duration = .milliseconds(600)

    private var task: Task<Void, Never>?
    private var pendingNoteID: String?

    /// Records the editor's latest title and HTML for `note`.
    ///
    /// A pending save for this note is cancelled before the text is compared with
    /// the stored note. When the editor matches the stored note, that save stays
    /// cancelled. Any other edit waits `delay`, then calls `save` with the note id,
    /// title, HTML, and created date.
    func editorChanged(
        title: String,
        html: String,
        note: NoteDetail,
        save: @escaping @MainActor (_ id: String, _ title: String, _ bodyHTML: String, _ createdAtSource: String) -> Void
    ) {
        if pendingNoteID == note.id {
            cancelPendingSave()
        }
        guard html != note.bodyHTML || title != note.title else { return }
        cancelPendingSave()
        let id = note.id
        let titleNow = title
        let body = html
        let created = note.createdAtSource
        let delay = delay
        pendingNoteID = id
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            save(id, titleNow, body, created)
        }
    }

    private func cancelPendingSave() {
        task?.cancel()
        task = nil
        pendingNoteID = nil
    }
}
