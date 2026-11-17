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
    NotificationCenter.default.post(name: .showNoteFind, object: event.window)
    return true
}

/// Find and replace for the open note. A panel over the note, under the note controls.
///
/// With Replace off, Done sits beside the match arrows. With Replace on, a second field
/// lines up under the find field, and Done moves to that lower row, under the checkbox.
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
    @FocusState private var fieldFocus: FindField?

    var body: some View {
        VStack(alignment: .leading, spacing: showsReplace ? 6 : 0) {
            HStack(spacing: showsReplace ? 12 : 8) {
                findField
                if showsReplace {
                    arrowSlot
                } else {
                    findSteps
                    Button("Done", action: onDone)
                        .controlSize(.small)
                    replaceToggle
                }
            }
            if showsReplace {
                HStack(alignment: .center, spacing: 12) {
                    replaceField
                    replaceActions
                }
            }
        }
        .onExitCommand(perform: onDone)
        .onAppear {
            if focused {
                fieldFocus = .query
            }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                fieldFocus = .query
            } else if fieldFocus == .query {
                fieldFocus = nil
            }
        }
        .onChange(of: fieldFocus) { _, newValue in
            let queryFocused = newValue == .query
            if focused != queryFocused {
                onFocusChange(queryFocused)
            }
        }
        .onChange(of: showsReplace) { _, shown in
            if !shown, fieldFocus == .replacement {
                fieldFocus = .query
            }
        }
    }

    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($fieldFocus, equals: .query)
                .focusEffectDisabled()
                .onSubmit(onNext)
                .accessibilityLabel("Find")
                .frame(maxWidth: .infinity, alignment: .leading)
            if !query.isEmpty {
                if !NoteSearch.terms(in: query).isEmpty {
                    Text("\(matchCount)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel("\(matchCount) matches")
                }
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: FindChrome.fieldHeight, alignment: .leading)
        .background(findFill, in: fieldShape)
        .overlay {
            if fieldFocus == .query {
                fieldShape.stroke(FindChrome.accent, lineWidth: 1)
            }
        }
    }

    /// Same fill and corner radius as the find field. The pink outline is the focused state.
    private var replaceField: some View {
        TextField("Replace", text: $replacement)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($fieldFocus, equals: .replacement)
            .focusEffectDisabled()
            .accessibilityLabel("Replace with")
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: FindChrome.fieldHeight, alignment: .leading)
            .background(findFill, in: fieldShape)
            .overlay {
                if fieldFocus == .replacement {
                    fieldShape.stroke(FindChrome.accent, lineWidth: 1)
                }
            }
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FindChrome.fieldRadius, style: .continuous)
    }

    /// One segmented control. The two chevrons share a single rounded shape.
    private var findSteps: some View {
        ControlGroup {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .help("Previous match")
            .accessibilityLabel("Previous match")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .help("Next match")
            .accessibilityLabel("Next match")
        }
        .controlSize(.small)
        .disabled(matchCount == 0)
    }

    /// As wide as Replace, All, and Done, so the chevrons sit halfway to the checkbox.
    private var arrowSlot: some View {
        replaceActions
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                HStack(spacing: 0) {
                    Spacer(minLength: 6)
                    findSteps
                    Spacer(minLength: 6)
                    replaceToggle
                }
            }
    }

    private var replaceToggle: some View {
        Toggle("Replace", isOn: $showsReplace)
            .toggleStyle(.checkbox)
            .tint(FindChrome.accent)
    }

    /// Replace, All, and Done. Small controls, with a gap before them and room under them.
    private var replaceActions: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button("Replace", action: onReplace)
                Button("All", action: onReplaceAll)
            }
            .controlSize(.small)
            .disabled(matchCount == 0)
            Button("Done", action: onDone)
                .controlSize(.small)
        }
    }

    private var findFill: Color {
        if colorScheme == .dark {
            Color(red: 46.0 / 255, green: 46.0 / 255, blue: 46.0 / 255)
        } else {
            Color(red: 246.0 / 255, green: 246.0 / 255, blue: 248.0 / 255)
        }
    }

}

private enum FindField: Hashable {
    case query
    case replacement
}

private enum FindChrome {
    static let accent = Color(red: 176.0 / 255, green: 92.0 / 255, blue: 186.0 / 255)
    /// Measured from the Notes find field. Rounder than a 5 pt rect, shorter than a capsule.
    static let fieldRadius: CGFloat = 8
    static let fieldHeight: CGFloat = 22
}
