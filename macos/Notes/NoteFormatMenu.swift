import AppKit
import SwiftUI

enum NoteHighlight: String, CaseIterable, Identifiable {
    case purple, pink, orange, mint, blue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .mint: "Mint"
        case .blue: "Blue"
        }
    }

    func nsColor(for scheme: ColorScheme) -> NSColor {
        let channel = srgb(for: scheme)
        return NSColor(
            srgbRed: channel.red / 255,
            green: channel.green / 255,
            blue: channel.blue / 255,
            alpha: 1
        )
    }

    private func srgb(for scheme: ColorScheme) -> HighlightSRGB {
        let dark = scheme == .dark
        switch self {
        case .purple:
            return dark
                ? HighlightSRGB(red: 219, green: 52, blue: 242)
                : HighlightSRGB(red: 203, green: 48, blue: 224)
        case .pink:
            return dark
                ? HighlightSRGB(red: 255, green: 55, blue: 95)
                : HighlightSRGB(red: 255, green: 45, blue: 85)
        case .orange:
            return dark
                ? HighlightSRGB(red: 255, green: 146, blue: 48)
                : HighlightSRGB(red: 255, green: 141, blue: 40)
        case .mint:
            return dark
                ? HighlightSRGB(red: 0, green: 218, blue: 195)
                : HighlightSRGB(red: 0, green: 200, blue: 179)
        case .blue:
            return dark
                ? HighlightSRGB(red: 0, green: 145, blue: 255)
                : HighlightSRGB(red: 0, green: 136, blue: 255)
        }
    }
}

private struct HighlightSRGB {
    var red: Double
    var green: Double
    var blue: Double
}

struct FormatStyleMenu: View {
    @ObservedObject var editor: EditorBridge
    @Binding var chosen: NoteHighlight
    @Environment(\.colorScheme) private var colorScheme
    @State private var state = EditorFormatState()

    private var current: NoteHighlight {
        NoteHighlight(rawValue: state.highlight) ?? chosen
    }

    private var bodyFont: Font {
        .system(size: NoteTypography.editorBodySize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                mark("B", command: "bold", help: "Bold", active: state.bold, font: .system(size: 16, weight: .bold))
                mark(
                    "I",
                    command: "italic",
                    help: "Italic",
                    active: state.italic,
                    font: .system(size: 18, design: .serif).italic()
                )
                mark(
                    "U",
                    command: "underline",
                    help: "Underline",
                    active: state.underline,
                    font: .system(size: 16),
                    underline: true
                )
                mark(
                    "S",
                    command: "strike",
                    help: "Strikethrough",
                    active: state.strike,
                    font: .system(size: 16),
                    strike: true
                )
                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)
                Button {
                    apply("highlight:\(current.rawValue)")
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                        .background(
                            state.highlight.isEmpty ? Color.clear : Color.primary.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help("Highlight")
                .accessibilityLabel("Highlight")
                highlightColors
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 6)
            Divider()
            style(
                "Title",
                command: "title",
                checked: state.block == "title",
                titleFont: .system(size: NoteTypography.editorTitleSize, weight: .bold)
            )
            style(
                "Heading",
                command: "heading",
                checked: state.block == "heading",
                titleFont: .system(size: NoteTypography.editorHeadingSize, weight: .bold)
            )
            style(
                "Subheading",
                command: "subheading",
                checked: state.block == "subheading",
                titleFont: .system(size: NoteTypography.editorSubheadingSize, weight: .semibold)
            )
            style("Body", command: "body", checked: state.block == "body", titleFont: bodyFont)
            style(
                "Monostyled",
                command: "monostyled",
                checked: state.block == "monostyled",
                titleFont: .system(size: NoteTypography.editorMonospacedSize, design: .monospaced)
            )
            style("Bulleted List", command: "bullet", checked: false, prefix: "•", titleFont: bodyFont)
            style("Dashed List", command: "dash", checked: false, prefix: "–", titleFont: bodyFont)
            style("Numbered List", command: "ordered", checked: false, prefix: "1.", titleFont: bodyFont)
            Divider()
            style("Block Quote", command: "quote", checked: false, quote: true, titleFont: bodyFont)
        }
        .frame(width: 220)
        .padding(.vertical, 4)
        .task { await refresh() }
    }

    private var highlightColors: some View {
        HighlightColorButton(current: current, scheme: colorScheme) { choice in
            chosen = choice
            apply("highlight:\(choice.rawValue)")
        }
        .frame(width: 20, height: 26)
        .help("Choose a highlight color")
        .accessibilityLabel("Choose a highlight color")
    }

    private func refresh() async {
        state = await editor.formatState()
        if let active = NoteHighlight(rawValue: state.highlight) {
            chosen = active
        }
    }

    private func mark(
        _ title: String,
        command: String,
        help: String,
        active: Bool,
        font: Font,
        underline: Bool = false,
        strike: Bool = false
    ) -> some View {
        Button {
            apply(command)
        } label: {
            Text(title)
                .font(font)
                .underline(underline)
                .strikethrough(strike, color: .primary)
                .frame(width: 28, height: 28)
                .background(active ? Color.primary.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func style(
        _ title: String,
        command: String,
        checked: Bool,
        prefix: String? = nil,
        quote: Bool = false,
        titleFont: Font
    ) -> some View {
        Button {
            apply(command)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(checked ? 1 : 0)
                    .frame(width: 14)
                if quote {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 3, height: 16)
                }
                if let prefix {
                    Text(prefix)
                        .font(.system(size: 14))
                        .frame(width: prefix == "1." ? 22 : 16, alignment: .leading)
                }
                Text(title)
                    .font(titleFont)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func apply(_ command: String) {
        Task {
            await editor.format(command)
            await refresh()
        }
    }
}

struct HighlightColorButton: NSViewRepresentable {
    var current: NoteHighlight
    var scheme: ColorScheme
    var onChoose: (NoteHighlight) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChoose: onChoose)
    }

    func makeNSView(context: Context) -> HighlightDotButton {
        let button = HighlightDotButton()
        button.coordinator = context.coordinator
        button.current = current
        button.scheme = scheme
        return button
    }

    func updateNSView(_ button: HighlightDotButton, context: Context) {
        context.coordinator.onChoose = onChoose
        button.coordinator = context.coordinator
        button.current = current
        button.scheme = scheme
        button.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var onChoose: (NoteHighlight) -> Void

        init(onChoose: @escaping (NoteHighlight) -> Void) {
            self.onChoose = onChoose
        }

        @objc func pick(_ sender: NSMenuItem) {
            guard let name = sender.representedObject as? String,
                  let choice = NoteHighlight(rawValue: name) else { return }
            onChoose(choice)
        }
    }
}

final class HighlightDotButton: NSButton {
    var coordinator: HighlightColorButton.Coordinator?
    var current: NoteHighlight = .purple
    var scheme: ColorScheme = .dark
    private var hovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .noImage
        toolTip = "Choose a highlight color"
        setAccessibilityLabel("Choose a highlight color")
        target = self
        action = #selector(showMenu(_:))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 20, height: 26)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let diameter: CGFloat = 10
        let dot = NSRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        current.nsColor(for: scheme).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    @objc private func showMenu(_ sender: Any?) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in NoteHighlight.allCases {
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(HighlightColorButton.Coordinator.pick(_:)),
                keyEquivalent: ""
            )
            item.target = coordinator
            item.representedObject = choice.rawValue
            item.state = choice == current ? .on : .off
            item.image = Self.dotImage(choice.nsColor(for: scheme))
            menu.addItem(item)
        }
        let popover = enclosingPopover
        let behavior = popover?.behavior
        popover?.behavior = .applicationDefined
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: self)
        if let behavior {
            popover?.behavior = behavior
        }
        hovering = false
        needsDisplay = true
    }

    private var enclosingPopover: NSPopover? {
        var responder: NSResponder? = self
        while let next = responder {
            if let popover = next as? NSPopover { return popover }
            responder = next.nextResponder
        }
        return nil
    }

    private static func dotImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
