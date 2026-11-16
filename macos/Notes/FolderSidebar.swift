import AppKit
import SwiftUI

struct FolderSidebar: View {
    @ObservedObject var store: LibraryStore
    var sidebarOpen: Bool
    @State private var newFolderShown = false
    @State private var newFolderName = "New Folder"

    var body: some View {
        FolderSourceList(store: store)
            .navigationTitle("Notes")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            .toolbar {
                if sidebarOpen {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newFolderName = "New Folder"
                            newFolderShown = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .help("New Folder")
                        .accessibilityLabel("New Folder")
                    }
                }
            }
            .sheet(isPresented: $newFolderShown) {
                NewFolderDialog(
                    name: $newFolderName,
                    onCancel: { newFolderShown = false },
                    onCreate: {
                        store.createFolder(name: newFolderName)
                        newFolderShown = false
                    }
                )
            }
    }
}

private struct NewFolderDialog: View {
    @Binding var name: String
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Folder")
                .font(.headline)
            SelectedNameField(text: $name, onSubmit: submit)
                .accessibilityLabel("Name")
                .frame(height: 24)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newFolderDialog")
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onCreate()
    }
}

private struct SelectedNameField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        field.setAccessibilityLabel("Name")
        field.setAccessibilityIdentifier("newFolderName")
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.selectAll(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        weak var field: NSTextField?
        private var didSelect = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func selectAll(_ field: NSTextField) {
            guard !didSelect else { return }
            didSelect = true
            focus(field, attempt: 0)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }

        private func focus(_ field: NSTextField, attempt: Int) {
            DispatchQueue.main.async {
                guard let window = field.window else {
                    if attempt < 10 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.focus(field, attempt: attempt + 1)
                        }
                    }
                    return
                }
                window.makeFirstResponder(field)
                let length = (field.stringValue as NSString).length
                field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
            }
        }
    }
}
