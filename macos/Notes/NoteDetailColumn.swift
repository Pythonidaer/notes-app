import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailColumn: View {
    @ObservedObject var store: LibraryStore
    @StateObject private var editor = EditorBridge()
    @State private var latestTitle = ""
    @State private var latestHTML = ""
    /// Stays true after the first paint so a note click does not disable Aa or swap in the reading page.
    @State private var editorReady = false
    @State private var formatMenuShown = false
    @State private var formatMenuClosedAt = Date.distantPast
    @State private var highlightColor = NoteHighlight.purple
    @State private var saveTask: Task<Void, Never>?
    @State private var findBarShown = false
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var replaceShown = false
    @State private var findCount = 0
    @State private var findFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if findBarShown, noteIsOpen {
                NoteFindBar(
                    query: $findQuery,
                    replacement: $replaceQuery,
                    showsReplace: $replaceShown,
                    matchCount: findCount,
                    focused: findFocused,
                    onPrevious: { Task { await stepFind(by: -1) } },
                    onNext: { Task { await stepFind(by: 1) } },
                    onReplace: { Task { await replaceFind(everyMatch: false) } },
                    onReplaceAll: { Task { await replaceFind(everyMatch: true) } },
                    onDone: closeFindBar,
                    onFocusChange: { findFocused = $0 }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            if let note = store.note, note.id == store.selectedNoteID {
                ZStack {
                    NoteReadWebView(
                        html: note.bodyHTML,
                        title: note.title,
                        dateHeading: NoteCalendar.heading(note.createdAtSource),
                        colorScheme: store.colorSchemeName
                    )
                    .opacity(editorReady ? 0 : 1)
                    .allowsHitTesting(!editorReady)
                    NoteEditorWebView(
                        bridge: editor,
                        noteID: note.id,
                        title: note.title,
                        html: note.bodyHTML,
                        dateHeading: NoteCalendar.heading(note.createdAtSource),
                        colorScheme: store.colorSchemeName,
                        onReady: revealEditor,
                        onNoteChange: { title, html in
                            latestTitle = title
                            latestHTML = html
                            guard let note = store.note,
                                  html != note.bodyHTML || title != note.title
                            else { return }
                            scheduleSave()
                        }
                    )
                    .opacity(editorReady ? 1 : 0)
                    .allowsHitTesting(editorReady)
                    .animation(nil, value: editorReady)
                }
                .animation(nil, value: editorReady)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.selectedNoteID != nil {
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a note", systemImage: "note.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.note?.id) { _, _ in
            loadDraft()
            if store.note?.id == nil {
                closeFindBar()
            }
        }
        .onChange(of: findQuery) { _, _ in
            guard findBarShown else { return }
            Task { await refreshFind() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNoteFind)) { _ in
            showFindBar()
        }
        .background {
            if store.colorSchemeName == "dark" {
                Color(red: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255)
            }
        }
        .toolbar {
            ToolbarItem(id: "create-note", placement: .primaryAction) {
                Button(action: store.createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .help("Create a note")
                .accessibilityLabel("Create a note")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(id: "format", placement: .primaryAction) {
                ControlGroup {
                    formatButton
                    Button {
                        Task { await editor.format("task") }
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .help("Tasks")
                    .disabled(!noteIsOpen)
                    Button {
                        Task { await editor.format("table") }
                    } label: {
                        Image(systemName: "tablecells")
                    }
                    .help("Table")
                    .accessibilityLabel("Table")
                    .disabled(!noteIsOpen)
                    attachmentMenu
                }
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(id: "delete-note", placement: .primaryAction) {
                Button(role: .destructive, action: store.askToDeleteNote) {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .disabled(!noteIsOpen)
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            noteSearchItem
        }
        .onAppear {
            loadDraft()
        }
    }

    private var noteIsOpen: Bool {
        store.note?.id == store.selectedNoteID
    }

    @ToolbarContentBuilder
    private var noteSearchItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(id: "note-search", placement: .primaryAction) {
                NoteSearchField(text: $store.searchText, scope: $store.searchScope)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "note-search", placement: .primaryAction) {
                NoteSearchField(text: $store.searchText, scope: $store.searchScope)
                    .fixedSize()
            }
        }
    }

    private func revealEditor() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            editorReady = true
        }
    }

    private var formatButton: some View {
        Button {
            if Date().timeIntervalSince(formatMenuClosedAt) < 0.3 {
                return
            }
            formatMenuShown.toggle()
        } label: {
            FormatAaLabel()
        }
        .help("Format")
        .accessibilityLabel("Format")
        .disabled(!noteIsOpen)
        .popover(isPresented: $formatMenuShown, arrowEdge: .top) {
            FormatStyleMenu(editor: editor, chosen: $highlightColor)
        }
        .onChange(of: formatMenuShown) { _, shown in
            if !shown {
                formatMenuClosedAt = Date()
            }
        }
    }

    private var statusMessage: String? {
        store.status.isEmpty ? nil : store.status
    }

    private var attachmentMenu: some View {
        Menu {
            Button(action: choosePhotoOrVideo) {
                Label("Choose Photo or Video", systemImage: "photo.on.rectangle")
            }
            Button(action: recordAudio) {
                Label("Record Audio", systemImage: "mic")
            }
            Button(action: attachFile) {
                Label("Attach File", systemImage: "doc")
            }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuIndicator(.hidden)
        .help("Attachment")
        .accessibilityLabel("Attachment")
        .disabled(!noteIsOpen)
    }

}

extension NoteDetailColumn {
    /// Recording stays out of this app. The row matches the Notes attachment menu and does not start a recording.
    fileprivate func recordAudio() {}

    fileprivate func choosePhotoOrVideo() {
        presentAttachmentPanel(types: [.image, .movie])
    }

    fileprivate func attachFile() {
        presentAttachmentPanel(types: nil)
    }

    fileprivate func presentAttachmentPanel(types: [UTType]?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let types {
            panel.allowedContentTypes = types
        }
        guard panel.runModal() == .OK else { return }
        let html = panel.urls.map { url in
            let name = Self.escapedText(url.lastPathComponent)
            let href = Self.escapedText(url.absoluteString)
            return "<a href=\"\(href)\">\(name)</a>"
        }.joined(separator: " ")
        guard !html.isEmpty else { return }
        Task { await editor.insertHTML(html) }
    }

    fileprivate static func escapedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    fileprivate func showFindBar() {
        guard noteIsOpen else { return }
        findBarShown = true
        findFocused = true
        Task { await refreshFind() }
    }

    fileprivate func closeFindBar() {
        guard findBarShown || !findQuery.isEmpty else {
            findBarShown = false
            return
        }
        findBarShown = false
        findCount = 0
        findFocused = false
        Task { await editor.clearFind() }
    }

    fileprivate func refreshFind() async {
        guard findBarShown else { return }
        findCount = await editor.updateFind(query: findQuery).count
    }

    fileprivate func stepFind(by delta: Int) async {
        let summary = delta < 0 ? await editor.findPrevious() : await editor.findNext()
        findCount = summary.count
    }

    fileprivate func replaceFind(everyMatch: Bool) async {
        let summary = everyMatch
            ? await editor.replaceEveryFind(with: replaceQuery)
            : await editor.replaceFind(with: replaceQuery)
        findCount = summary.count
    }

    fileprivate func loadDraft() {
        formatMenuShown = false
        latestTitle = store.note?.title ?? ""
        latestHTML = store.note?.bodyHTML ?? ""
        if store.note?.id != store.selectedNoteID {
            editorReady = false
        }
    }

    fileprivate func scheduleSave() {
        guard let id = store.note?.id else { return }
        let titleNow = latestTitle
        let created = store.note?.createdAtSource ?? ""
        let body = latestHTML
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            store.saveNote(id: id, title: titleNow, bodyHTML: body, createdAtSource: created)
        }
    }

}

/// The capital A and smaller lowercase a on the Notes format button.
private struct FormatAaLabel: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -0.5) {
            Text("A")
                .font(.system(size: 17, weight: .medium))
            Text("a")
                .font(.system(size: 12, weight: .regular))
        }
        .foregroundStyle(.primary)
        .fixedSize()
        .accessibilityHidden(true)
    }
}
