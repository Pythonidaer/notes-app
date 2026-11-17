import SwiftUI

struct NoteDetailColumn: View {
    @ObservedObject var store: LibraryStore
    @StateObject private var editor = EditorBridge()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            NoteCanvas(
                editor: editor,
                note: openNote,
                isLoading: store.selectedNoteID != nil && openNote == nil,
                colorSchemeName: store.colorSchemeName,
                focusWhenReady: store.editing,
                onSave: { id, title, bodyHTML, createdAtSource in
                    store.saveNote(
                        id: id,
                        title: title,
                        bodyHTML: bodyHTML,
                        createdAtSource: createdAtSource
                    )
                },
                onEmptyClick: { store.startNoteInEmptyFolder() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if store.colorSchemeName == "dark" {
                NoteChrome.noteFill(for: store.colorSchemeName)
            }
        }
        .toolbar {
            ToolbarItem(id: "create-note", placement: .primaryAction) {
                Button(action: store.createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .help("Create a note")
                .accessibilityLabel("Create a note")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            NoteFormatToolbarItem(editor: editor, enabled: noteIsOpen, noteID: openNote?.id)
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(id: "delete-note", placement: .primaryAction) {
                Button(role: .destructive, action: store.askToDeleteNote) {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .disabled(!noteIsOpen)
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            noteSearchItem
        }
    }

    private var openNote: NoteDetail? {
        guard let note = store.note, note.id == store.selectedNoteID else { return nil }
        return note
    }

    private var noteIsOpen: Bool {
        openNote != nil
    }

    private var statusMessage: String? {
        store.status.isEmpty ? nil : store.status
    }

    @ToolbarContentBuilder
    private var noteSearchItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(id: "note-search", placement: .primaryAction) {
                NoteSearchField(text: $store.searchText, scope: $store.searchScope)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "note-search", placement: .primaryAction) {
                NoteSearchField(text: $store.searchText, scope: $store.searchScope)
                    .fixedSize()
            }
        }
    }
}
