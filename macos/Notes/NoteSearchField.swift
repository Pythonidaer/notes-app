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
    @StateObject private var clickMonitor = SearchClickMonitor()

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
                .background(SearchClearButtonArea(monitor: clickMonitor))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.fieldWidth, height: Self.fieldHeight)
        .background {
            ZStack {
                Capsule().fill(fill)
                SearchSuggestionAnchor(
                    monitor: clickMonitor,
                    allowsSuggestions: suggestionsAllowed,
                    onSelect: choose
                )
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
            clickMonitor.onFocus = {
                focusSearch()
                installFindMonitor(true)
            }
            clickMonitor.onBlur = {
                assignSearchFocused(false)
                installFindMonitor(false)
                publishSuggestions(focused: false)
            }
            clickMonitor.install()
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                clickMonitor.markSearchActive()
                assignSearchFocused(true)
            }
            installFindMonitor(isFocused || searchFocused)
        }
        .onDisappear {
            clickMonitor.remove()
            installFindMonitor(false)
        }
    }

    /// Measured in Notes, dark mode. The focus ring around the search capsule.
    static let focusRing = Color(red: 121.0 / 255, green: 82.0 / 255, blue: 129.0 / 255)

    /// The menu lists scopes only while the field is empty and no scope is chosen.
    private var suggestionsAllowed: Bool {
        text.isEmpty && scope == nil
    }

    private func focusSearch() {
        clickMonitor.markSearchActive()
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
        clickMonitor.applySuggestions(focused: focused, allowed: suggestionsAllowed)
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

/// Pins the suggestion menu under the search capsule. Its view is the capsule's frame.
private struct SearchSuggestionAnchor: NSViewRepresentable {
    var monitor: SearchClickMonitor
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
        coordinator.monitor = monitor
        monitor.capsule = view
        monitor.suggestions = coordinator
        coordinator.preparePanel()
        coordinator.sync()
    }

    static func dismantleNSView(_ nsView: SuggestionAnchorView, coordinator: Coordinator) {
        coordinator.monitor?.detachSuggestions(coordinator)
        coordinator.hide()
    }

    final class Coordinator: SearchSuggestionPresenting {
        /// Set from the click, so the menu does not wait for the next SwiftUI render.
        var focused = false
        /// The field is empty and no scope is selected.
        var allowsSuggestions = false
        var onSelect: (NoteSearchScope) -> Void = { _ in }
        weak var anchor: SuggestionAnchorView?
        weak var monitor: SearchClickMonitor?
        private(set) var panel: SearchSuggestionPanel?

        func apply(focused: Bool? = nil, allowed: Bool) {
            if let focused { self.focused = focused }
            allowsSuggestions = allowed
            sync()
        }

        func preparePanel() {
            _ = ensurePanel()
        }

        /// Shows the menu under the capsule, or hides it while the capsule is not in a window.
        func sync() {
            guard focused, allowsSuggestions else {
                hide()
                return
            }
            guard let anchor, anchor.window != nil, anchor.bounds.width > 1 else {
                hide()
                return
            }
            let panel = ensurePanel()
            panel.list.onSelect = onSelect
            panel.place(under: anchor)
        }

        func hide() {
            panel?.orderOffScreen()
        }

        func isMenu(_ window: NSWindow) -> Bool {
            window === panel
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

/// The capsule behind the search field. It only positions the menu and marks the capsule's frame.
private final class SuggestionAnchorView: PassthroughView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
}

/// Marks the clear button's frame, so the click monitor leaves those clicks to the button.
private struct SearchClearButtonArea: NSViewRepresentable {
    var monitor: SearchClickMonitor

    func makeNSView(context: Context) -> PassthroughView {
        PassthroughView()
    }

    func updateNSView(_ view: PassthroughView, context: Context) {
        monitor.clearButtonArea = view
    }
}

/// A view that marks a frame. Clicks pass through to the controls under it.
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The suggestion menu that belongs to one search field.
protocol SearchSuggestionPresenting: AnyObject {
    /// Shows or hides the menu before the current event returns.
    func apply(focused: Bool?, allowed: Bool)
    /// Whether `window` is this field's menu.
    func isMenu(_ window: NSWindow) -> Bool
}

/// Focuses one note bar search field when a click lands on its capsule.
///
/// The toolbar can swallow the click before SwiftUI sees it, so the field is focused from the
/// mouse-down. Each field owns its monitor. The monitor knows its field's capsule and clear
/// button through views the field places, and finds the text field inside that capsule, in the
/// capsule's window. It focuses only that control. A click anywhere else, or the capsule's
/// window resigning key, ends the search focus. The suggestion menu is shown and hidden here,
/// in the mouse-down handler.
final class SearchClickMonitor: ObservableObject {
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}
    /// The capsule's frame. Its window is the window that owns this search field.
    weak var capsule: NSView?
    /// The clear button's frame, while the button is shown.
    weak var clearButtonArea: NSView?
    weak var suggestions: SearchSuggestionPresenting?
    /// The search field holds focus, so the next outside click ends it.
    private(set) var isActive = false
    private var mouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private weak var cachedSearchField: NSTextField?

    /// Starts watching mouse-downs and the owning window's key state. Calling it again does nothing.
    func install() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleMouseDown(event) ?? event
            }
        }
        if resignKeyObserver == nil {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.ownerWindowDidResignKey(notification.object as? NSWindow)
            }
        }
    }

    /// Stops watching. The owning view calls this when it leaves the toolbar.
    func remove() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
    }

    func detachSuggestions(_ presenter: SearchSuggestionPresenting) {
        if suggestions === presenter {
            suggestions = nil
        }
    }

    /// A focus that did not come through the click monitor still dismisses on the next outside click.
    func markSearchActive() {
        isActive = true
    }

    /// Shows or hides the menu before this mouse-down returns.
    func applySuggestions(focused: Bool? = nil, allowed: Bool) {
        suggestions?.apply(focused: focused, allowed: allowed)
    }

    /// The editable text field inside the capsule, in the capsule's window.
    ///
    /// The lookup walks up from the capsule and searches each ancestor, so the field in the same
    /// toolbar item is found first. The result is cached until it leaves the capsule. A cold
    /// lookup is linear in the views of the capsule's window.
    var searchField: NSTextField? {
        guard let capsule, capsule.window != nil else { return nil }
        if let cachedSearchField, Self.isTextField(cachedSearchField, inside: capsule) {
            return cachedSearchField
        }
        cachedSearchField = Self.textField(inside: capsule)
        return cachedSearchField
    }

    /// Focuses the field for a click on its capsule and consumes the click.
    ///
    /// A click on the clear button or on this field's menu passes through. Any other click ends
    /// the search focus. A click in another window never focuses this field, even over the capsule.
    func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if let eventWindow = event.window, suggestions?.isMenu(eventWindow) == true {
            return event
        }
        guard let capsule, let ownerWindow = capsule.window, event.window === ownerWindow,
              let field = searchField else {
            endSearchFocus()
            return event
        }
        let point = event.locationInWindow
        guard Self.windowFrame(of: capsule).contains(point) else {
            endSearchFocus()
            return event
        }
        if let clearButtonArea, clearButtonArea.window === ownerWindow,
           Self.windowFrame(of: clearButtonArea).contains(point) {
            return event
        }
        isActive = true
        onFocus()
        if !ownerWindow.isKeyWindow, ownerWindow.canBecomeKey {
            ownerWindow.makeKey()
        }
        ownerWindow.makeFirstResponder(field)
        return nil
    }

    private func ownerWindowDidResignKey(_ window: NSWindow?) {
        guard let window, window === capsule?.window else { return }
        endSearchFocus()
    }

    private func endSearchFocus() {
        guard isActive else { return }
        isActive = false
        onBlur()
    }

    private static func windowFrame(of view: NSView) -> NSRect {
        view.convert(view.bounds, to: nil)
    }

    private static func isTextField(_ field: NSTextField, inside capsule: NSView) -> Bool {
        guard field.isEditable, field.window != nil, field.window === capsule.window else { return false }
        let center = NSPoint(x: field.bounds.midX, y: field.bounds.midY)
        return capsule.bounds.contains(capsule.convert(center, from: field))
    }

    private static func textField(inside capsule: NSView) -> NSTextField? {
        var ancestor = capsule.superview
        while let view = ancestor {
            if let field = textField(in: view, inside: capsule) { return field }
            ancestor = view.superview
        }
        return nil
    }

    private static func textField(in view: NSView, inside capsule: NSView) -> NSTextField? {
        if view is WKWebView { return nil }
        if let field = view as? NSTextField, isTextField(field, inside: capsule) { return field }
        for child in view.subviews {
            if let field = textField(in: child, inside: capsule) { return field }
        }
        return nil
    }

    deinit {
        remove()
    }
}
