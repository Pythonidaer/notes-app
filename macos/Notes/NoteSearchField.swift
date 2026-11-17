import AppKit
import SwiftUI
import WebKit

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
                SearchSuggestionAnchor(allowsSuggestions: suggestionsAllowed, onSelect: choose)
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
        .animation(nil, value: searchFocused)
        .contentShape(Capsule())
        .onTapGesture { focusSearch() }
        .onAppear {
            SearchClickMonitor.shared.onFocus = {
                focusSearch()
                installFindMonitor(true)
            }
            SearchClickMonitor.shared.onBlur = {
                assignSearchFocused(false)
                installFindMonitor(false)
                publishSuggestions(focused: false)
            }
            SearchClickMonitor.shared.install()
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { assignSearchFocused(true) }
            installFindMonitor(isFocused || searchFocused)
        }
        .onDisappear { installFindMonitor(false) }
    }

    /// Measured in Notes, dark mode. The focus ring around the search capsule.
    static let focusRing = Color(red: 121.0 / 255, green: 82.0 / 255, blue: 129.0 / 255)

    /// The menu lists scopes only while the field is empty and no scope is chosen.
    private var suggestionsAllowed: Bool {
        text.isEmpty && scope == nil
    }

    private func focusSearch() {
        SearchClickMonitor.shared.markSearchActive()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            searchFocused = true
            focused = true
        }
        publishSuggestions(focused: true)
    }

    private func assignSearchFocused(_ isFocused: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            searchFocused = isFocused
        }
    }

    /// Shows or hides the menu in this event.
    ///
    /// The click monitor runs before SwiftUI renders `searchFocused`. Waiting for that
    /// render is the delay before the menu opens and before it closes.
    private func publishSuggestions(focused: Bool? = nil) {
        SearchClickMonitor.shared.applySuggestions(focused: focused, allowed: suggestionsAllowed)
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
        defer { publishSuggestions() }
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
    var allowsSuggestions: Bool
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
        let coordinator = context.coordinator
        coordinator.allowsSuggestions = allowsSuggestions
        coordinator.onSelect = onSelect
        coordinator.anchor = view
        SearchClickMonitor.shared.attachSuggestions(coordinator)
        SearchClickMonitor.shared.rememberSearchField(near: view)
        coordinator.preparePanel()
        coordinator.sync()
    }

    static func dismantleNSView(_ nsView: SuggestionAnchorView, coordinator: Coordinator) {
        SearchClickMonitor.shared.detachSuggestions(coordinator)
        coordinator.hide()
    }

    final class Coordinator {
        /// Set from the click, so the menu does not wait for the next SwiftUI render.
        var focused = false
        /// The field is empty and no scope is selected.
        var allowsSuggestions = false
        var onSelect: (NoteSearchScope) -> Void = { _ in }
        weak var anchor: SuggestionAnchorView?
        private var panel: SearchSuggestionPanel?

        func apply(focused: Bool? = nil, allowed: Bool) {
            if let focused { self.focused = focused }
            allowsSuggestions = allowed
            sync()
        }

        func preparePanel() {
            _ = ensurePanel()
        }

        func sync() {
            guard focused, allowsSuggestions else {
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
            panel?.orderOffScreen()
        }

        private func ensurePanel() -> SearchSuggestionPanel {
            if let panel { return panel }
            let created = SearchSuggestionPanel()
            created.contentView?.layoutSubtreeIfNeeded()
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
/// The suggestion menu is shown and hidden here, in the mouse-down handler.
final class SearchClickMonitor {
    static let shared = SearchClickMonitor()
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}
    private var monitor: Any?
    private var active = false
    private weak var suggestions: SearchSuggestionAnchor.Coordinator?
    private weak var cachedSearchField: NSTextField?

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

    fileprivate func attachSuggestions(_ coordinator: SearchSuggestionAnchor.Coordinator) {
        suggestions = coordinator
    }

    fileprivate func detachSuggestions(_ coordinator: SearchSuggestionAnchor.Coordinator) {
        if suggestions === coordinator {
            suggestions = nil
        }
    }

    /// A focus that did not come through the click monitor still dismisses on the next outside click.
    fileprivate func markSearchActive() {
        active = true
    }

    /// Shows or hides the menu before this mouse-down returns.
    fileprivate func applySuggestions(focused: Bool? = nil, allowed: Bool) {
        suggestions?.apply(focused: focused, allowed: allowed)
    }

    /// Keeps the field found while the anchor is on screen, so a click does not search for it.
    fileprivate func rememberSearchField(near anchor: NSView) {
        guard let window = anchor.window else { return }
        if let cachedSearchField, cachedSearchField.window === window, isSearchField(cachedSearchField) {
            return
        }
        cachedSearchField = searchTextField(in: window)
    }

    /// A click on the clear button is left alone. Other clicks inside the capsule are consumed.
    private func focusSearchField(for event: NSEvent) -> NSEvent? {
        let point = clickScreenPoint(event)
        if event.window is SearchSuggestionPanel { return event }
        guard let field = searchField(preferring: event.window), let fieldWindow = field.window else { return event }
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
        searchField(preferring: nil)
    }

    /// Uses the cached field. A cold lookup checks `window` before the other windows.
    private func searchField(preferring window: NSWindow?) -> NSTextField? {
        if let cachedSearchField, cachedSearchField.window != nil, isSearchField(cachedSearchField) {
            return cachedSearchField
        }
        if let window, let field = searchTextField(in: window) {
            cachedSearchField = field
            return field
        }
        let found = searchTextFieldInApp()
        cachedSearchField = found
        return found
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
        if view is WKWebView { return nil }
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
        if view is WKWebView { return nil }
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
        if view is WKWebView { return nil }
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
