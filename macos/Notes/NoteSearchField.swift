import AppKit
import SwiftUI

/// The note bar's search field.
///
/// It is the library search for the note list. Command-F does not use this field.
/// A click focuses it. While it is empty, the Notes suggestion menu opens underneath.
struct NoteSearchField: View {
    /// Measured from Notes. The capsule is 280 by 34 points.
    static let fieldWidth: CGFloat = 280
    static let fieldHeight: CGFloat = 34
    /// Room for the focus ring, so the toolbar does not clip it.
    static let focusRingOutset: CGFloat = 4

    @Binding var text: String
    @Binding var scope: NoteSearchScope?
    @FocusState private var focused: Bool
    /// The capsule is focused. The toolbar can focus the field without updating `focused`.
    @State private var searchFocused = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var findMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: NoteTypography.noteBarSearchSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: fieldText)
                .textFieldStyle(.plain)
                .font(.system(size: NoteTypography.noteBarSearchSize, weight: .regular))
                .tint(Self.focusRing)
                .focused($focused)
                .accessibilityLabel("Search")
            if showsClear {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: NoteTypography.noteBarSearchSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.fieldWidth, height: Self.fieldHeight)
        .background {
            ZStack {
                Capsule().fill(fill)
                SearchSuggestionAnchor(shown: suggestionsShown, onSelect: choose)
            }
        }
        .overlay {
            Capsule().strokeBorder(hairline, lineWidth: 1)
        }
        .padding(Self.focusRingOutset)
        .background {
            if searchFocused {
                Capsule().strokeBorder(Self.focusRing, lineWidth: 3.5)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { focusSearch() }
        .onAppear {
            SearchClickMonitor.shared.onFocus = {
                focusSearch()
                installFindMonitor(true)
            }
            SearchClickMonitor.shared.onBlur = {
                searchFocused = false
                installFindMonitor(false)
            }
            SearchClickMonitor.shared.install()
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { searchFocused = true }
            installFindMonitor(isFocused || searchFocused)
        }
        .onDisappear { installFindMonitor(false) }
    }

    /// Measured in Notes, dark mode. The focus ring around the search capsule.
    static let focusRing = Color(red: 121.0 / 255, green: 82.0 / 255, blue: 129.0 / 255)

    private var suggestionsShown: Bool {
        searchFocused && text.isEmpty && scope == nil
    }

    private func focusSearch() {
        searchFocused = true
        focused = true
    }

    private var showsClear: Bool {
        scope != nil || !text.isEmpty
    }

    private var fill: Color {
        colorScheme == .dark
            ? Color(red: 25.0 / 255, green: 29.0 / 255, blue: 30.0 / 255)
            : Color(red: 246.0 / 255, green: 246.0 / 255, blue: 248.0 / 255)
    }

    private var hairline: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    /// The field shows a suggestion title without searching for those words.
    private var fieldText: Binding<String> {
        Binding(get: { displayedText }, set: applyFieldText)
    }

    private var displayedText: String {
        guard let scope else { return text }
        if text.isEmpty { return scope.title }
        return "\(scope.title) \(text)"
    }

    private func applyFieldText(_ newValue: String) {
        guard let scope else {
            text = newValue
            return
        }
        let title = scope.title
        if newValue == title {
            text = ""
            return
        }
        if newValue.hasPrefix(title) {
            let extra = newValue.dropFirst(title.count).trimmingCharacters(in: .whitespaces)
            text = String(extra)
            return
        }
        self.scope = nil
        text = title.hasPrefix(newValue) ? "" : newValue
    }

    private func choose(_ scope: NoteSearchScope) {
        self.scope = scope
        text = ""
        focusSearch()
    }

    private func clearSearch() {
        text = ""
        scope = nil
        focusSearch()
    }

    /// Command-F finds inside the open note, including while this field is focused.
    private func installFindMonitor(_ install: Bool) {
        if install {
            guard findMonitor == nil else { return }
            findMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                noteFindKeyEquivalent(event) ? nil : event
            }
            return
        }
        guard let findMonitor else { return }
        NSEvent.removeMonitor(findMonitor)
        self.findMonitor = nil
    }
}

/// Pins the suggestion menu under the search capsule.
private struct SearchSuggestionAnchor: NSViewRepresentable {
    var shown: Bool
    var onSelect: (NoteSearchScope) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SuggestionAnchorView {
        let view = SuggestionAnchorView()
        view.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.sync()
        }
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SuggestionAnchorView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? NoteSearchField.fieldWidth,
            height: proposal.height ?? NoteSearchField.fieldHeight
        )
    }

    func updateNSView(_ view: SuggestionAnchorView, context: Context) {
        context.coordinator.shown = shown
        context.coordinator.onSelect = onSelect
        context.coordinator.anchor = view
        context.coordinator.sync()
    }

    static func dismantleNSView(_ nsView: SuggestionAnchorView, coordinator: Coordinator) {
        coordinator.hide()
    }

    final class Coordinator {
        var shown = false
        var onSelect: (NoteSearchScope) -> Void = { _ in }
        weak var anchor: SuggestionAnchorView?
        private var panel: SearchSuggestionPanel?

        func sync() {
            guard shown else {
                hide()
                return
            }
            let panel = ensurePanel()
            panel.list.onSelect = onSelect
            if let anchor, anchor.window != nil, anchor.bounds.width > 1 {
                panel.place(under: anchor)
                return
            }
            guard let field = SearchClickMonitor.shared.searchField(), let fieldWindow = field.window else {
                hide()
                return
            }
            let fieldRect = fieldWindow.convertToScreen(field.convert(field.bounds, to: nil))
            let capsule = fieldRect.insetBy(dx: -28, dy: -9)
            panel.place(atLeadingEdgeOf: capsule)
        }

        func hide() {
            panel?.orderOut(nil)
        }

        private func ensurePanel() -> SearchSuggestionPanel {
            if let panel { return panel }
            let created = SearchSuggestionPanel()
            panel = created
            return created
        }
    }
}

private final class SuggestionAnchorView: NSView {
    var onLayout: (() -> Void)?

    /// The anchor only positions the menu. Clicks pass through to the text field.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
}

/// Focuses the note bar search field when a click lands on its capsule.
///
/// The toolbar is a separate window and can swallow the click before SwiftUI sees it.
final class SearchClickMonitor {
    static let shared = SearchClickMonitor()
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}
    private var monitor: Any?
    private var active = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.focusSearchField(for: event) ?? event
        }
    }

    func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    /// A click on the clear button is left alone. Other clicks inside the capsule are consumed.
    private func focusSearchField(for event: NSEvent) -> NSEvent? {
        let point = clickScreenPoint(event)
        if event.window is SearchSuggestionPanel { return event }
        guard let field = searchField(), let fieldWindow = field.window else { return event }
        let capsule = fieldWindow.convertToScreen(field.convert(field.bounds, to: nil)).insetBy(dx: -28, dy: -9)
        guard capsule.contains(point) else {
            if active {
                active = false
                onBlur()
            }
            return event
        }
        if clearButton(around: field, contains: point) != nil { return event }
        active = true
        onFocus()
        fieldWindow.makeFirstResponder(field)
        return nil
    }

    /// The note bar search field, wherever the toolbar put it.
    func searchField() -> NSTextField? {
        searchTextFieldInApp()
    }

    private func clickScreenPoint(_ event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else { return NSEvent.mouseLocation }
        return eventWindow.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    /// The note bar's search field. It lives in the short toolbar window.
    private func searchTextFieldInApp() -> NSTextField? {
        for window in NSApp.windows where window.frame.height <= 80 {
            if let field = searchTextField(in: window) ?? firstTextField(in: window) {
                return field
            }
        }
        for window in NSApp.windows {
            if let field = searchTextField(in: window) { return field }
        }
        return nil
    }

    private func firstTextField(in window: NSWindow) -> NSTextField? {
        let roots = [window.contentView?.superview, window.contentView].compactMap { $0 }
        for root in roots {
            if let field = firstTextField(in: root) { return field }
        }
        return nil
    }

    private func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for child in view.subviews {
            if let field = firstTextField(in: child) { return field }
        }
        return nil
    }

    private func searchTextField(in window: NSWindow) -> NSTextField? {
        let roots = [window.contentView?.superview, window.contentView].compactMap { $0 }
        for root in roots {
            if let field = searchTextField(in: root) { return field }
        }
        return nil
    }

    private func searchTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, isSearchField(field) { return field }
        for child in view.subviews {
            if let field = searchTextField(in: child) { return field }
        }
        return nil
    }

    private func isSearchField(_ field: NSTextField) -> Bool {
        field.accessibilityLabel() == "Search" || field.placeholderString == "Search"
    }

    private func clearButton(around field: NSTextField, contains point: NSPoint) -> NSButton? {
        guard let root = field.superview else { return nil }
        return clearButton(in: root, contains: point)
    }

    private func clearButton(in view: NSView, contains point: NSPoint) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == "Clear",
           let buttonWindow = button.window,
           buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) {
            return button
        }
        for child in view.subviews {
            if let button = clearButton(in: child, contains: point) { return button }
        }
        return nil
    }

    deinit {
        remove()
    }
}
