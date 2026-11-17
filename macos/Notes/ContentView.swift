import SwiftUI

struct ContentView: View {
    @StateObject private var store = LibraryStore()
    @StateObject private var noteWindows = NoteWindowPresenter()
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        Group {
            if let loadError = store.loadError {
                ContentUnavailableView(
                    "Notes",
                    systemImage: "square.and.pencil",
                    description: Text(loadError)
                )
            } else if store.snapshot == nil {
                ProgressView("Loading")
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    FolderSidebar(store: store, sidebarOpen: sidebarOpen)
                } content: {
                    NoteListColumn(store: store) { noteID in
                        noteWindows.openNoteInNewWindow(noteID)
                    }
                } detail: {
                    NoteDetailColumn(store: store)
                }
            }
        }
        .preferredColorScheme(store.colorSchemeName == "dark" ? .dark : .light)
        .task {
            noteWindows.connect(store)
            store.load()
        }
        .alert(
            store.confirmation?.title ?? "",
            isPresented: confirmationPresented
        ) {
            confirmButton
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.confirmation?.message ?? "")
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        let title = store.confirmation?.confirmTitle ?? "Delete"
        if store.confirmation?.isDestructive == false {
            Button(title) {
                store.confirmation?.action()
            }
        } else {
            Button(title, role: .destructive) {
                store.confirmation?.action()
            }
        }
    }

    /// The folder sidebar is open. A collapsed sidebar is `.doubleColumn` or `.detailOnly`.
    private var sidebarOpen: Bool {
        columnVisibility == .all || columnVisibility == .automatic
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { store.confirmation != nil },
            set: { isPresented in
                if !isPresented {
                    store.confirmation = nil
                }
            }
        )
    }
}
