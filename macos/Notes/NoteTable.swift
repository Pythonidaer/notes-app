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
    var onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
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
        context.coordinator.table = table

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
        context.coordinator.apply(
            groups: groups,
            selectedID: selectedID,
            query: query,
            showsResultFolder: showsResultFolder,
            folderNames: folderNames
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnID = NSUserInterfaceItemIdentifier("note")

        weak var table: NSTableView?
        var onSelect: (String) -> Void = { _ in }
        private var rows: [Row] = []
        private var signature = ""
        private var selectedID: String?
        private var query = ""
        private var showsResultFolder = false
        private var folderNames: [String: String] = [:]
        private var suppress = false

        func apply(
            groups: [NoteCalendar.Group],
            selectedID: String?,
            query: String,
            showsResultFolder: Bool,
            folderNames: [String: String]
        ) {
            self.selectedID = selectedID
            self.query = query
            self.showsResultFolder = showsResultFolder
            self.folderNames = folderNames
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
                showsSearchResult ? 70 : 56
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
                let detail = query.isEmpty || excerpt.isEmpty ? note.opening : excerpt
                cell.configure(
                    title: note.title.isEmpty ? "Untitled" : note.title,
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
            selectedID = note.id
            onSelect(note.id)
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
