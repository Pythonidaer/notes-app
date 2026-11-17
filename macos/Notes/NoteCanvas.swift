import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NoteChrome {
    static func noteFill(for colorSchemeName: String) -> Color {
        if colorSchemeName == "dark" {
            Color(red: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255)
        } else {
            Color(nsColor: .textBackgroundColor)
        }
    }

    static func barFill(for colorSchemeName: String) -> Color {
        if colorSchemeName == "dark" {
            Color(red: 35.0 / 255, green: 40.0 / 255, blue: 43.0 / 255)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

/// The note page shared by the detail column and a note window: editor, date heading, and find.
struct NoteCanvas: View {
    @ObservedObject var editor: EditorBridge
    var note: NoteDetail?
    var isLoading: Bool
    var colorSchemeName: String
    /// Moves the caret to the title when the editor first appears. Used for a new note.
    var focusWhenReady: Bool
    var onSave: (_ id: String, _ title: String, _ bodyHTML: String, _ createdAtSource: String) -> Void
    var onEmptyClick: () -> Void = {}

    /// Stays true after the first paint so a note click does not swap in the reading page.
    @State private var editorReady = false
    @State private var autosave = NoteAutosave()
    @State private var findBarShown = false
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var replaceShown = false
    @State private var findCount = 0
    @State private var findFocused = false
    /// Height of the find panel, so the note starts under it instead of running through it.
    @State private var findPanelHeight: CGFloat = 0
    @State private var hostWindow: NSWindow?

    var body: some View {
        noteContent
            .padding(.top, findInset)
            .overlay(alignment: .top) {
                if findBarShown, note != nil {
                    findPanel
                }
            }
            .onPreferenceChange(FindPanelHeightKey.self) { findPanelHeight = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: note?.id) { _, id in
                if id == nil {
                    editorReady = false
                    closeFindBar()
                }
            }
            .onChange(of: findQuery) { _, _ in
                guard findBarShown else { return }
                Task { await refreshFind() }
            }
            .onChange(of: findBarShown) { _, shown in
                if !shown { findPanelHeight = 0 }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showNoteFind)) { notification in
                guard let hostWindow else { return }
                guard (notification.object as? NSWindow) === hostWindow else { return }
                showFindBar()
            }
            .background(alignment: .topLeading) {
                HostWindowReader { hostWindow = $0 }
                    .frame(width: 0, height: 0)
            }
    }

    private var noteContent: some View {
        Group {
            if let note {
                ZStack {
                    if !editorReady {
                        NoteReadWebView(
                            html: note.bodyHTML,
                            title: note.title,
                            dateHeading: NoteCalendar.heading(note.createdAtSource),
                            colorScheme: colorSchemeName
                        )
                    }
                    NoteEditorWebView(
                        bridge: editor,
                        noteID: note.id,
                        title: note.title,
                        html: note.bodyHTML,
                        dateHeading: NoteCalendar.heading(note.createdAtSource),
                        colorScheme: colorSchemeName,
                        onReady: {
                            revealEditor()
                            guard focusWhenReady else { return }
                            Task { await editor.focusAtStart() }
                        },
                        onNoteChange: { title, html in
                            guard let note = self.note else { return }
                            autosave.editorChanged(
                                title: title,
                                html: html,
                                note: note
                            ) { id, title, bodyHTML, createdAtSource in
                                onSave(id, title, bodyHTML, createdAtSource)
                            }
                        }
                    )
                    .opacity(editorReady ? 1 : 0)
                    .allowsHitTesting(editorReady)
                    .animation(nil, value: editorReady)
                }
                .animation(nil, value: editorReady)
                .padding(.horizontal, 20)
            } else if isLoading {
                ProgressView("Loading")
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEmptyClick)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var findPanel: some View {
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
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoteChrome.barFill(for: colorSchemeName))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: FindPanelHeightKey.self, value: proxy.size.height)
            }
        }
    }

    /// The note starts below the panel. Until the panel is measured, a stand-in keeps the title uncovered.
    private var findInset: CGFloat {
        guard findBarShown, note != nil else { return 0 }
        if findPanelHeight > 1 { return findPanelHeight }
        return replaceShown ? 80 : 46
    }

    private func revealEditor() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            editorReady = true
        }
    }

    private func showFindBar() {
        guard note != nil else { return }
        findBarShown = true
        findFocused = true
        Task { await refreshFind() }
    }

    private func closeFindBar() {
        guard findBarShown || !findQuery.isEmpty else {
            findBarShown = false
            return
        }
        findBarShown = false
        findCount = 0
        findFocused = false
        Task { await editor.clearFind() }
    }

    private func refreshFind() async {
        guard findBarShown else { return }
        findCount = await editor.updateFind(query: findQuery).count
    }

    private func stepFind(by delta: Int) async {
        let summary = delta < 0 ? await editor.findPrevious() : await editor.findNext()
        findCount = summary.count
    }

    private func replaceFind(everyMatch: Bool) async {
        let summary = everyMatch
            ? await editor.replaceEveryFind(with: replaceQuery)
            : await editor.replaceFind(with: replaceQuery)
        findCount = summary.count
    }
}

/// Aa, tasks, table, and attachments in one pill. Aa is the leftmost button.
struct NoteFormatToolbarItem: ToolbarContent {
    var editor: EditorBridge
    var enabled: Bool
    var noteID: String?

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(id: "format", placement: .primaryAction) {
                NoteFormatControls(editor: editor, enabled: enabled, noteID: noteID)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "format", placement: .primaryAction) {
                NoteFormatControls(editor: editor, enabled: enabled, noteID: noteID)
            }
        }
    }
}

struct NoteFormatControls: View {
    var editor: EditorBridge
    var enabled: Bool
    var noteID: String?

    @State private var formatMenuShown = false
    @State private var formatMenuClosedAt = Date.distantPast
    @State private var highlightColor = NoteHighlight.purple

    var body: some View {
        HStack(spacing: 2) {
            formatButton
            commandButton("checklist", help: "Tasks", label: "Tasks") {
                Task { await editor.format("task") }
            }
            commandButton("tablecells", help: "Table", label: "Table") {
                Task { await editor.format("table") }
            }
            attachmentMenu
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(pillFill)
                .overlay {
                    Capsule().strokeBorder(pillStroke, lineWidth: 0.5)
                }
        }
        .fixedSize()
        .onChange(of: noteID) { _, _ in
            formatMenuShown = false
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
                .frame(width: 36, height: 26)
        }
        .buttonStyle(.plain)
        .help("Format")
        .accessibilityLabel("Format")
        .disabled(!enabled)
        .popover(isPresented: $formatMenuShown, arrowEdge: .top) {
            FormatStyleMenu(editor: editor, chosen: $highlightColor)
        }
        .onChange(of: formatMenuShown) { _, shown in
            if !shown {
                formatMenuClosedAt = Date()
            }
        }
    }

    private func commandButton(
        _ symbol: String,
        help: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 32, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .disabled(!enabled)
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
                .font(.system(size: 15))
                .frame(width: 32, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Attachment")
        .accessibilityLabel("Attachment")
        .disabled(!enabled)
    }

    @Environment(\.colorScheme) private var colorScheme

    /// A single capsule, matching the Notes format control. Dark and light each get their own fill.
    private var pillFill: Color {
        colorScheme == .dark
            ? Color(red: 58 / 255, green: 58 / 255, blue: 62 / 255)
            : Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255)
    }

    private var pillStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    /// Recording stays out of this app. The row matches the Notes attachment menu and does not start a recording.
    private func recordAudio() {}

    private func choosePhotoOrVideo() {
        presentAttachmentPanel(types: [.image, .movie])
    }

    private func attachFile() {
        presentAttachmentPanel(types: nil)
    }

    private func presentAttachmentPanel(types: [UTType]?) {
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

    private static func escapedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

private struct FindPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reads the window that owns this note, so Command-F opens find in that window only.
private struct HostWindowReader: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HostWindowView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HostWindowView)?.onChange = onChange
    }
}

private final class HostWindowView: NSView {
    var onChange: (NSWindow?) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onChange(window)
    }
}
