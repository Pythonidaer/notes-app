import SwiftUI
import WebKit

struct EditorFormatState: Decodable, Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var block = "body"
    var highlight = ""
}

struct FindMatchSummary: Decodable, Equatable {
    var count = 0
    var index = 0
}

@MainActor
final class EditorBridge: ObservableObject {
    weak var webView: WKWebView?
    private var ready = false
    private var findQuery = ""

    func attach(_ webView: WKWebView) {
        self.webView = webView
        ready = false
    }

    func html() async throws -> String {
        guard let webView else {
            throw LibraryError.message("The editor is not open.")
        }
        try await waitUntilReady(webView)
        let value = try await webView.evaluateJavaScript("window.notesEditor.getHTML()")
        guard let html = value as? String else {
            throw LibraryError.message("The editor did not return the note.")
        }
        return html
    }

    func format(_ command: String) async {
        guard let webView, let literal = jsonLiteral(command) else { return }
        _ = try? await webView.evaluateJavaScript("window.notesEditor.format(\(literal))")
    }

    /// Puts the insertion point at the start of the note so typing begins in the title.
    func focusAtStart() async {
        guard let webView else { return }
        webView.window?.makeFirstResponder(webView)
        _ = try? await webView.evaluateJavaScript("window.notesEditor.focusStart()")
    }

    func insertHTML(_ html: String) async {
        guard let webView, let literal = jsonLiteral(html) else { return }
        _ = try? await webView.evaluateJavaScript("window.notesEditor.insertHTML(\(literal))")
    }

    /// Highlights `query` in the open note and returns how many matches there are.
    func updateFind(query: String) async -> FindMatchSummary {
        findQuery = query
        return await findCommand("find", query)
    }

    func findNext() async -> FindMatchSummary {
        await findCommand("findNext")
    }

    func findPrevious() async -> FindMatchSummary {
        await findCommand("findPrevious")
    }

    /// Replaces the current match. The note keeps the new text.
    func replaceFind(with replacement: String) async -> FindMatchSummary {
        await findCommand("replaceCurrent", replacement)
    }

    /// Replaces every match in the open note.
    func replaceEveryFind(with replacement: String) async -> FindMatchSummary {
        await findCommand("replaceAll", replacement)
    }

    /// Drops the find highlights. Replacements already made stay in the note.
    func clearFind() async {
        findQuery = ""
        guard let webView else { return }
        _ = try? await webView.evaluateJavaScript("window.notesEditor.clearFind()")
    }

    func formatState() async -> EditorFormatState {
        guard let webView else { return EditorFormatState() }
        guard let value = try? await webView.evaluateJavaScript("window.notesEditor.formatState()"),
              let json = value as? String,
              let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(EditorFormatState.self, from: data)
        else {
            return EditorFormatState()
        }
        return state
    }

    private func jsonLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setNote(title: String, html: String, dateHeading: String, in webView: WKWebView) async throws {
        try await waitUntilReady(webView)
        guard let titleLiteral = jsonLiteral(title),
              let htmlLiteral = jsonLiteral(html),
              let dateLiteral = jsonLiteral(dateHeading)
        else { return }
        _ = try await webView.evaluateJavaScript(
            "window.notesEditor.setNote(\(titleLiteral), \(htmlLiteral), \(dateLiteral))"
        )
        if !findQuery.isEmpty {
            _ = await updateFind(query: findQuery)
        }
    }

    private func findCommand(_ name: String, _ argument: String? = nil) async -> FindMatchSummary {
        guard let webView else { return FindMatchSummary() }
        let script: String
        if let argument, let literal = jsonLiteral(argument) {
            script = "window.notesEditor.\(name)(\(literal))"
        } else if argument == nil {
            script = "window.notesEditor.\(name)()"
        } else {
            return FindMatchSummary()
        }
        guard let value = try? await webView.evaluateJavaScript(script),
              let json = value as? String,
              let data = json.data(using: .utf8),
              let summary = try? JSONDecoder().decode(FindMatchSummary.self, from: data)
        else {
            return FindMatchSummary()
        }
        return summary
    }

    private func waitUntilReady(_ webView: WKWebView) async throws {
        if ready { return }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let value = try? await webView.evaluateJavaScript("window.notesEditorReady === true"),
               (value as? Bool) == true || (value as? NSNumber)?.boolValue == true {
                ready = true
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw LibraryError.message("The editor did not load.")
    }
}

private struct EditorChange: Decodable {
    var title: String
    var html: String
}

struct NoteEditorWebView: NSViewRepresentable {
    @ObservedObject var bridge: EditorBridge
    var noteID: String
    var title: String
    var html: String
    var dateHeading: String
    var colorScheme: String
    var onReady: () -> Void
    var onNoteChange: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            bridge: bridge,
            noteID: noteID,
            title: title,
            html: html,
            dateHeading: dateHeading,
            onReady: onReady,
            onNoteChange: onNoteChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "noteChanged")
        configuration.setURLSchemeHandler(context.coordinator.audio, forURLScheme: "notes-audio")
        let editorDirectory = Bundle.main.resourceURL?.appendingPathComponent("Editor", isDirectory: true)
        if let editorDirectory {
            let server = EditorFileServer(directory: editorDirectory)
            context.coordinator.server = server
            configuration.setURLSchemeHandler(server, forURLScheme: "notes-editor")
        }
        let webView = NotePageWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.appearance = NSAppearance(named: colorScheme == "dark" ? .darkAqua : .aqua)
        webView.navigationDelegate = context.coordinator
        confineScrollingToVertical(webView)
        bridge.attach(webView)
        if editorDirectory != nil {
            webView.load(URLRequest(url: URL(string: "notes-editor://page/index.html")!))
        } else {
            webView.loadHTMLString("<p>The editor page is missing.</p>", baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        bridge.webView = webView
        webView.appearance = NSAppearance(named: colorScheme == "dark" ? .darkAqua : .aqua)
        confineScrollingToVertical(webView)
        context.coordinator.onReady = onReady
        context.coordinator.onNoteChange = onNoteChange
        context.coordinator.dateHeading = dateHeading
        if context.coordinator.noteID != noteID {
            context.coordinator.noteID = noteID
            context.coordinator.sync = NoteEditorSync()
            context.coordinator.appliedHTML = nil
            context.coordinator.title = title
            context.coordinator.html = html
            guard context.coordinator.pageReady else { return }
            context.coordinator.loadNoteIntoEditor(in: webView, announceReady: true)
            return
        }
        guard context.coordinator.appliedHTML != nil else {
            context.coordinator.title = title
            context.coordinator.html = html
            guard context.coordinator.pageReady else { return }
            context.coordinator.loadNoteIntoEditor(in: webView, announceReady: true)
            return
        }
        guard let incoming = context.coordinator.sync.noteToApply(storedTitle: title, storedHTML: html) else {
            return
        }
        context.coordinator.title = incoming.title
        context.coordinator.html = incoming.html
        guard context.coordinator.pageReady else { return }
        context.coordinator.loadNoteIntoEditor(in: webView, announceReady: false)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var bridge: EditorBridge
        var noteID: String
        var title: String
        var html: String
        var dateHeading: String
        var onReady: () -> Void
        var onNoteChange: (String, String) -> Void
        var pageReady = false
        var appliedHTML: String?
        var sync = NoteEditorSync()
        var loadGeneration = 0
        var server: EditorFileServer?
        let audio = AudioSchemeHandler()

        init(
            bridge: EditorBridge,
            noteID: String,
            title: String,
            html: String,
            dateHeading: String,
            onReady: @escaping () -> Void,
            onNoteChange: @escaping (String, String) -> Void
        ) {
            self.bridge = bridge
            self.noteID = noteID
            self.title = title
            self.html = html
            self.dateHeading = dateHeading
            self.onReady = onReady
            self.onNoteChange = onNoteChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            confineScrollingToVertical(webView)
            loadNoteIntoEditor(in: webView, announceReady: true)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard appliedHTML != nil,
                  message.name == "noteChanged",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let change = try? JSONDecoder().decode(EditorChange.self, from: data)
            else { return }
            sync.didEdit(title: change.title, html: change.html)
            onNoteChange(change.title, change.html)
        }

        func loadNoteIntoEditor(in webView: WKWebView, announceReady: Bool) {
            loadGeneration += 1
            let generation = loadGeneration
            let noteID = noteID
            let title = title
            let html = html
            let dateHeading = dateHeading
            Task { @MainActor in
                do {
                    try await bridge.setNote(title: title, html: html, dateHeading: dateHeading, in: webView)
                    guard self.noteID == noteID, self.loadGeneration == generation else { return }
                    let first = appliedHTML == nil
                    appliedHTML = html
                    sync.didLoad(title: title, html: html)
                    if announceReady || first {
                        onReady()
                    }
                } catch {
                    guard self.noteID == noteID, self.loadGeneration == generation else { return }
                    sync.didFailToLoad()
                }
            }
        }
    }
}

/// The page's own find stays out. Command-F opens the note find bar.
final class NotePageWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if noteFindKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Keeps a note's web view on a vertical scroll. A sideways trackpad swipe does not move it.
func confineScrollingToVertical(_ view: NSView) {
    if let scrollView = view as? NSScrollView {
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
    }
    view.subviews.forEach(confineScrollingToVertical)
}
