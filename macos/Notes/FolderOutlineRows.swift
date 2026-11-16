import AppKit

extension FolderOutlineCoordinator {
    func rebuild(folders: [Folder], notes: [NoteSummary]) {
        let counts = Self.counts(notes)
        let grouped = Dictionary(grouping: folders, by: { $0.parentID ?? "" })
        func ordered(_ parent: String) -> [Folder] {
            (grouped[parent] ?? []).sorted { left, right in
                if left.position != right.position { return left.position < right.position }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        }
        func nodes(_ parent: String) -> [OutlineItem] {
            ordered(parent).map { folder in
                let item = OutlineItem(
                    kind: .folder(folder),
                    count: counts[folder.id] ?? 0,
                    children: nodes(folder.id)
                )
                return item
            }
        }
        let folderRoots = nodes("")
        let all = OutlineItem(kind: .allNotes, count: notes.count, children: [])
        roots = [all] + folderRoots
        itemsByID = [:]
        func index(_ items: [OutlineItem]) {
            for item in items {
                if case .folder(let folder) = item.kind {
                    itemsByID[folder.id] = item
                }
                index(item.children)
            }
        }
        index(folderRoots)
    }

    func refreshCounts(notes: [NoteSummary]) {
        let counts = Self.counts(notes)
        for item in itemsByID.values {
            if case .folder(let folder) = item.kind {
                item.count = counts[folder.id] ?? 0
            }
        }
        if let all = roots.first, case .allNotes = all.kind {
            all.count = notes.count
        }
        guard let outline else { return }
        outline.enumerateAvailableRowViews { rowView, row in
            guard let item = outline.item(atRow: row) as? OutlineItem,
                  let cell = rowView.view(atColumn: 0) as? FolderCell else { return }
            cell.countField.stringValue = "\(item.count)"
        }
    }

    func restoreExpansion() {
        guard let outline else { return }
        if !didExpandInitially {
            outline.expandItem(nil, expandChildren: true)
            didExpandInitially = true
            expanded = Set(itemsByID.keys)
            return
        }
        func walk(_ items: [OutlineItem]) {
            for item in items {
                if case .folder(let folder) = item.kind, expanded.contains(folder.id) {
                    outline.expandItem(item)
                }
                walk(item.children)
            }
        }
        walk(roots)
    }

    func selectCurrent() {
        guard let outline else { return }
        let item: OutlineItem?
        if let folderID, let match = itemsByID[folderID] {
            item = match
            expandAncestors(of: folderID)
        } else {
            item = roots.first { if case .allNotes = $0.kind { return true }; return false }
        }
        guard let item else { return }
        let row = outline.row(forItem: item)
        guard row >= 0, outline.selectedRow != row else { return }
        suppressSelection = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressSelection = false
        outline.scrollRowToVisible(row)
    }

    func expandAncestors(of id: String) {
        guard let outline, let item = itemsByID[id] else { return }
        var parent = parentID(of: item)
        while let current = parent {
            if let parentItem = itemsByID[current] {
                outline.expandItem(parentItem)
                expanded.insert(current)
            }
            parent = itemsByID[current].flatMap { parentID(of: $0) }
        }
    }

    func parentID(of item: OutlineItem) -> String? {
        guard case .folder(let folder) = item.kind else { return nil }
        return folder.parentID
    }

    func acceptOn(raw: String, item: OutlineItem?) {
        guard let item else { return }
        switch item.kind {
        case .allNotes:
            onDrop(raw, .allNotes, .child)
        case .folder(let folder):
            onDrop(raw, .folder(folder.id), .child)
        }
    }

    func acceptBetween(raw: String, parent: OutlineItem?, index: Int) {
        let siblings: [OutlineItem]
        let folderIndex: Int
        if let parent {
            siblings = parent.children
            folderIndex = index
        } else {
            siblings = roots.filter {
                if case .folder = $0.kind { return true }
                return false
            }
            folderIndex = max(0, index - 1)
        }
        let ids = siblings.compactMap { item -> String? in
            if case .folder(let folder) = item.kind { return folder.id }
            return nil
        }
        let draggedID = raw.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            guard let placement = SiblingDrop.placement(
                siblingIDs: ids,
                draggedID: draggedID,
                index: folderIndex
            ) else {
            return
        }
        onDrop(raw, .folder(placement.targetID), placement.zone)
    }

    func dragString(_ info: NSDraggingInfo) -> String? {
        let board = info.draggingPasteboard
        let types = [LibraryDrag.pasteboardType, NSPasteboard.PasteboardType.string]
        for type in types {
            if let value = board.string(forType: type),
               value.hasPrefix("note:") || value.hasPrefix("folder:") {
                return value
            }
            for item in board.pasteboardItems ?? [] {
                guard let value = item.string(forType: type),
                      value.hasPrefix("note:") || value.hasPrefix("folder:") else { continue }
                return value
            }
        }
        return nil
    }

    static func counts(_ notes: [NoteSummary]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for note in notes {
            guard let folderID = note.folderID else { continue }
            counts[folderID, default: 0] += 1
        }
        return counts
    }
}
