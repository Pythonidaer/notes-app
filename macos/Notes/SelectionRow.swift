import AppKit

final class NotesSelectionRow: NSTableRowView {
    enum Kind {
        case folder
        case note
        case plain
    }

    var kind: Kind = .plain
    private var reflecting = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func sync(selected: Bool) {
        guard !reflecting else { return }
        reflecting = true
        defer { reflecting = false }
        if isSelected != selected {
            isSelected = selected
        }
        needsDisplay = true
        refreshCells()
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue, !reflecting else { return }
            needsDisplay = true
            refreshCells()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Note rows draw their own pill so it can share the title block's insets.
        guard selectionIsActive, kind == .folder else { return }
        let rect = bounds.insetBy(dx: 8, dy: 3)
        let radius: CGFloat = 6
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        guard selectionIsActive, kind != .plain else { return .normal }
        if kind == .folder {
            return enclosingFolderOutline(of: self)?.showsAccentSelection == true ? .emphasized : .normal
        }
        if enclosingNoteList(of: self)?.showsAccentSelection == true {
            return .emphasized
        }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .emphasized : .normal
    }

    func updateSelectionAppearance() {
        needsDisplay = true
        refreshCells()
    }

    private var selectionIsActive: Bool {
        notesRowIsSelected(self)
    }

    private func refreshCells() {
        guard numberOfColumns > 0 else { return }
        let style = interiorBackgroundStyle
        let other: NSView.BackgroundStyle = style == .emphasized ? .normal : .emphasized
        for column in 0..<numberOfColumns {
            guard let cell = view(atColumn: column) as? NSTableCellView else { continue }
            if cell.backgroundStyle == style {
                cell.backgroundStyle = other
            }
            cell.backgroundStyle = style
        }
    }

    private var fillColor: NSColor {
        switch kind {
        case .folder:
            if enclosingFolderOutline(of: self)?.showsAccentSelection == true {
                return .controlAccentColor
            }
            return Self.quietSelectionFill
        case .note:
            if enclosingNoteList(of: self)?.showsAccentSelection == true {
                return .controlAccentColor
            }
            return Self.quietSelectionFill
        case .plain:
            return .clear
        }
    }

    /// Gray used for a note row, and for a folder once the sidebar is no longer the active column.
    static let quietSelectionFill = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.27, green: 0.27, blue: 0.29, alpha: 1)
        }
        return NSColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
    }
}

func enclosingNoteList(of view: NSView) -> NoteListView? {
    var current: NSView? = view
    while let candidate = current {
        if let list = candidate as? NoteListView { return list }
        current = candidate.superview
    }
    return nil
}

func enclosingFolderOutline(of view: NSView) -> FolderOutlineView? {
    var current: NSView? = view
    while let candidate = current {
        if let outline = candidate as? FolderOutlineView { return outline }
        current = candidate.superview
    }
    return nil
}

func notesRowIsSelected(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
        if let row = candidate as? NSTableRowView {
            var parent = row.superview
            while let container = parent {
                if let table = container as? NSTableView {
                    let index = table.row(for: row)
                    if index >= 0 {
                        return table.isRowSelected(index)
                    }
                    break
                }
                parent = container.superview
            }
            return row.isSelected
        }
        current = candidate.superview
    }
    return false
}
