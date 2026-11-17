import AppKit
import Combine
import SwiftUI

/// Shows notes in their own windows, using the library the main window already opened.
///
/// A window is the note only. Closing it closes the window. The note stays in its folder.
@MainActor
final class NoteWindowPresenter: ObservableObject {
    private var openNotes = OpenNoteWindows()
    private var controllers: [String: NoteWindowController] = [:]
    private weak var store: LibraryStore?
    private var snapshotObserver: AnyCancellable?

    func connect(_ store: LibraryStore) {
        guard self.store !== store else { return }
        self.store = store
        snapshotObserver = store.$snapshot.sink { [weak self] snapshot in
            MainActor.assumeIsolated {
                self?.closeMissingNotes(in: snapshot)
            }
        }
    }

    /// Opens `noteID` in a note window. The main window's selection and the note's folder stay as they are.
    ///
    /// A missing note does not open a window. A note that already has a window comes forward.
    func openNoteInNewWindow(_ noteID: String) {
        guard let store else { return }
        switch openNotes.open(noteID: noteID, availableIDs: store.notes.map(\.id)) {
        case .missing:
            return
        case .alreadyOpen(let noteID):
            controllers[noteID]?.bringForward()
        case .present(let noteID):
            guard store.note(id: noteID) != nil else {
                openNotes.close(noteID: noteID)
                return
            }
            let controller = NoteWindowController(
                noteID: noteID,
                store: store,
                cascadeIndex: controllers.count,
                onUserClose: { [weak self] in
                    self?.didClose(noteID)
                }
            )
            controllers[noteID] = controller
            controller.bringForward()
        }
    }

    private func didClose(_ noteID: String) {
        openNotes.close(noteID: noteID)
        controllers[noteID] = nil
    }

    private func closeMissingNotes(in snapshot: LibrarySnapshot?) {
        guard let snapshot, let store else { return }
        let closed = openNotes.closeNotesMissing(from: snapshot.notes.map(\.id))
        for noteID in closed {
            let controller = controllers.removeValue(forKey: noteID)
            controller?.closeBecauseNoteDisappeared()
        }
        for noteID in openNotes.noteIDs {
            let storedTitle = store.notes.first { $0.id == noteID }?.title ?? ""
            controllers[noteID]?.updateChrome(
                title: OpenNoteWindows.title(for: storedTitle),
                colorSchemeName: store.colorSchemeName
            )
        }
    }
}

@MainActor
final class NoteWindowController: NSWindowController, NSWindowDelegate {
    private var onUserClose: (() -> Void)?
    private var suppressClose = false

    init(noteID: String, store: LibraryStore, cascadeIndex: Int, onUserClose: @escaping () -> Void) {
        self.onUserClose = onUserClose
        let storedTitle = store.notes.first { $0.id == noteID }?.title ?? ""
        let window = NoteCursorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = OpenNoteWindows.title(for: storedTitle)
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: store.colorSchemeName == "dark" ? .darkAqua : .aqua)
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingController(rootView: NoteWindowView(store: store, noteID: noteID))
        hosting.sceneBridgingOptions = .toolbars
        window.contentViewController = hosting
        place(window, cascadeIndex: cascadeIndex)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func bringForward() {
        window?.makeKeyAndOrderFront(nil)
    }

    func updateChrome(title: String, colorSchemeName: String) {
        window?.title = title
        window?.appearance = NSAppearance(named: colorSchemeName == "dark" ? .darkAqua : .aqua)
    }

    /// Closes the window because the note is gone. This is not the user closing it.
    func closeBecauseNoteDisappeared() {
        suppressClose = true
        onUserClose = nil
        window?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard !suppressClose else { return }
            let close = onUserClose
            onUserClose = nil
            close?()
        }
    }

    private func place(_ window: NSWindow, cascadeIndex: Int) {
        let size = window.frame.size
        let anchor = NSApp.keyWindow?.frame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 200, y: 200, width: 1200, height: 800)
        let step = CGFloat(cascadeIndex) * 28
        let origin = NSPoint(
            x: anchor.midX - size.width / 2 + step,
            y: anchor.midY - size.height / 2 - step
        )
        window.setFrameOrigin(origin)
    }
}

/// One note, with the same editor, date heading, format pill, and find bar as the detail column.
private struct NoteWindowView: View {
    @ObservedObject var store: LibraryStore
    var noteID: String
    @StateObject private var editor = EditorBridge()
    @State private var detail: NoteDetail?

    init(store: LibraryStore, noteID: String) {
        self.store = store
        self.noteID = noteID
        _detail = State(initialValue: store.note(id: noteID))
    }

    var body: some View {
        NoteCanvas(
            editor: editor,
            note: detail,
            isLoading: detail == nil,
            colorSchemeName: store.colorSchemeName,
            focusWhenReady: false,
            onSave: { id, title, bodyHTML, createdAtSource in
                store.saveNote(
                    id: id,
                    title: title,
                    bodyHTML: bodyHTML,
                    createdAtSource: createdAtSource
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if store.colorSchemeName == "dark" {
                NoteChrome.noteFill(for: store.colorSchemeName)
            }
        }
        .background(alignment: .topLeading) {
            if let detail {
                WindowTitleWriter(title: OpenNoteWindows.title(for: detail.title))
                    .frame(width: 0, height: 0)
            }
        }
        .toolbar {
            NoteFormatToolbarItem(editor: editor, enabled: detail != nil, noteID: detail?.id)
        }
        .preferredColorScheme(store.colorSchemeName == "dark" ? .dark : .light)
        .onReceive(store.$snapshot) { _ in
            detail = store.note(id: noteID)
        }
    }
}

/// The note uses the text cursor. The hosting view was putting the arrow back on every move.
private final class NoteCursorWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard event.type == .mouseMoved || event.type == .cursorUpdate else { return }
        useTextCursor(for: event)
    }

    private func useTextCursor(for event: NSEvent) {
        guard let content = contentView else { return }
        let local = content.convert(event.locationInWindow, from: nil)
        guard content.bounds.contains(local) else { return }
        let superPoint = content.convert(local, to: content.superview)
        if let hit = content.hitTest(superPoint), control(in: hit, stoppingAt: content) {
            return
        }
        NSCursor.iBeam.set()
    }

    /// Buttons and fields keep their own cursors. The note itself does not.
    private func control(in view: NSView, stoppingAt root: NSView) -> Bool {
        var current: NSView? = view
        while let view = current, view !== root {
            if view is NSControl { return true }
            current = view.superview
        }
        return false
    }
}

/// Keeps the window title on the note's list title, including "New Note" for an empty title.
private struct WindowTitleWriter: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        let view = TitleView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TitleView else { return }
        guard view.title != title else { return }
        view.title = title
        view.apply()
    }

    private final class TitleView: NSView {
        var title = ""

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            window?.title = title
        }
    }
}
