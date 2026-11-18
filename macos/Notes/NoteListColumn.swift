import SwiftUI

struct NoteListColumn: View {
    @ObservedObject var store: LibraryStore
    var onOpenInNewWindow: (String) -> Void = { _ in }

    var body: some View {
        let notes = store.notesMatchingSearch()
        let searching = store.isSearching
        let groups = searching ? searchGroups(notes) : NoteCalendar.arrange(notes, arrangement: store.listArrangement)
        let folderNames = Dictionary(uniqueKeysWithValues: store.folders.map { ($0.id, $0.name) })
        Group {
            if groups.isEmpty {
                Text(searching ? "No Results" : "No Notes")
                    .font(Font(NoteTypography.emptyNoteList))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.startNoteInEmptyFolder()
                    }
            } else {
                NoteTable(
                    groups: groups,
                    selectedID: store.selectedNoteID,
                    query: searching ? store.searchText : "",
                    showsResultFolder: searching,
                    folderNames: folderNames,
                    folders: store.folders,
                    onSelect: { store.selectNote($0) },
                    onMove: { store.moveNote($0, to: $1) },
                    onDuplicate: { store.duplicateNote($0) },
                    onDelete: { id in
                        guard store.selectNote(id) else { return }
                        store.askToDeleteNote()
                    },
                    onOpenInNewWindow: onOpenInNewWindow
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(searching ? "Search" : (store.selectedFolder?.name ?? "All notes"))
        .navigationSubtitle(searching ? NoteSearch.resultSubtitle(matchCount: notes.count) : noteCount(notes.count))
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 420)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                listMenu
            }
        }
    }

    /// One Notes heading, still sorted by the current list arrangement.
    private func searchGroups(_ notes: [NoteSummary]) -> [NoteCalendar.Group] {
        var arrangement = store.listArrangement
        arrangement.grouping = .groupsOff
        return NoteCalendar.arrange(notes, arrangement: arrangement).map { group in
            NoteCalendar.Group(key: "search", label: "Notes", notes: group.notes)
        }
    }

    private func noteCount(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }

    private var listMenu: some View {
        Menu {
            Menu {
                Picker("Sort By", selection: $store.listArrangement.field) {
                    Text("Default (Date Edited)").tag(NoteSortField.dateEditedDefault)
                    Text("Date Edited").tag(NoteSortField.dateEdited)
                    Text("Date Created").tag(NoteSortField.dateCreated)
                    Text("Title").tag(NoteSortField.title)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Picker("Order", selection: $store.listArrangement.direction) {
                    Text("Newest First").tag(NoteSortDirection.newestFirst)
                    Text("Oldest First").tag(NoteSortDirection.oldestFirst)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            Menu {
                Picker("Group By Date", selection: $store.listArrangement.grouping) {
                    Text("Default (On)").tag(NoteDateGrouping.onByDefault)
                    Text("On").tag(NoteDateGrouping.groupsOn)
                    Text("Off").tag(NoteDateGrouping.groupsOff)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Group By Date", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityLabel("More")
    }
}
