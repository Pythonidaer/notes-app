import AppKit
import SwiftUI

@main
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
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
