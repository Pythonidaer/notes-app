import AppKit
import SwiftUI

@main
struct NotesApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// One library window, as in Notes. A note can still open in its own window from the list.
    var body: some Scene {
        Window("Notes", id: "main") {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Find") {
                    NotificationCenter.default.post(name: .showNoteFind, object: NSApp.keyWindow)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
