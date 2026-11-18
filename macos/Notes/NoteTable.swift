import AppKit
import SwiftUI

private let headerTextInset: CGFloat = 16

struct NoteTable: NSViewRepresentable {
    var groups: [NoteCalendar.Group]
    var selectedID: String?
    var query: String = ""
    /// Search results show the folder name, including a suggestion with no typed words.
    var showsResultFolder: Bool = false
    var folderNames: [String: String] = [:]
    var folders: [Folder] = []
    /// Opens the clicked note. Returns false when it could not open, and the previous row is selected again.
    var onSelect: (String) -> Bool
    var onMove: (String, String) -> Void = { _, _ in }
    var onDuplicate: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onOpenInNewWindow: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NoteListView()
        table.headerView = nil
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.allowsColumnResizing = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .none
        table.style = .plain
        table.rowSizeStyle = .custom
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        let column = NSTableColumn(identifier: Coordinator.columnID)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table
        context.coordinator.startTrackingClicks()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onMove = onMove
        context.coordinator.onDelete = onDelete
        context.coordinator.onDuplicate = onDuplicate
        context.coordinator.onOpenInNewWindow = onOpenInNewWindow
        context.coordinator.apply(
            groups: groups,
            selectedID: selectedID,
            query: query,
            showsResultFolder: showsResultFolder,
            folderNames: folderNames,
            folders: folders
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        static let columnID = NSUserInterfaceItemIdentifier("note")

        weak var table: NoteListView?
        private var clickMonitor: Any?
        var onSelect: (String) -> Bool = { _ in true }
        var onMove: (String, String) -> Void = { _, _ in }
        var onDelete: (String) -> Void = { _ in }
        var onDuplicate: (String) -> Void = { _ in }
        var onOpenInNewWindow: (String) -> Void = { _ in }
        private var contextNoteID: String?
        private var rows: [Row] = []
        private var signature = ""
        private var selectedID: String?
        private var query = ""
        private var showsResultFolder = false
        private var folderNames: [String: String] = [:]
        private var folders: [Folder] = []
        private var suppress = false

        deinit {
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
        }

        /// Clicks in the list use the accent fill. A click in the note, or anywhere else, switches it to gray.
        func startTrackingClicks() {
            guard clickMonitor == nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.trackClick(event)
                return event
            }
        }

        func apply(
            groups: [NoteCalendar.Group],
            selectedID: String?,
            query: String,
            showsResultFolder: Bool,
            folderNames: [String: String],
            folders: [Folder]
        ) {
            self.selectedID = selectedID
            self.query = query
            self.showsResultFolder = showsResultFolder
            self.folderNames = folderNames
            self.folders = folders
            let next = Self.flatten(groups, query: query, folderNames: folderNames)
            let nextSignature = "\(showsResultFolder)\n" + next.map(\.signature).joined(separator: "\n")
            if nextSignature != signature {
                signature = nextSignature
                rows = next
                table?.reloadData()
            }
            showSelection()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            switch rows[row] {
            case .header:
                44
            case .note:
                showsSearchResult ? NoteListMetrics.searchRowHeight : NoteListMetrics.rowHeight
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch rows[row] {
            case .header(let title):
                let cell = (tableView.makeView(withIdentifier: Self.headerID, owner: self) as? NoteHeaderCell)
                    ?? NoteHeaderCell()
                cell.identifier = Self.headerID
                cell.configure(title)
                return cell
            case .note(let note, let query, let folder):
                let cell = (tableView.makeView(withIdentifier: Self.columnID, owner: self) as? NoteRowCell)
                    ?? NoteRowCell()
                cell.identifier = Self.columnID
                let excerpt = NoteSearch.excerpt(in: note.searchText, query: query)
                let detail = !query.isEmpty && !excerpt.isEmpty ? excerpt : NoteCalendar.listPreview(note.opening)
                cell.configure(
                    title: NoteCalendar.listTitle(note.title),
                    date: NoteCalendar.format(note),
                    detail: detail,
                    query: query,
                    folderName: showsSearchResult ? folder : ""
                )
                return cell
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("note-row")
            let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? NotesSelectionRow)
                ?? NotesSelectionRow()
            view.identifier = identifier
            if case .header = rows[row] {
                view.kind = .plain
            } else {
                view.kind = .note
            }
            return view
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            if case .note = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard case .note(let note, _, _) = rows[row] else { return nil }
            return LibraryDrag.writer(LibraryDrag.payload(noteID: note.id))
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            guard let row = rowIndexes.first, case .note(let note, _, _) = rows[row] else { return }
            LibraryDrag.current = LibraryDrag.payload(noteID: note.id)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            LibraryDrag.current = nil
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table else { return }
            table.enumerateAvailableRowViews { rowView, row in
                (rowView as? NotesSelectionRow)?.sync(selected: table.isRowSelected(row))
            }
            guard !suppress else { return }
            let row = table.selectedRow
            guard row >= 0, case .note(let note, _, _) = rows[row] else { return }
            guard note.id != selectedID else { return }
            let previousID = selectedID
            selectedID = note.id
            guard onSelect(note.id) else {
                selectedID = previousID
                showSelection()
                return
            }
        }

        private func showSelection() {
            guard let table else { return }
            let row = rows.firstIndex { item in
                if case .note(let note, _, _) = item { return note.id == selectedID }
                return false
            }
            suppress = true
            if let row {
                if table.selectedRow != row {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    table.scrollRowToVisible(row)
                }
            } else if table.selectedRow >= 0 {
                table.deselectAll(nil)
            }
            suppress = false
        }

        private var showsSearchResult: Bool {
            showsResultFolder || !query.isEmpty
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0, table.clickedRow < rows.count,
                  case .note(let note, _, _) = rows[table.clickedRow] else { return }
            contextNoteID = note.id
            if table.selectedRow != table.clickedRow {
                table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
            }
            menu.addItem(command("Open Note in New Window", symbol: "arrow.up.right.square", action: #selector(openContextNoteInNewWindow(_:))))
            menu.addItem(.separator())
            menu.addItem(command("Duplicate Note", symbol: "plus.square.on.square", action: #selector(duplicateContextNote(_:))))
            menu.addItem(.separator())
            menu.addItem(moveMenu(excluding: note.folderID))
            menu.addItem(.separator())
            menu.addItem(command("Delete", symbol: "trash", action: #selector(deleteContextNote(_:))))
        }

        @objc func deleteContextNote(_ sender: Any?) {
            guard let contextNoteID else { return }
            onDelete(contextNoteID)
        }

        @objc func moveContextNote(_ sender: NSMenuItem) {
            guard let contextNoteID, let folderID = sender.representedObject as? String else { return }
            onMove(contextNoteID, folderID)
        }

        @objc func openContextNoteInNewWindow(_ sender: Any?) {
            guard let contextNoteID else { return }
            onOpenInNewWindow(contextNoteID)
        }

        @objc func duplicateContextNote(_ sender: Any?) {
            guard let contextNoteID else { return }
            onDuplicate(contextNoteID)
        }

        private func command(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }

        private func moveMenu(excluding currentFolderID: String?) -> NSMenuItem {
            let item = command("Move to", symbol: "folder", action: #selector(moveContextNote(_:)))
            item.action = nil
            item.target = nil
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for entry in Self.folderEntries(folders) {
                let destination = NSMenuItem(title: entry.folder.name, action: #selector(moveContextNote(_:)), keyEquivalent: "")
                destination.target = self
                destination.representedObject = entry.folder.id
                destination.indentationLevel = entry.depth
                destination.isEnabled = entry.folder.id != currentFolderID
                submenu.addItem(destination)
            }
            item.submenu = submenu
            item.isEnabled = !submenu.items.isEmpty
            return item
        }

        private static func folderEntries(_ folders: [Folder]) -> [(folder: Folder, depth: Int)] {
            let grouped = Dictionary(grouping: folders, by: { $0.parentID ?? "" })
            func ordered(_ parent: String) -> [Folder] {
                (grouped[parent] ?? []).sorted { left, right in
                    if left.position != right.position { return left.position < right.position }
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
            }
            var entries: [(folder: Folder, depth: Int)] = []
            func walk(_ parent: String, depth: Int) {
                for folder in ordered(parent) {
                    entries.append((folder, depth))
                    walk(folder.id, depth: depth + 1)
                }
            }
            walk("", depth: 0)
            return entries
        }

        private func trackClick(_ event: NSEvent) {
            guard let table, let eventWindow = event.window, !eventWindow.className.contains("Menu") else { return }
            let host = table.enclosingScrollView ?? table
            let inList = eventWindow === table.window && host.bounds.contains(host.convert(event.locationInWindow, from: nil))
            let quiet = !inList
            guard table.noteSelectionIsQuiet != quiet else { return }
            table.noteSelectionIsQuiet = quiet
            table.refreshSelectionAppearance()
        }

        private static let headerID = NSUserInterfaceItemIdentifier("header")

        private static func flatten(
            _ groups: [NoteCalendar.Group],
            query: String,
            folderNames: [String: String]
        ) -> [Row] {
            groups.flatMap { group in
                let notes = group.notes.map { note in
                    Row.note(note, query: query, folder: folderNames[note.folderID ?? ""] ?? "")
                }
                guard !group.label.isEmpty else { return notes }
                return [Row.header(group.label)] + notes
            }
        }
    }
}

private enum Row {
    case header(String)
    case note(NoteSummary, query: String, folder: String)

    var signature: String {
        switch self {
        case .header(let title):
            return "header:\(title)"
        case .note(let note, let query, let folder):
            let excerpt = NoteSearch.excerpt(in: note.searchText, query: query)
            let detail = query.isEmpty || excerpt.isEmpty ? note.opening : excerpt
            return "note:\(note.id)|\(note.title)|\(NoteCalendar.format(note))|\(detail)|\(query)|\(folder)"
        }
    }
}

private final class NoteHeaderCell: NSTableCellView {
    private let divider = NSView()
    private var dividerHeight = NSLayoutConstraint()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let title = NSTextField(labelWithString: "")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NoteTypography.noteListSection
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.isEditable = false
        title.isSelectable = false
        title.refusesFirstResponder = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        textField = title
        addSubview(title)
        addSubview(divider)
        dividerHeight = divider.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: headerTextInset),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            title.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -6),
            divider.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerHeight
        ])
        refreshDivider()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(_ title: String) {
        textField?.stringValue = title
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        dividerHeight.constant = 1 / scale
        refreshDivider()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDivider()
    }

    private func refreshDivider() {
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

/// The note list. A click in the list draws the selection in the accent color. A click elsewhere draws it gray.
final class NoteListView: NSTableView {
    /// Starts quiet because the note column opens with the editor active.
    var noteSelectionIsQuiet = true
    private var keyObservers: [NSObjectProtocol] = []

    /// Accent fill while the list is the column that was just clicked, and the window is key.
    var showsAccentSelection: Bool {
        guard let window, window.isKeyWindow else { return false }
        return !noteSelectionIsQuiet
    }

    func refreshSelectionAppearance() {
        enumerateAvailableRowViews { rowView, _ in
            (rowView as? NotesSelectionRow)?.updateSelectionAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in keyObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyObservers.removeAll()
        guard let window else { return }
        let names = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification]
        for name in names {
            keyObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshSelectionAppearance()
                }
            )
        }
    }

    deinit {
        for observer in keyObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
