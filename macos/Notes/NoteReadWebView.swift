import SwiftUI
import WebKit

struct NoteReadWebView: NSViewRepresentable {
    var html: String
    var title: String?
    var dateHeading: String?
    var colorScheme: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.setURLSchemeHandler(context.coordinator.audio, forURLScheme: "notes-audio")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        confineScrollingToVertical(webView)
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        confineScrollingToVertical(webView)
        let next = document
        guard context.coordinator.lastDocument != next else { return }
        context.coordinator.lastDocument = next
        webView.loadHTMLString(next, baseURL: nil)
    }

    private var document: String {
        ReadingHTML.document(body: html, colorScheme: colorScheme, title: title, dateHeading: dateHeading)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let audio = AudioSchemeHandler()
        var lastDocument = ""

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
    }
}

final class AudioSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var stopped: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        do {
            guard let url = urlSchemeTask.request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let storagePath = components.queryItems?.first(where: { $0.name == "path" })?.value
            else {
                throw AudioPathError.invalid
            }
            let file = try AudioLocator.fileURL(
                storagePath: storagePath,
                roots: [AudioLocator.copyRoot, AudioLocator.audioRoot]
            )
            let data = try Data(contentsOf: file)
            let mime = mimeType(for: file)
            let header = urlSchemeTask.request.value(forHTTPHeaderField: "Range")
            let range = AudioByteRange.parse(header: header, total: data.count)
            let body = range?.body(from: data) ?? data
            let status = range?.status ?? 200
            var fields = [
                "Content-Type": mime,
                "Content-Length": String(body.count),
                "Accept-Ranges": "bytes"
            ]
            if let contentRange = range?.contentRange {
                fields["Content-Range"] = contentRange
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: fields
            ) else {
                throw AudioPathError.missing
            }
            finish(urlSchemeTask, taskID) { task in
                task.didReceive(response)
                task.didReceive(body)
                task.didFinish()
            }
        } catch {
            finish(urlSchemeTask, taskID) { $0.didFailWithError(error) }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stopped.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func finish(
        _ task: WKURLSchemeTask,
        _ taskID: ObjectIdentifier,
        _ send: (WKURLSchemeTask) -> Void
    ) {
        lock.lock()
        let skip = stopped.contains(taskID)
        lock.unlock()
        if !skip {
            send(task)
        }
    }

    private func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "m4a", "mp4":
            "audio/mp4"
        case "wav":
            "audio/wav"
        case "aac":
            "audio/aac"
        default:
            "audio/mpeg"
        }
    }
}
