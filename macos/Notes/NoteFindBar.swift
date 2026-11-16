import AppKit
import SwiftUI

extension Notification.Name {
    /// Command-F. Finds inside the open note and does not filter the note list.
    static let showNoteFind = Notification.Name("notes.showNoteFind")
}

/// Command-F opens the note find bar. The web view and the library search field both see the key.
func noteFindKeyEquivalent(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" else { return false }
    NotificationCenter.default.post(name: .showNoteFind, object: nil)
    return true
}

/// Find and replace for the open note. It sits above the note, under the note controls.
struct NoteFindBar: View {
    @Binding var query: String
    @Binding var replacement: String
    @Binding var showsReplace: Bool
    var matchCount: Int
    var focused: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onDone: () -> Void
    var onFocusChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var findWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                findField
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: FindFieldWidthKey.self, value: proxy.size.width)
                        }
                    }
                findStepButton("chevron.left", help: "Previous match", action: onPrevious)
                findStepButton("chevron.right", help: "Next match", action: onNext)
                Button("Done", action: onDone)
                Toggle("Replace", isOn: $showsReplace)
                    .toggleStyle(.checkbox)
                    .tint(FindChrome.accent)
            }
            if showsReplace {
                HStack(spacing: 8) {
                    TextField("Replace", text: $replacement)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(width: findWidth)
                        .background(findFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        }
                    Spacer(minLength: 16)
                    ControlGroup {
                        Button("Replace", action: onReplace)
                        Button("All", action: onReplaceAll)
                    }
                    .disabled(matchCount == 0)
                }
            }
        }
        .onPreferenceChange(FindFieldWidthKey.self) { findWidth = $0 }
        .onExitCommand(perform: onDone)
    }

    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            NoteFindQueryField(
                text: $query,
                isFocused: focused,
                onSubmit: onNext,
                onCancel: onDone,
                onFocusChange: onFocusChange
            )
            if !NoteSearch.terms(in: query).isEmpty {
                Text("\(matchCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(matchCount) matches")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(findFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FindChrome.accent, lineWidth: 1)
        }
    }

    private var findFill: Color {
        if colorScheme == .dark {
            Color(red: 25.0 / 255, green: 29.0 / 255, blue: 30.0 / 255)
        } else {
            Color(red: 246.0 / 255, green: 246.0 / 255, blue: 248.0 / 255)
        }
    }

    private func findStepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
        .disabled(matchCount == 0)
    }
}

private enum FindChrome {
    static let accent = Color(red: 176.0 / 255, green: 92.0 / 255, blue: 186.0 / 255)
}

private struct FindFieldWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The find field. The query is highlighted the same yellow as matches in the note.
struct NoteFindQueryField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.setAccessibilityLabel("Find")
        context.coordinator.paint(field, text: text)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.onFocusChange = onFocusChange
        if field.stringValue != text {
            context.coordinator.paint(field, text: text)
        }
        guard context.coordinator.focused != isFocused else { return }
        context.coordinator.focused = isFocused
        guard isFocused else { return }
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, onFocusChange: onFocusChange)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var onFocusChange: (Bool) -> Void
        var focused = false

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            onFocusChange: @escaping (Bool) -> Void
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onFocusChange = onFocusChange
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            onCancel()
            return true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            paint(field, text: field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onFocusChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            onFocusChange(false)
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
        }

        func paint(_ field: NSTextField, text: String) {
            let font = field.font ?? .systemFont(ofSize: NSFont.systemFontSize)
            if let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage {
                let range = NSRange(location: 0, length: storage.length)
                guard range.length > 0 else { return }
                storage.addAttributes(Self.highlightAttributes(font: font), range: range)
                return
            }
            if text.isEmpty {
                field.textColor = .labelColor
                field.stringValue = ""
                return
            }
            let painted = NSMutableAttributedString(string: text, attributes: Self.highlightAttributes(font: font))
            let editor = field.currentEditor()
            let selection = editor?.selectedRange ?? NSRange(location: painted.length, length: 0)
            field.attributedStringValue = painted
            field.currentEditor()?.selectedRange = selection
        }

        private static func highlightAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.11, alpha: 1),
                .backgroundColor: NSColor(srgbRed: 248.0 / 255, green: 220.0 / 255, blue: 48.0 / 255, alpha: 1)
            ]
        }
    }
}
