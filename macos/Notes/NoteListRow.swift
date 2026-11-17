import AppKit

private let noteTextInset: CGFloat = 36
/// Equal on both sides, so the pill is not wider on the leading edge.
private let selectionHorizontalInset: CGFloat = 12
/// Clears the hairline above the row by the same amount as the one below.
private let selectionVerticalInset: CGFloat = 6

enum NoteListMetrics {
    static let rowHeight: CGFloat = 68
    static let searchRowHeight: CGFloat = 82
}

/// One note in the list. A search result adds the matched snippet and the folder name.
final class NoteRowCell: NSTableCellView {
    let previewField = NSTextField(labelWithString: "")
    private let selection = NSView()
    private let textBlock = NSView()
    private let divider = NSView()
    private var textBlockBottom = NSLayoutConstraint()
    private let folderIcon = NSImageView()
    private let folderField = NSTextField(labelWithString: "")
    private var dividerHeight = NSLayoutConstraint()
    private var titleText = ""
    private var dateText = ""
    private var detailText = ""
    private var query = ""
    private var folderName = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selection.wantsLayer = true
        selection.layer?.cornerRadius = 8
        selection.layer?.cornerCurve = .continuous
        textBlock.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel(font: NoteTypography.noteListTitle)
        prepare(previewField, font: NoteTypography.noteListPreview)
        prepareFolderIcon()
        prepare(folderField, font: NoteTypography.noteListFolder)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        textField = title
        addSubview(selection)
        addSubview(textBlock)
        textBlock.addSubview(title)
        textBlock.addSubview(previewField)
        textBlock.addSubview(folderIcon)
        textBlock.addSubview(folderField)
        addSubview(divider)
        pin(title)
        refreshDivider()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, date: String, detail: String, query: String, folderName: String) {
        titleText = title
        dateText = date
        detailText = detail
        self.query = query
        self.folderName = folderName
        let showFolder = !folderName.isEmpty
        folderIcon.isHidden = !showFolder
        folderField.isHidden = !showFolder
        folderField.stringValue = folderName
        textBlockBottom.isActive = false
        textBlockBottom = textBlock.bottomAnchor.constraint(
            equalTo: showFolder ? folderField.bottomAnchor : previewField.bottomAnchor
        )
        textBlockBottom.isActive = true
        updateSelection()
    }

    override func layout() {
        super.layout()
        selection.frame = bounds.insetBy(dx: selectionHorizontalInset, dy: selectionVerticalInset)
        let scale = window?.backingScaleFactor ?? 2
        dividerHeight.constant = 1 / scale
        refreshDivider()
        updateSelection()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDivider()
        updateSelection()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateSelection() }
    }

    private func makeLabel(font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        prepare(field, font: font)
        return field
    }

    private func prepare(_ field: NSTextField, font: NSFont) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = true
        field.isEditable = false
        field.isSelectable = false
        field.refusesFirstResponder = true
        field.focusRingType = .none
    }

    private func prepareFolderIcon() {
        folderIcon.translatesAutoresizingMaskIntoConstraints = false
        folderIcon.imageScaling = .scaleProportionallyDown
        folderIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
    }

    private func pin(_ title: NSTextField) {
        dividerHeight = divider.heightAnchor.constraint(equalToConstant: 1)
        textBlockBottom = textBlock.bottomAnchor.constraint(equalTo: previewField.bottomAnchor)
        NSLayoutConstraint.activate([
            textBlock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: noteTextInset),
            textBlock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -noteTextInset),
            textBlock.centerYAnchor.constraint(equalTo: centerYAnchor),
            textBlockBottom,
            title.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: textBlock.trailingAnchor),
            title.topAnchor.constraint(equalTo: textBlock.topAnchor),
            previewField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            previewField.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            previewField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            folderIcon.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            folderIcon.topAnchor.constraint(equalTo: previewField.bottomAnchor, constant: 2),
            folderIcon.widthAnchor.constraint(equalToConstant: 12),
            folderIcon.heightAnchor.constraint(equalToConstant: 12),
            folderField.leadingAnchor.constraint(equalTo: folderIcon.trailingAnchor, constant: 4),
            folderField.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            folderField.centerYAnchor.constraint(equalTo: folderIcon.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerHeight
        ])
    }

    private func updateSelection() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selected = rowIsSelected
        let accent = selected && enclosingNoteList(of: self)?.showsAccentSelection == true
        selection.isHidden = !selected
        let fill = accent ? NSColor.controlAccentColor : Self.quietFill(dark: dark)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selection.layer?.backgroundColor = fill.cgColor
        }
        let onFill = accent || (selected && dark)
        let titleColor: NSColor = onFill ? .white : .labelColor
        let secondary: NSColor = onFill ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
        let match = NoteSearch.matchColor(in: effectiveAppearance)
        textField?.attributedStringValue = highlighted(
            titleText,
            font: NoteTypography.noteListTitle,
            color: titleColor,
            match: match
        )
        previewField.attributedStringValue = previewLine(color: secondary, match: match)
        previewField.isHidden = dateText.isEmpty && detailText.isEmpty
        folderField.textColor = secondary
        folderIcon.contentTintColor = secondary
    }

    private func previewLine(color: NSColor, match: NSColor) -> NSAttributedString {
        let date = dateText
        let detail = detailText
        let combined: String
        let detailStart: Int
        if date.isEmpty {
            combined = detail
            detailStart = 0
        } else if detail.isEmpty {
            combined = date
            detailStart = combined.utf16.count
        } else {
            combined = "\(date) \(detail)"
            detailStart = (date as NSString).length + 1
        }
        let line = NSMutableAttributedString(
            string: combined,
            attributes: [.font: NoteTypography.noteListPreview, .foregroundColor: color]
        )
        guard !query.isEmpty, !detail.isEmpty else { return line }
        for range in NoteSearch.highlightRanges(in: detail, query: query) {
            let nsRange = NSRange(range, in: detail)
            let shifted = NSRange(location: detailStart + nsRange.location, length: nsRange.length)
            guard NSMaxRange(shifted) <= line.length else { continue }
            line.addAttribute(.foregroundColor, value: match, range: shifted)
        }
        return line
    }

    private func highlighted(_ text: String, font: NSFont, color: NSColor, match: NSColor) -> NSAttributedString {
        let line = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        guard !query.isEmpty else { return line }
        for range in NoteSearch.highlightRanges(in: text, query: query) {
            let nsRange = NSRange(range, in: text)
            guard NSMaxRange(nsRange) <= line.length else { continue }
            line.addAttribute(.foregroundColor, value: match, range: nsRange)
        }
        return line
    }

    private func refreshDivider() {
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    private var rowIsSelected: Bool {
        notesRowIsSelected(self)
    }

    private static func quietFill(dark: Bool) -> NSColor {
        if dark {
            return NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1)
        }
        return NSColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
    }
}
