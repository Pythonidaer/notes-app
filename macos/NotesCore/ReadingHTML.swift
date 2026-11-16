import Foundation

enum ReadingHTML {
    /// Plain text from the start of a note body, for the list preview.
    static func opening(in html: String) -> String {
        let plain = plainText(in: html)
        if plain.count <= 280 { return plain }
        return String(plain.prefix(280))
    }

    /// The note body as plain text, without the list preview's length limit.
    static func plainText(in html: String) -> String {
        let withoutScripts = replacing(
            #"<script\b[^>]*>[\s\S]*?</script>"#,
            in: html,
            options: [.caseInsensitive]
        )
        let withoutStyles = replacing(
            #"<style\b[^>]*>[\s\S]*?</style>"#,
            in: withoutScripts,
            options: [.caseInsensitive]
        )
        let withBreaks = replacing(#"<br\s*/?>"#, in: withoutStyles, with: " ", options: [.caseInsensitive])
        let withBlocks = replacing(
            #"</(?:p|div|li|h[1-6]|tr|blockquote|figcaption|pre)>"#,
            in: withBreaks,
            with: " ",
            options: [.caseInsensitive]
        )
        let withoutTags = replacing(#"<[^>]+>"#, in: withBlocks, with: " ")
        let decoded = decodedEntities(withoutTags)
        let collapsed = decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text a search compares, including attachment file names and display names.
    static func searchText(in html: String, displayNames: [String: String]) -> String {
        let plain = plainText(in: html)
        let names = embeddedAudio(in: html).flatMap { clip -> [String] in
            var parts = [clip.fileName]
            if let display = displayNames[clip.storagePath], !display.isEmpty {
                parts.append(display)
            }
            let segment = clip.storagePath
                .split(whereSeparator: { $0 == "/" || $0 == "\\" })
                .last
                .map(String.init) ?? ""
            if !segment.isEmpty, segment != clip.fileName {
                parts.append(segment)
            }
            return parts
        }
        return ([plain] + names).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `html` contains a checklist.
    static func containsChecklist(in html: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive]
        if html.range(of: "data-type=\"taskList\"", options: options) != nil { return true }
        return html.range(of: "data-type=\"taskItem\"", options: options) != nil
    }

    /// Whether `html` contains an attachment.
    ///
    /// Audio embeds, images, videos, and file links count. A web link does not.
    static func containsAttachment(in html: String) -> Bool {
        if !embeddedAudio(in: html).isEmpty { return true }
        let options: String.CompareOptions = [.caseInsensitive]
        if html.range(of: "<img", options: options) != nil { return true }
        if html.range(of: "<video", options: options) != nil { return true }
        return html.range(of: "href=\"file:", options: options) != nil
    }

    static func document(
        body: String,
        colorScheme: String,
        title: String? = nil,
        dateHeading: String? = nil
    ) -> String {
        let scheme = colorScheme == "dark" ? "dark" : "light"
        let dateBlock = dateHeading.map { value in
            "<p id=\"note-date\" class=\"note-date\">\(escaped(value))</p>"
        } ?? ""
        let titleBlock = title.map { value in
            "<p data-note-title=\"\">\(escaped(value))</p>"
        } ?? ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html { visibility: hidden; }
        html.fonts-ready { visibility: visible; }
        :root { color-scheme: \(scheme); }
        \(ReadingStyle.rules)
        </style>
        <script>
        document.fonts.ready.then(() => document.documentElement.classList.add("fonts-ready"));
        </script>
        </head>
        <body><div class="noteText">\(dateBlock)\(titleBlock)\(injectAudio(body))</div></body>
        </html>
        """
    }

    static func embeddedAudio(in html: String) -> [EmbeddedAudio] {
        figures(in: html).map { figure in
            let storagePath = attribute("data-nn-storage-path", in: figure.opening) ?? ""
            let named = attribute("data-nn-file-name", in: figure.opening) ?? ""
            let fileName = named.isEmpty
                ? (storagePath.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "Audio")
                : named
            return EmbeddedAudio(storagePath: storagePath, fileName: fileName)
        }
    }

    static func injectAudio(_ html: String) -> String {
        var result = html
        for figure in figures(in: html).reversed() {
            guard let storagePath = attribute("data-nn-storage-path", in: figure.opening),
                  !storagePath.isEmpty,
                  let full = Range(figure.range, in: result)
            else {
                continue
            }
            var markup = withoutCaption(String(result[full]))
            if markup.range(of: "<audio", options: .caseInsensitive) == nil,
               let close = markup.range(of: "</figure>", options: [.backwards, .caseInsensitive]) {
                markup.insert(contentsOf: audioPlayer(storagePath: storagePath), at: close.lowerBound)
            }
            result.replaceSubrange(full, with: markup)
        }
        return result
    }

    static func audioPlayer(storagePath: String) -> String {
        let encoded = percentEncodedPath(storagePath)
        return #"<audio controls preload="metadata" src="notes-audio://clip?path=\#(encoded)"></audio>"#
    }

    static func percentEncodedPath(_ storagePath: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return storagePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? storagePath
    }

    private static func withoutCaption(_ markup: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"<figcaption\b[^>]*>[\s\S]*?</figcaption>"#,
            options: [.caseInsensitive]
        ) else {
            return markup
        }
        let range = NSRange(markup.startIndex..<markup.endIndex, in: markup)
        return expression.stringByReplacingMatches(in: markup, range: range, withTemplate: "")
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with replacement: String = " ",
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func decodedEntities(_ text: String) -> String {
        var result = decodedNumericEntities(text)
        let named = [
            ("&nbsp;", " "),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&")
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func decodedNumericEntities(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) else {
            return text
        }
        var result = text
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in expression.matches(in: result, range: range).reversed() {
            guard let whole = Range(match.range, in: result),
                  let marker = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result)
            else {
                continue
            }
            let hex = !result[marker].isEmpty
            let number = String(result[digits])
            let scalar = hex ? UInt32(number, radix: 16) : UInt32(number)
            guard let scalar, let unicode = UnicodeScalar(scalar) else { continue }
            result.replaceSubrange(whole, with: String(Character(unicode)))
        }
        return result
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private struct FigureMatch {
        var range: NSRange
        var opening: String
    }

    private static func figures(in html: String) -> [FigureMatch] {
        guard let expression = try? NSRegularExpression(
            pattern: #"<figure\b([^>]*)>([\s\S]*?)</figure>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let openingRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let opening = String(html[openingRange])
            guard opening.contains("nn-audio-embed"), opening.contains("data-nn-storage-path") else {
                return nil
            }
            return FigureMatch(range: match.range, opening: opening)
        }
    }

    private static func attribute(_ name: String, in opening: String) -> String? {
        let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: name))="([^"]*)""#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: opening,
                range: NSRange(opening.startIndex..<opening.endIndex, in: opening)
              ),
              let valueRange = Range(match.range(at: 1), in: opening)
        else {
            return nil
        }
        return String(opening[valueRange])
    }
}

private enum ReadingStyle {
    static let rules = """
    html, body {
      background: transparent;
      color: CanvasText;
      max-width: 100%;
      min-height: 100%;
      margin: 0;
      overflow-x: clip;
      overscroll-behavior-x: none;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    }
    body {
      display: flex;
      flex-direction: column;
    }
    .noteText p.note-date {
      margin: 2px 0 0;
      padding: 0;
      text-align: center;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: \(NoteTypography.editorDateSize)px;
      font-weight: \(NoteTypography.cssWeight(NoteTypography.editorDateWeight));
      line-height: \(NoteTypography.editorDateLineHeight)px;
      color: color-mix(in srgb, CanvasText 50%, transparent);
    }
    .noteText {
      flex: 1 0 auto;
      min-width: 0;
      max-width: 100%;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: \(NoteTypography.editorBodySize)px;
      font-weight: \(NoteTypography.cssWeight(NoteTypography.editorBodyWeight));
      line-height: \(NoteTypography.editorBodyLineHeight)px;
      font-variant-ligatures: none;
      white-space: pre-wrap;
      overflow-wrap: break-word;
      color: CanvasText;
    }
    .noteText p { margin: 0.45rem 0; }
    .noteText p[data-note-title] {
      font-size: \(NoteTypography.editorTitleSize)px;
      font-weight: \(NoteTypography.cssWeight(NoteTypography.editorTitleWeight));
      line-height: \(NoteTypography.editorTitleLineHeight)px;
      margin: 8px 0 12px;
    }
    .noteText h1, .noteText h2, .noteText h3 {
      line-height: \(NoteTypography.editorHeadingLineHeight)px;
      margin: 0.7rem 0 0.35rem;
    }
    .noteText h1, .noteText h2 {
      font-size: \(NoteTypography.editorHeadingSize)px;
      font-weight: \(NoteTypography.cssWeight(NoteTypography.editorHeadingWeight));
    }
    .noteText h3 {
      font-size: \(NoteTypography.editorSubheadingSize)px;
      font-weight: \(NoteTypography.cssWeight(NoteTypography.editorSubheadingWeight));
    }
    .noteText pre {
      max-width: 100%;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: \(NoteTypography.editorMonospacedSize)px;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    .noteText img, .noteText video, .noteText figure, .noteText pre { max-width: 100%; }
    .noteText blockquote {
      margin: 0.6rem 0;
      padding-left: 0.75rem;
      border-left: 3px solid color-mix(in srgb, CanvasText 35%, transparent);
    }
    .noteText ul, .noteText ol { margin: 0.45rem 0; padding-left: 30px; }
    .noteText ul[data-list="dash"] { list-style-type: "–  "; }
    .noteText ul[data-type="taskList"] { list-style: none; padding-left: 0; }
    .noteText ul[data-type="taskList"] li {
      display: flex;
      gap: 0.4rem;
      align-items: flex-start;
    }
    .noteText figure { margin: 0.75rem 0; }
    .noteText .tableWrapper { max-width: 100%; margin: 0.75rem 0; }
    .noteText table {
      border-collapse: collapse;
      table-layout: fixed;
      width: 100%;
      margin: 0;
    }
    .noteText td, .noteText th {
      border: 1px solid color-mix(in srgb, CanvasText 25%, transparent);
      padding: 6px 8px;
      vertical-align: top;
      overflow-wrap: break-word;
    }
    .noteText td p, .noteText th p { margin: 0; }
    mark { color: inherit; background-color: transparent; border-radius: 3px; }
    mark[data-color="purple"] {
      color: light-dark(rgb(203, 48, 224), rgb(219, 52, 242)) !important;
      background-color: light-dark(rgb(203 48 224 / 15%), rgb(219 52 242 / 15%)) !important;
    }
    mark[data-color="pink"] {
      color: light-dark(rgb(255, 45, 85), rgb(255, 55, 95)) !important;
      background-color: light-dark(rgb(255 45 85 / 15%), rgb(255 55 95 / 15%)) !important;
    }
    mark[data-color="orange"] {
      color: light-dark(rgb(255, 141, 40), rgb(255, 146, 48)) !important;
      background-color: light-dark(rgb(255 141 40 / 15%), rgb(255 146 48 / 15%)) !important;
    }
    mark[data-color="mint"] {
      color: light-dark(rgb(0, 200, 179), rgb(0, 218, 195)) !important;
      background-color: light-dark(rgb(0 200 179 / 15%), rgb(0 218 195 / 15%)) !important;
    }
    mark[data-color="blue"] {
      color: light-dark(rgb(0, 136, 255), rgb(0, 145, 255)) !important;
      background-color: light-dark(rgb(0 136 255 / 15%), rgb(0 145 255 / 15%)) !important;
    }
    figure { margin: 0.75rem 0; }
    .nn-audio-caption { display: none; }
    audio { display: block; width: 100%; margin: 0.35rem 0; }
    """
}
