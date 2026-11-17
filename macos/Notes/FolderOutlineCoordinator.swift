import AppKit

final class FolderOutlineCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSMenuDelegate, NSTextFieldDelegate {
    static let columnID = NSUserInterfaceItemIdentifier("folder")

    weak var outline: FolderOutlineView?
    var roots: [OutlineItem] = []
    var itemsByID: [String: OutlineItem] = [:]
    var expanded: Set<String> = []
    var didExpandInitially = false
    var folderSignature = ""
    var noteSignature = ""
    var folderID: String?
    var suppressSelection = false
    var onSelect: (String?) -> Void = { _ in }
    var onRename: (String, String) -> Void = { _, _ in }
    var onDrop: (String, DropAnchor, DropZone) -> Void = { _, _, _ in }
    var onDelete: (String) -> Void = { _ in }
    private var sidebarClickMonitor: Any?
    private weak var renamingField: NSTextField?
    private var handlingRenameEnd = false

    func connect(_ store: LibraryStore) {
        onSelect = { id in
            Task { @MainActor in
                store.selectFolder(id)
            }
        }
        onRename = { id, name in
            Task { @MainActor in
                store.renameFolder(id: id, name: name)
            }
        }
        onDrop = { raw, anchor, zone in
            Task { @MainActor in
                store.receiveDrop(raw: raw, on: anchor, zone: zone)
            }
        }
        onDelete = { id in
            Task { @MainActor in
                store.folderID = id
                store.askToDeleteFolder()
            }
        }
    }

        func apply(folders: [Folder], notes: [NoteSummary], folderID: String?) {
            self.folderID = folderID
            let nextFolders = folders.map { folder in
                "\(folder.id)\t\(folder.name)\t\(folder.parentID ?? "")\t\(folder.position)"
            }.joined(separator: "\n")
        let nextNotes = notes.map { "\($0.id)\t\($0.folderID ?? "")" }.joined(separator: "\n")
        if nextFolders != folderSignature {
            folderSignature = nextFolders
            noteSignature = nextNotes
            rebuild(folders: folders, notes: notes)
            suppressSelection = true
            outline?.reloadData()
            restoreExpansion()
            suppressSelection = false
        } else if nextNotes != noteSignature {
            noteSignature = nextNotes
            refreshCounts(notes: notes)
        }
        selectCurrent()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return roots.count }
        return (item as? OutlineItem)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return roots[index] }
        return (item as? OutlineItem)?.children[index] ?? OutlineItem.allNotes
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? OutlineItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = (outlineView.makeView(withIdentifier: Self.columnID, owner: self) as? FolderCell) ?? FolderCell()
        cell.identifier = Self.columnID
        guard let row = item as? OutlineItem else { return cell }
        cell.textField?.delegate = self
        cell.textField?.identifier = nil
        cell.textField?.isEditable = false
        cell.textField?.isSelectable = false
        cell.textField?.refusesFirstResponder = true
        switch row.kind {
        case .allNotes:
            cell.configure(symbol: "tray.full", title: "All notes", count: row.count, folderID: nil)
        case .folder(let folder):
            cell.configure(symbol: "folder", title: folder.name, count: row.count, folderID: folder.id)
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        32
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("folder-row")
        let row = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NotesSelectionRow)
            ?? NotesSelectionRow()
        row.identifier = identifier
        row.kind = .folder
        return row
    }

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> (any NSPasteboardWriting)? {
        guard let row = item as? OutlineItem, case .folder(let folder) = row.kind else { return nil }
        return LibraryDrag.writer(LibraryDrag.payload(folderID: folder.id))
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        guard let row = draggedItems.first as? OutlineItem, case .folder(let folder) = row.kind else { return }
        LibraryDrag.current = LibraryDrag.payload(folderID: folder.id)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        LibraryDrag.current = nil
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let raw = dragString(info) ?? LibraryDrag.current else { return [] }
        guard raw.hasPrefix("note:") || raw.hasPrefix("folder:") else { return [] }
        if raw.hasPrefix("note:") {
            if index == NSOutlineViewDropOnItemIndex, item is OutlineItem {
                return .move
            }
            let siblings = (item as? OutlineItem)?.children ?? roots
            if siblings.indices.contains(index) {
                outlineView.setDropItem(siblings[index], dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .move
            }
            if index > 0, siblings.indices.contains(index - 1) {
                outlineView.setDropItem(siblings[index - 1], dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .move
            }
            if let parent = item as? OutlineItem {
                outlineView.setDropItem(parent, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .move
            }
            return []
        }
        if let target = item as? OutlineItem, case .allNotes = target.kind {
            outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        }
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let raw = dragString(info) ?? LibraryDrag.current else { return false }
        if index == NSOutlineViewDropOnItemIndex {
            acceptOn(raw: raw, item: item as? OutlineItem)
            return true
        }
        acceptBetween(raw: raw, parent: item as? OutlineItem, index: index)
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline else { return }
        outline.enumerateAvailableRowViews { rowView, row in
            (rowView as? NotesSelectionRow)?.sync(selected: outline.isRowSelected(row))
        }
        guard !suppressSelection else { return }
        let row = outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) as? OutlineItem else { return }
        let id: String?
        switch item.kind {
        case .allNotes:
            id = nil
        case .folder(let folder):
            id = folder.id
        }
        if id != folderID {
            folderID = id
            onSelect(id)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem,
              case .folder(let folder) = item.kind else { return }
        expanded.insert(folder.id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem,
              case .folder(let folder) = item.kind else { return }
        expanded.remove(folder.id)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let outline, outline.clickedRow >= 0,
              let item = outline.item(atRow: outline.clickedRow) as? OutlineItem,
              case .folder = item.kind else { return }
        suppressSelection = true
        outline.selectRowIndexes(IndexSet(integer: outline.clickedRow), byExtendingSelection: false)
        suppressSelection = false
            if let item = outline.item(atRow: outline.selectedRow) as? OutlineItem,
               case .folder(let folder) = item.kind {
            folderID = folder.id
            onSelect(folder.id)
        }
        let rename = menu.addItem(withTitle: "Rename", action: #selector(beginRename(_:)), keyEquivalent: "")
        rename.target = self
            let delete = menu.addItem(
                withTitle: "Delete",
                action: #selector(deleteSelectedFolder(_:)),
                keyEquivalent: ""
            )
        delete.target = self
    }

    @objc func beginRename(_ sender: Any?) {
        guard let outline else { return }
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0,
              let item = outline.item(atRow: row) as? OutlineItem,
              case .folder = item.kind,
              let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? FolderCell,
              let field = cell.textField else { return }
        field.refusesFirstResponder = false
        field.isSelectable = true
        field.isEditable = true
        field.delegate = self
        renamingField = field
        outline.sidebarSelectionIsQuiet = false
        outline.window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.utf16.count)
        outline.refreshSelectionAppearance()
    }

    @objc func deleteSelectedFolder(_ sender: Any?) {
        guard let id = folderID else { return }
        onDelete(id)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, !handlingRenameEnd else { return }
        handlingRenameEnd = true
        defer { handlingRenameEnd = false }
        closeRenameField(field)
        guard let id = field.identifier?.rawValue, !id.isEmpty else { return }
        guard let item = itemsByID[id], case .folder(let folder) = item.kind else { return }
        let movement = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if movement == NSTextMovement.cancel.rawValue || trimmed.isEmpty || trimmed == folder.name {
            field.stringValue = folder.name
            return
        }
        field.stringValue = trimmed
        onRename(id, trimmed)
    }

    /// Clicks in the notes list do not take first responder, so the field editor would stay up.
    /// This watches the window and closes rename unless the click is on the name being edited.
    func startTrackingSidebarClicks() {
        guard sidebarClickMonitor == nil else { return }
        sidebarClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.trackSidebarClick(event)
            return event
        }
    }

    deinit {
        if let sidebarClickMonitor {
            NSEvent.removeMonitor(sidebarClickMonitor)
        }
    }

    private func trackSidebarClick(_ event: NSEvent) {
        guard let outline, let eventWindow = event.window, !eventIsMenu(eventWindow) else { return }
        let inThisWindow = eventWindow === outline.window
        if inThisWindow,
           event.type == .leftMouseDown,
           let field = renamingField,
           eventHits(field, event) || eventHitsFieldEditor(field, event) {
            return
        }
        let inSidebar = inThisWindow && eventHitsSidebar(event)
        let wasRenaming = renamingField != nil
        if let field = renamingField {
            commitRenameField(field)
        }
        let quiet = !inSidebar
        let changed = outline.sidebarSelectionIsQuiet != quiet
        outline.sidebarSelectionIsQuiet = quiet
        if wasRenaming || changed {
            outline.refreshSelectionAppearance()
        }
        if quiet {
            releaseSidebarFocus(outline)
        }
    }

    private func commitRenameField(_ field: NSTextField) {
        if field.currentEditor() != nil {
            field.window?.endEditing(for: nil)
        }
        if field.currentEditor() != nil {
            _ = field.window?.makeFirstResponder(nil)
        }
        closeRenameField(field)
    }

    /// Lets the click land first, then moves keyboard focus off the sidebar when it stayed there.
    private func releaseSidebarFocus(_ outline: NSOutlineView) {
        DispatchQueue.main.async { [weak outline] in
            guard let outline, let window = outline.window else { return }
            let responder = window.firstResponder
            let sidebarFocused = responder === outline
                || (responder as? NSView)?.isDescendant(of: outline) == true
            guard sidebarFocused else { return }
            _ = window.makeFirstResponder(nil)
        }
    }

    private func eventIsMenu(_ window: NSWindow) -> Bool {
        window.className.contains("Menu")
    }

    private func closeRenameField(_ field: NSTextField) {
        field.isEditable = false
        field.isSelectable = false
        field.refusesFirstResponder = true
        field.window?.invalidateCursorRects(for: field)
        if renamingField === field {
            renamingField = nil
        }
    }

    private func eventHits(_ view: NSView, _ event: NSEvent) -> Bool {
        guard event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func eventHitsFieldEditor(_ field: NSTextField, _ event: NSEvent) -> Bool {
        guard let editor = field.currentEditor() else { return false }
        return eventHits(editor, event)
    }

    private func eventHitsSidebar(_ event: NSEvent) -> Bool {
        guard let outline, event.window === outline.window else { return false }
        let host = outline.enclosingScrollView ?? outline
        return eventHits(host, event)
    }
}
