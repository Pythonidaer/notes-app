import Foundation
import WebKit

final class EditorFileServer: NSObject, WKURLSchemeHandler {
    let directory: URL
    private let lock = NSLock()
    private var stopped: Set<ObjectIdentifier> = []

    init(directory: URL) {
        self.directory = directory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else {
            finish(urlSchemeTask, taskID) { $0.didFailWithError(AudioPathError.invalid) }
            return
        }
        let relative = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = directory.appendingPathComponent(relative.isEmpty ? "index.html" : relative)
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path == root.path || resolved.path.hasPrefix(rootPrefix) else {
            finish(urlSchemeTask, taskID) { $0.didFailWithError(AudioPathError.escapes) }
            return
        }
        do {
            let data = try Data(contentsOf: resolved)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": Self.mimeType(for: resolved),
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*"
                ]
            ) else {
                throw AudioPathError.missing
            }
            finish(urlSchemeTask, taskID) { task in
                task.didReceive(response)
                task.didReceive(data)
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

    private static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "js", "mjs":
            "text/javascript"
        case "css":
            "text/css"
        case "html":
            "text/html; charset=utf-8"
        case "svg":
            "image/svg+xml"
        default:
            "application/octet-stream"
        }
    }
}
