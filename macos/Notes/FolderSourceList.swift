import AppKit
import SwiftUI

struct FolderSourceList: NSViewRepresentable {
    @ObservedObject var store: LibraryStore

    func makeCoordinator() -> FolderOutlineCoordinator {
        FolderOutlineCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = FolderOutlineView()
        outline.headerView = nil
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.allowsColumnResizing = false
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = false
        outline.selectionHighlightStyle = .none
        outline.style = .plain
        outline.rowSizeStyle = .custom
        outline.rowHeight = 32
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 16
        outline.floatsGroupRows = false
        outline.usesAlternatingRowBackgroundColors = false
        outline.autoresizesOutlineColumn = true
        outline.focusRingType = .none
        let column = NSTableColumn(identifier: FolderOutlineCoordinator.columnID)
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(FolderOutlineCoordinator.beginRename(_:))
        outline.registerForDraggedTypes([.string, LibraryDrag.pasteboardType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.connect(store)
        context.coordinator.apply(
            folders: store.folders,
            notes: store.notes,
            folderID: store.folderID
        )
    }

}

final class OutlineItem: NSObject {
    enum Kind {
        case allNotes
        case folder(Folder)
    }

    var kind: Kind
    var count: Int
    var children: [OutlineItem]

    init(kind: Kind, count: Int, children: [OutlineItem]) {
        self.kind = kind
        self.count = count
        self.children = children
    }

    static let allNotes = OutlineItem(kind: .allNotes, count: 0, children: [])
}

final class FolderOutlineView: NSOutlineView {
    /// Matches the folder icon's leading inset so the disclosure triangle sits against the icon.
    static let iconInset: CGFloat = 10

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        let cell = frameOfCell(atColumn: 0, row: row)
        guard cell.width > 1, cell.height > 1 else {
            return super.frameOfOutlineCell(atRow: row)
        }
        // The system slot is as wide as the indent, and the triangle is drawn at its
        // left edge. Size the slot to the triangle so it sits against the folder icon.
        let side: CGFloat = 11
        let gap: CGFloat = 1
        return NSRect(
            x: cell.minX + Self.iconInset - gap - side,
            y: cell.midY - side / 2,
            width: side,
            height: side
        )
    }
}

final class FolderCell: NSTableCellView {
    let countField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        let title = NSTextField(labelWithString: "")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.cell?.truncatesLastVisibleLine = true
        title.isEditable = false
        title.isSelectable = false
        title.refusesFirstResponder = true
        title.focusRingType = .none
        title.font = NoteTypography.folderName
        countField.translatesAutoresizingMaskIntoConstraints = false
        countField.alignment = .right
        countField.isEditable = false
        countField.isSelectable = false
        countField.refusesFirstResponder = true
        countField.font = NoteTypography.folderCount
        imageView = icon
        textField = title
        addSubview(icon)
        addSubview(title)
        addSubview(countField)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countField.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: FolderOutlineView.iconInset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            countField.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            countField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            countField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(symbol: String, title: String, count: Int, folderID: String?) {
        imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView?.contentTintColor = .labelColor
        textField?.stringValue = title
        textField?.identifier = folderID.map { NSUserInterfaceItemIdentifier($0) }
        countField.stringValue = "\(count)"
        applyColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    private func applyColors() {
        let selected = backgroundStyle == .emphasized || rowIsSelected
        textField?.textColor = selected ? .white : .labelColor
        countField.textColor = selected ? NSColor.white.withAlphaComponent(0.9) : .secondaryLabelColor
        imageView?.contentTintColor = selected ? .white : .secondaryLabelColor
    }

    private var rowIsSelected: Bool {
        notesRowIsSelected(self)
    }
}
