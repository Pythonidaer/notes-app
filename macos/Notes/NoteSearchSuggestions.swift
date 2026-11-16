import AppKit

/// The menu under the search field. It does not take key focus away from the field.
final class SearchSuggestionPanel: NSPanel {
    let list: SuggestionListView

    init() {
        let menu = SuggestionListView()
        list = menu
        super.init(
            contentRect: NSRect(origin: .zero, size: menu.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = list
        setContentSize(list.fittingSize)
    }

    /// Puts the menu just under `anchor`, aligned to its leading edge.
    func place(under anchor: NSView) {
        guard let window = anchor.window else { return }
        appearance = anchor.effectiveAppearance
        list.applyAppearance()
        let inWindow = anchor.convert(anchor.bounds, to: nil)
        let screenRect = window.convertToScreen(inWindow)
        let size = list.fittingSize
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - 2 - size.height)
        if let visible = window.screen?.visibleFrame, origin.y < visible.minY {
            origin.y = screenRect.maxY + 2
        }
        let frame = NSRect(origin: origin, size: size)
        if self.frame != frame {
            setFrame(frame, display: true)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Puts the menu just under a capsule rectangle in screen coordinates.
    func place(atLeadingEdgeOf capsule: NSRect) {
        let size = list.fittingSize
        var origin = NSPoint(x: capsule.minX, y: capsule.minY - 2 - size.height)
        if let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame, origin.y < visible.minY {
            origin.y = capsule.maxY + 2
        }
        let frame = NSRect(origin: origin, size: size)
        if self.frame != frame {
            setFrame(frame, display: true)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }
}

/// Shared Notes through Notes with Attachments, in Notes' order.
final class SuggestionListView: NSView {
    static let menuWidth: CGFloat = 247
    static let rowHeight: CGFloat = 22
    static let menuInset: CGFloat = 5
    var onSelect: (NoteSearchScope) -> Void = { _ in }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let rows = CGFloat(NoteSearchScope.allCases.count)
        let height = Self.menuInset * 2 + Self.rowHeight * rows
        return NSSize(width: Self.menuWidth, height: height)
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: .zero))
        wantsLayer = true
        layer?.cornerRadius = 10
        var originY = Self.menuInset
        for scope in NoteSearchScope.allCases {
            let row = SearchSuggestionRow(scope: scope)
            row.target = self
            row.action = #selector(choose(_:))
            row.frame = NSRect(x: 4, y: originY, width: Self.menuWidth - 8, height: Self.rowHeight)
            row.autoresizingMask = [.width]
            addSubview(row)
            originY += Self.rowHeight
        }
        frame.size = fittingSize
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    func applyAppearance() {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        let dark = match == .darkAqua || match == .vibrantDark
        let fill = dark
            ? NSColor(srgbRed: 40.0 / 255, green: 43.0 / 255, blue: 45.0 / 255, alpha: 1)
            : NSColor(srgbRed: 246.0 / 255, green: 246.0 / 255, blue: 248.0 / 255, alpha: 1)
        let stroke = dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke.cgColor
        layer?.borderWidth = 1
    }

    @objc fileprivate func choose(_ sender: SearchSuggestionRow) {
        onSelect(sender.scope)
    }
}

private final class SearchSuggestionRow: NSControl {
    let scope: NoteSearchScope

    init(scope: NoteSearchScope) {
        self.scope = scope
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        setAccessibilityRole(.button)
        setAccessibilityLabel(scope.title)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: scope.title)
        label.font = NoteTypography.noteSearchSuggestion
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.refusesFirstResponder = true
        for item in [icon, label] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}
