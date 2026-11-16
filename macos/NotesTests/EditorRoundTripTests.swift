import AppKit
import ObjectiveC
import WebKit
import XCTest

final class EditorRoundTripTests: XCTestCase {
    private let session = EditorSession()

    @MainActor
    func testSavedHtmlReopensWithTasksColorAndAudio() async throws {
        let index = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Notes/Editor/index.html")
        let webView = try await session.load(index)
        try await session.evaluate("window.notesEditor.setHTML(\(session.json(fixtureHTML)))", in: webView)
        try await session.evaluate("window.notesEditor.insertText(' Swift proof.')", in: webView)
        let savedHTML = try await session.string("window.notesEditor.getHTML()", in: webView)
        assertFeatures(savedHTML)

        let (url, database) = try Fixture.importedLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let created = try database.createNote(folderID: nil)
        let stored = try database.saveNote(
            id: created.id,
            title: "Swift proof",
            bodyHTML: savedHTML,
            createdAtSource: created.createdAtSource
        )
        XCTAssertEqual(stored.bodyHTML, savedHTML)
        XCTAssertEqual(stored.title, "Swift proof")

        let reopenedView = try await session.load(index)
        try await session.evaluate("window.notesEditor.setHTML(\(session.json(stored.bodyHTML)))", in: reopenedView)
        let reopened = try await session.string("window.notesEditor.getHTML()", in: reopenedView)
        assertFeatures(reopened)
        XCTAssertEqual(try database.note(id: created.id).bodyHTML, savedHTML)
    }

    @MainActor
    func testTitleBlockUpdatesTheListTitle() async throws {
        let index = session.page
        let webView = try await session.load(index)
        try await session.evaluate(
            "window.notesEditor.setNote(\(try session.json("Thursday Off Cabot")), "
                + "\(try session.json("<p>Sing the song</p><p>Say no offense</p>")))",
            in: webView
        )
        let title = try await session.string("window.notesEditor.getTitle()", in: webView)
        XCTAssertEqual(title, "Thursday Off Cabot")
        let body = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(body.contains("data-note-title"), body)
        XCTAssertFalse(body.contains("Thursday Off Cabot"), body)
        XCTAssertTrue(body.contains("Sing the song"), body)

        try await session.evaluate("window.notesEditor.selectText(\"Say no offense\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"title\")", in: webView)
        let updatedTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
        XCTAssertEqual(updatedTitle, "Say no offense")
        let renamed = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(renamed.contains("<h1"), renamed)
        XCTAssertFalse(renamed.contains("data-note-title"), renamed)
        XCTAssertFalse(renamed.contains("Say no offense"), renamed)
        XCTAssertTrue(renamed.contains("Thursday Off Cabot"), renamed)
        XCTAssertTrue(renamed.contains("Sing the song"), renamed)

        try await session.evaluate("window.notesEditor.selectText(\"Sing the song\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"heading\")", in: webView)
        let headed = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(headed.contains("<h2"), headed)
        let keptTitle = try await session.string("window.notesEditor.getTitle()", in: webView)
        XCTAssertEqual(keptTitle, "Say no offense")

        try await session.evaluate("window.notesEditor.selectText(\"Sing the song\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"subheading\")", in: webView)
        let subheaded = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(subheaded.contains("<h3"), subheaded)

        try await session.evaluate("window.notesEditor.selectText(\"Sing the song\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"body\")", in: webView)
        let restored = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(restored.contains("<h3"), restored)
        XCTAssertTrue(restored.contains("Sing the song"), restored)

        let selected = try await session.string(
            """
            (() => {
              const title = document.querySelector("[data-note-title], .note-title");
              if (!title) return "missing";
              title.dispatchEvent(new MouseEvent("dblclick", { bubbles: true, cancelable: true }));
              return window.notesEditor.selectionText();
            })()
            """,
            in: webView
        )
        XCTAssertEqual(selected, "Say no offense")
    }

    @MainActor
    func testNoteScrollsVerticallyOnly() async throws {
        let webView = try await session.load(session.page)
        let html = "<h2>Previous goals:</h2><p>\(String(repeating: "word ", count: 80))</p><h3>Next</h3>"
        try await session.evaluate(
            "window.notesEditor.setNote(\(try session.json("Goals")), \(try session.json(html)))",
            in: webView
        )
        let script = """
        (() => { const root = document.documentElement; \
        const style = (selector) => getComputedStyle(document.querySelector(selector)); \
        const title = style("[data-note-title]"); const note = style(".noteText"); \
        const heading = style("h2"); const subheading = style("h3"); \
        return [root.scrollWidth <= root.clientWidth, title.fontSize, title.fontWeight, \
        note.fontSize, note.fontWeight, heading.fontSize, heading.fontWeight, \
        subheading.fontSize, subheading.fontWeight].join("|"); })()
        """
        let metrics = try await session.string(script, in: webView)
        XCTAssertEqual(metrics, "true|22px|700|13px|400|13px|700|13px|600")
    }

    @MainActor
    func testHighlightSetsNamedTextAndBackground() async throws {
        let index = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Notes/Editor/index.html")
        let webView = try await session.load(index, appearance: .aqua)
        try await session.evaluate(
            "window.notesEditor.setHTML(\"<p>Hello <span style=\\\"color: #2563eb\\\">blue</span> line</p>\")",
            in: webView
        )
        try await session.evaluate("window.notesEditor.selectAll()", in: webView)
        try await session.evaluate("window.notesEditor.format(\"highlight\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"color\")", in: webView)
        let untouched = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(untouched.contains("<mark"))
        XCTAssertFalse(untouched.contains("#ffe14d"))

        let saved = try await savedHighlightHTML(in: webView)
        let reopened = try await session.load(index, appearance: .aqua)
        try await session.evaluate("window.notesEditor.setHTML(\(try session.json(saved)))", in: reopened)
        let roundTrip = try await session.string("window.notesEditor.getHTML()", in: reopened)
        XCTAssertTrue(roundTrip.contains("data-color=\"blue\""), roundTrip)
        let roundTripPaint = try await highlightPaint(named: "blue", in: reopened)
        XCTAssertEqual(roundTripPaint.text, [0, 136, 255], roundTripPaint.raw)
        XCTAssertEqual(roundTripPaint.alpha, 0.15, accuracy: 0.02, roundTripPaint.raw)

        let dark = try await session.load(index, appearance: .darkAqua)
        try await session.evaluate("window.notesEditor.setHTML(\(try session.json(saved)))", in: dark)
        let mint = try await highlightPaint(named: "blue", in: dark)
        try await session.evaluate("window.notesEditor.selectAll()", in: dark)
        try await session.evaluate("window.notesEditor.format(\"highlight:mint\")", in: dark)
        let darkMint = try await highlightPaint(named: "mint", in: dark)
        XCTAssertEqual(darkMint.text, [0, 218, 195], darkMint.raw)
        XCTAssertEqual(darkMint.background, [0, 218, 195], darkMint.raw)
        XCTAssertEqual(darkMint.alpha, 0.15, accuracy: 0.02, darkMint.raw)
        XCTAssertNotEqual(mint.text, darkMint.text)

        try await session.evaluate("window.notesEditor.selectAll()", in: webView)
        try await session.evaluate("window.notesEditor.format(\"highlight:blue\")", in: webView)
        let cleared = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertFalse(cleared.contains("<mark"), cleared)
    }

    private struct HighlightPaint {
        var text: [Int]
        var background: [Int]
        var alpha: Double
        var raw: String
    }

    @MainActor
    private func highlightPaint(named name: String, in webView: WKWebView) async throws -> HighlightPaint {
        let raw = try await session.string(
            """
            (() => {
              const mark = document.querySelector('mark[data-color="\(name)"]');
              if (!mark) return "";
              const style = getComputedStyle(mark);
              const read = (value) => {
                const probe = document.createElement("canvas").getContext("2d");
                probe.fillStyle = "#000000";
                probe.fillStyle = value;
                const normalized = String(probe.fillStyle);
                const hex = /^#([0-9a-f]{6})$/i.exec(normalized);
                const rgba = /rgba?\\(([^)]+)\\)/.exec(normalized) || /rgba?\\(([^)]+)\\)/.exec(value);
                let rgb = [];
                let alpha = 1;
                if (hex) {
                  rgb = [0, 2, 4].map((index) => parseInt(hex[1].slice(index, index + 2), 16));
                }
                if (rgba) {
                  const parts = rgba[1].split(",").map((part) => Number(part.trim()));
                  if (!rgb.length) rgb = parts.slice(0, 3).map((part) => Math.round(part));
                  if (parts.length > 3) alpha = parts[3];
                }
                return rgb.concat([alpha]).join(",");
              };
              return read(style.color) + "|" + read(style.backgroundColor)
                + "|" + style.color + "|" + style.backgroundColor;
            })()
            """,
            in: webView
        )
        let pieces = raw.split(separator: "|").map(String.init)
        guard pieces.count >= 2 else {
            throw LibraryError.message("The highlight did not paint. \(raw)")
        }
        func channels(_ value: String) -> (rgb: [Int], alpha: Double) {
            let numbers = value.split(separator: ",").map { Double($0) ?? -1 }
            let rgb = numbers.prefix(3).map { Int($0.rounded()) }
            let alpha = numbers.count > 3 ? numbers[3] : 1
            return (rgb, alpha)
        }
        let text = channels(pieces[0])
        let background = channels(pieces[1])
        return HighlightPaint(text: text.rgb, background: background.rgb, alpha: background.alpha, raw: raw)
    }

    private func assertFeatures(_ html: String) {
        XCTAssertTrue(html.contains("Checklist"))
        XCTAssertTrue(html.contains("Swift proof"))
        XCTAssertTrue(html.contains("f000c610-c2e9-472b-a39b-7651188d396e_ErectileDysfunction.mp3"))
        XCTAssertTrue(
            html.contains("#2563eb")
                || html.contains("37, 99, 235")
                || html.contains("37,99,235")
                || html.lowercased().contains("2563eb")
        )
    }

    private var fixtureHTML: String {
        let blue = #"<p>Hello <span style="color: #2563eb">blue</span> line.</p>"#
        let tasks = """
        <ul data-type="taskList"><li data-checked="false" data-type="taskItem">\
        <label><input type="checkbox"><span></span></label><p>Checklist</p></li></ul>
        """
        let audioPath = "4d57c7e8-8a77-4661-8d1f-2d65ffc05388/composer-2/"
            + "f000c610-c2e9-472b-a39b-7651188d396e_ErectileDysfunction.mp3"
        let audio = #"<figure data-nn-storage-path="\#(audioPath)" data-nn-file-name="ErectileDysfunction.mp3" "#
            + #"data-nn-mime-type="audio/mpeg" class="nn-audio-embed">"#
            + #"<figcaption class="nn-audio-caption">ErectileDysfunction.mp3</figcaption></figure>"#
        return blue + tasks + audio
    }

    @MainActor
    private func savedHighlightHTML(in webView: WKWebView) async throws -> String {
        let colors = [
            ("purple", [203, 48, 224]),
            ("pink", [255, 45, 85]),
            ("orange", [255, 141, 40]),
            ("mint", [0, 200, 179]),
            ("blue", [0, 136, 255])
        ]
        var saved = ""
        for (name, components) in colors {
            try await session.evaluate("window.notesEditor.selectAll()", in: webView)
            try await session.evaluate("window.notesEditor.format(\"highlight:\(name)\")", in: webView)
            let html = try await session.string("window.notesEditor.getHTML()", in: webView)
            XCTAssertTrue(html.contains("data-color=\"\(name)\""), html)
            XCTAssertFalse(html.contains("0.42"), html)
            XCTAssertFalse(html.contains("#ffe14d"), html)
            XCTAssertTrue(
                html.contains("#2563eb") || html.contains("37, 99, 235") || html.contains("37,99,235"),
                html
            )
            let painted = try await highlightPaint(named: name, in: webView)
            XCTAssertEqual(painted.text, components, painted.raw)
            XCTAssertEqual(painted.background, components, painted.raw)
            XCTAssertEqual(painted.alpha, 0.15, accuracy: 0.02, painted.raw)
            saved = html
        }
        return saved
    }
}

final class EditorSession {
    private var retained: [WKWebView] = []
    private var windows: [NSWindow] = []
    private var servers: [EditorFileServer] = []

    var page: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Notes/Editor/index.html")
    }

    @MainActor
    func load(_ index: URL, appearance: NSAppearance.Name = .aqua) async throws -> WKWebView {
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path), "Build the editor page before opening it.")
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration(for: index)
        )
        let namedAppearance = NSAppearance(named: appearance)
        webView.appearance = namedAppearance
        retained.append(webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = namedAppearance
        window.contentView = webView
        windows.append(window)
        let delegate = NavigationWait()
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(webView, &editorDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.finished = { continuation.resume() }
            delegate.failed = { error in continuation.resume(throwing: error) }
            webView.load(URLRequest(url: URL(string: "notes-editor://page/index.html")!))
        }
        let deadline = Date().addingTimeInterval(20)
        var lastError = ""
        while Date() < deadline {
            do {
                let ready = try await webView.evaluateJavaScript("window.notesEditorReady === true")
                if (ready as? Bool) == true || (ready as? NSNumber)?.boolValue == true {
                    return webView
                }
            } catch {
                lastError = error.localizedDescription
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw LibraryError.message("The editor did not load. \(lastError)")
    }

    @MainActor
    func evaluate(_ script: String, in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(script)
    }

    @MainActor
    func string(_ script: String, in webView: WKWebView) async throws -> String {
        let value = try await webView.evaluateJavaScript(script)
        guard let html = value as? String else {
            throw LibraryError.message("The editor did not return the note.")
        }
        return html
    }

    func json(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private func configuration(for index: URL) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let server = EditorFileServer(directory: index.deletingLastPathComponent())
        servers.append(server)
        configuration.setURLSchemeHandler(server, forURLScheme: "notes-editor")
        return configuration
    }
}

private var editorDelegateKey: UInt8 = 0

private final class NavigationWait: NSObject, WKNavigationDelegate {
    var finished: (() -> Void)?
    var failed: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?()
        finished = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed?(error)
        failed = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed?(error)
        failed = nil
    }
}
