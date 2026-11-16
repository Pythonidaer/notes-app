import XCTest

final class AudioLocatorTests: XCTestCase {
    func testLastSegmentStaysInsideTheAudioFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let file = root.appendingPathComponent("clip.mp3")
        try Data("clip".utf8).write(to: file)
        let resolved = try AudioLocator.fileURL(
            storagePath: "user/scope/clip.mp3",
            root: root
        )
        XCTAssertEqual(resolved.standardizedFileURL.resolvingSymlinksInPath().path, file.resolvingSymlinksInPath().path)
        let sameFile = try AudioLocator.fileURL(storagePath: "../clip.mp3", root: root)
        XCTAssertEqual(sameFile.resolvingSymlinksInPath().path, file.resolvingSymlinksInPath().path)
        XCTAssertThrowsError(try AudioLocator.fileURL(storagePath: "missing.mp3", root: root)) { error in
            XCTAssertEqual(error as? AudioPathError, .missing)
        }
        XCTAssertThrowsError(try AudioLocator.fileURL(storagePath: ".", root: root))
    }

    func testSymlinkOutsideTheAudioFolderIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = directory.appendingPathComponent("outside.mp3")
        try Data("outside".utf8).write(to: outside)
        let root = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.mp3"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try AudioLocator.fileURL(storagePath: "link.mp3", root: root)) { error in
            XCTAssertEqual(error as? AudioPathError, .escapes)
        }
    }

    func testReadingHTMLKeepsTheAudioFigureAndAddsPlayback() {
        let html = [
            #"<figure data-nn-storage-path="user/scope/clip.mp3""#,
            #" data-nn-file-name="clip.mp3" class="nn-audio-embed">"#,
            "<figcaption>clip.mp3</figcaption></figure>"
        ].joined()
        let clips = ReadingHTML.embeddedAudio(in: html)
        XCTAssertEqual(clips.map(\.storagePath), ["user/scope/clip.mp3"])
        XCTAssertEqual(clips.map(\.fileName), ["clip.mp3"])
        let document = ReadingHTML.document(body: html, colorScheme: "dark")
        XCTAssertTrue(document.contains("notes-audio://clip?path="))
        XCTAssertTrue(document.contains(#"data-nn-storage-path="user/scope/clip.mp3""#))
        XCTAssertTrue(document.contains("<audio controls"))
        XCTAssertFalse(document.contains("<figcaption"))
        XCTAssertTrue(document.contains("clip.mp3"))
        XCTAssertTrue(document.contains("color-scheme: dark"))
    }

    func testSearchFindsAttachmentNamesThatAreNotTheTitle() {
        let path = "user/scope/a3037e83_Confidence.mp3"
        let html = """
        <figure data-nn-storage-path="\(path)" data-nn-file-name="Confidence.mp3" \
        class="nn-audio-embed"></figure><p>Hello there</p>
        """
        let note = NoteSummary(
            id: "confidence",
            title: "Set list",
            createdAtSource: "",
            modifiedAtSource: "",
            searchText: ReadingHTML.searchText(in: html, displayNames: [path: "Stage whisper"])
        )
        XCTAssertTrue(note.matchesSearch("Confidence.mp3"))
        XCTAssertTrue(note.matchesSearch("stage whisper"))
        XCTAssertTrue(note.matchesSearch("Hello there"))
        XCTAssertFalse(note.matchesSearch("Shared Notes"))
        XCTAssertTrue(note.matchesSearch("  "))
    }

    func testAudioByteRangeReadsASlice() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let first = AudioByteRange.parse(header: "bytes=0-1", total: data.count)
        XCTAssertEqual(first?.status, 206)
        XCTAssertEqual(first?.body(from: data), Data([0, 1]))
        XCTAssertEqual(first?.contentRange, "bytes 0-1/10")
        let rest = AudioByteRange.parse(header: "bytes=4-", total: data.count)
        XCTAssertEqual(rest?.body(from: data), Data([4, 5, 6, 7, 8, 9]))
        let suffix = AudioByteRange.parse(header: "bytes=-3", total: data.count)
        XCTAssertEqual(suffix?.body(from: data), Data([7, 8, 9]))
        XCTAssertEqual(AudioByteRange.parse(header: "bytes=20-30", total: data.count)?.status, 416)
        XCTAssertNil(AudioByteRange.parse(header: nil, total: data.count))
    }

    func testOpeningTextIsTheStartOfTheNote() {
        let html = "<p>One nice <b>thing</b> about living</p><p>More &amp; more</p>"
        XCTAssertEqual(ReadingHTML.opening(in: html), "One nice thing about living More & more")
        XCTAssertEqual(ReadingHTML.opening(in: "<p></p>"), "")
        XCTAssertEqual(ReadingHTML.opening(in: "<p>Tom &#39; Jerry</p>"), "Tom ' Jerry")
        let titled = ReadingHTML.document(
            body: "<p>Sing the song</p>",
            colorScheme: "dark",
            title: "Thursday <Off>",
            dateHeading: "July 31, 2025 at 7:09 PM"
        )
        XCTAssertTrue(titled.contains("data-note-title"))
        XCTAssertTrue(titled.contains("Thursday &lt;Off&gt;"))
        XCTAssertTrue(titled.contains("Sing the song"))
        XCTAssertTrue(titled.contains("note-date"))
        XCTAssertTrue(titled.contains("margin: 0.45rem 0"))
        let date = titled.range(of: "note-date")
        let title = titled.range(of: "data-note-title")
        XCTAssertNotNil(date)
        XCTAssertNotNil(title)
        if let date, let title {
            XCTAssertLessThan(date.lowerBound, title.lowerBound)
        }
    }

    func testExportedComedyAudioResolves() throws {
        let storage = """
        4d57c7e8-8a77-4661-8d1f-2d65ffc05388/composer-2/\
        f000c610-c2e9-472b-a39b-7651188d396e_ErectileDysfunction.mp3
        """
        let file = try AudioLocator.fileURL(storagePath: storage, root: AudioLocator.audioRoot)
        XCTAssertEqual(file.lastPathComponent, "f000c610-c2e9-472b-a39b-7651188d396e_ErectileDysfunction.mp3")
        XCTAssertTrue(file.path.hasPrefix(AudioLocator.audioRoot.resolvingSymlinksInPath().path))
    }

    private func makeRoot() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-audio-\(UUID().uuidString)", isDirectory: true)
        let root = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
