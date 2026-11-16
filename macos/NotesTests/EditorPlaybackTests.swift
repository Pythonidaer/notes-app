import WebKit
import XCTest

final class EditorPlaybackTests: XCTestCase {
    private let session = EditorSession()

    @MainActor
    func testAudioFigureShowsAPlayerAndKeepsTheStoragePath() async throws {
        let path = "user/scope/Confidence.mp3"
        let html = """
        <figure data-nn-storage-path="\(path)" data-nn-file-name="Confidence.mp3" \
        class="nn-audio-embed"><figcaption>Confidence.mp3</figcaption></figure>
        """
        let webView = try await session.load(session.page)
        try await session.evaluate("window.notesEditor.setHTML(\(try session.json(html)))", in: webView)
        let saved = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(saved.contains("data-nn-storage-path=\"\(path)\""), saved)
        let visible = try await session.string(
            """
            (() => {
              const audio = document.querySelector("figure.nn-audio-embed audio");
              const caption = document.querySelector("figcaption");
              const src = audio ? audio.getAttribute("src") : "";
              return [audio ? "audio" : "missing", caption ? "caption" : "player", src].join("|");
            })()
            """,
            in: webView
        )
        XCTAssertTrue(visible.hasPrefix("audio|player|notes-audio://clip?path="), visible)
        XCTAssertTrue(visible.contains("Confidence.mp3"), visible)
    }

    @MainActor
    func testTableInsertsTwoByTwo() async throws {
        let webView = try await session.load(session.page)
        try await session.evaluate(
            "window.notesEditor.setNote(\(try session.json("Title")), \(try session.json("<p>Body text</p>")))",
            in: webView
        )
        try await session.evaluate("window.notesEditor.selectText(\"Body text\")", in: webView)
        try await session.evaluate("window.notesEditor.format(\"table\")", in: webView)
        let html = try await session.string("window.notesEditor.getHTML()", in: webView)
        XCTAssertTrue(html.contains("<table"), html)
        XCTAssertEqual(html.components(separatedBy: "<td").count - 1, 4, html)
        let title = try await session.string("window.notesEditor.getTitle()", in: webView)
        XCTAssertEqual(title, "Title")
    }
}
