import AppKit
import SwiftUI
import XCTest

/// One window with a toolbar item that holds a capsule, its text field, and a clear button area.
@MainActor
private final class SearchItemFixture {
    let window: NSWindow
    let capsule = NSView(frame: NSRect(x: 100, y: 100, width: 280, height: 34))
    let field = NSTextField(frame: NSRect(x: 130, y: 108, width: 200, height: 18))
    let clearButtonArea = NSView(frame: NSRect(x: 350, y: 108, width: 16, height: 18))
    let monitor = SearchClickMonitor()
    var focusCount = 0
    var blurCount = 0

    init(origin: NSPoint) {
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: 600, height: 300)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let item = NSView(frame: window.contentView!.bounds)
        field.placeholderString = "Search"
        item.addSubview(capsule)
        item.addSubview(field)
        item.addSubview(clearButtonArea)
        window.contentView!.addSubview(item)
        monitor.capsule = capsule
        monitor.clearButtonArea = clearButtonArea
        monitor.onFocus = { [unowned self] in focusCount += 1 }
        monitor.onBlur = { [unowned self] in blurCount += 1 }
    }

    func mouseDown(at point: NSPoint, in eventWindow: NSWindow? = nil) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: (eventWindow ?? window).windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    var fieldIsEditing: Bool {
        (window.firstResponder as? NSText)?.delegate === field
    }
}

@MainActor
final class NoteSearchFieldTests: XCTestCase {
    func testSearchFieldIsTheTextFieldInsideItsOwnCapsule() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        let other = SearchItemFixture(origin: NSPoint(x: 0, y: 400))
        let stray = NSTextField(frame: NSRect(x: 420, y: 200, width: 100, height: 20))
        stray.placeholderString = "Search"
        fixture.window.contentView!.addSubview(stray)

        XCTAssertTrue(fixture.monitor.searchField === fixture.field)
        XCTAssertTrue(other.monitor.searchField === other.field)

        fixture.capsule.removeFromSuperview()
        XCTAssertNil(fixture.monitor.searchField, "A capsule outside a window has no field.")
    }

    func testClickOnCapsuleFocusesItsFieldAndConsumesTheClick() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))

        let result = fixture.monitor.handleMouseDown(fixture.mouseDown(at: NSPoint(x: 110, y: 117)))

        XCTAssertNil(result)
        XCTAssertEqual(fixture.focusCount, 1)
        XCTAssertTrue(fixture.monitor.isActive)
        XCTAssertTrue(fixture.fieldIsEditing)
    }

    func testClickOnClearButtonPassesThrough() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        let event = fixture.mouseDown(at: NSPoint(x: 358, y: 117))

        XCTAssertTrue(fixture.monitor.handleMouseDown(event) === event)
        XCTAssertEqual(fixture.focusCount, 0)
        XCTAssertEqual(fixture.blurCount, 0)
    }

    func testOutsideClickEndsSearchFocusOnce() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        _ = fixture.monitor.handleMouseDown(fixture.mouseDown(at: NSPoint(x: 110, y: 117)))

        let outside = fixture.mouseDown(at: NSPoint(x: 20, y: 20))
        XCTAssertTrue(fixture.monitor.handleMouseDown(outside) === outside)
        _ = fixture.monitor.handleMouseDown(fixture.mouseDown(at: NSPoint(x: 20, y: 20)))

        XCTAssertEqual(fixture.blurCount, 1)
        XCTAssertFalse(fixture.monitor.isActive)
    }

    func testClickInAnotherWindowDoesNotFocusThisField() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        let noteWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        noteWindow.isReleasedWhenClosed = false
        fixture.monitor.markSearchActive()

        let event = fixture.mouseDown(at: NSPoint(x: 110, y: 117), in: noteWindow)

        XCTAssertTrue(fixture.monitor.handleMouseDown(event) === event)
        XCTAssertEqual(fixture.focusCount, 0)
        XCTAssertEqual(fixture.blurCount, 1, "A click in another window ends this field's focus.")
        XCTAssertFalse(fixture.fieldIsEditing)
    }

    func testEachWindowFocusesOnlyItsOwnField() {
        let first = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        let second = SearchItemFixture(origin: NSPoint(x: 0, y: 400))
        _ = first.monitor.handleMouseDown(first.mouseDown(at: NSPoint(x: 110, y: 117)))

        let click = second.mouseDown(at: NSPoint(x: 110, y: 117))
        XCTAssertTrue(first.monitor.handleMouseDown(click) === click)
        XCTAssertNil(second.monitor.handleMouseDown(click))

        XCTAssertEqual(first.blurCount, 1)
        XCTAssertEqual(second.focusCount, 1)
        XCTAssertTrue(second.fieldIsEditing)
        XCTAssertEqual(first.focusCount, 1)
    }

    func testOwningWindowResigningKeyEndsSearchFocus() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        let other = SearchItemFixture(origin: NSPoint(x: 0, y: 400))
        fixture.monitor.install()
        defer { fixture.monitor.remove() }
        fixture.monitor.markSearchActive()

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other.window)
        XCTAssertEqual(fixture.blurCount, 0)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        XCTAssertEqual(fixture.blurCount, 1)
    }

    func testEachSuggestionRowTakesClicksOnItself() {
        let list = SuggestionListView()
        for (index, scope) in NoteSearchScope.menuScopes.enumerated() {
            let rowMiddle = SuggestionListView.menuInset
                + SuggestionListView.rowHeight * (CGFloat(index) + 0.5)
            let point = NSPoint(x: 40, y: rowMiddle)

            let hits = list.subviews.compactMap { $0.hitTest(point) }

            XCTAssertEqual(hits.count, 1, "Only one row takes a click on \(scope.title).")
            XCTAssertEqual(hits.first?.accessibilityLabel(), scope.title)
        }
    }

    func testRemovedMonitorIgnoresOwningWindowResigningKey() {
        let fixture = SearchItemFixture(origin: NSPoint(x: 0, y: 0))
        fixture.monitor.install()
        fixture.monitor.remove()
        fixture.monitor.markSearchActive()

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)

        XCTAssertEqual(fixture.blurCount, 0)
    }
}

/// The real search field in a real window toolbar, driven by events through the app's event queue.
@MainActor
final class NoteSearchFieldToolbarTests: XCTestCase {
    private final class SearchModel: ObservableObject {
        @Published var text = ""
        @Published var scope: NoteSearchScope?
    }

    private struct ToolbarHost: View {
        @ObservedObject var model: SearchModel

        var body: some View {
            Color.clear
                .frame(width: 900, height: 400)
                .toolbar {
                    ToolbarItem(id: "note-search", placement: .primaryAction) {
                        NoteSearchField(text: $model.text, scope: $model.scope)
                            .fixedSize()
                    }
                }
        }
    }

    private var model: SearchModel!
    private var window: NSWindow!

    override func setUp() async throws {
        _ = NSApplication.shared
        model = SearchModel()
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let hosting = NSHostingController(rootView: ToolbarHost(model: model))
        hosting.sceneBridgingOptions = .toolbars
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
        pump(until: { self.searchTextField() != nil })
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window.close()
        window = nil
        model = nil
        pump(seconds: 0.1)
    }

    func testClickFocusesShowsSuggestionsAndOutsideClickDismisses() throws {
        let field = try XCTUnwrap(searchTextField())

        click(at: capsulePoint(for: field, offset: -100))

        XCTAssertTrue(isEditing(field), "A click on the capsule focuses the field.")
        XCTAssertTrue(suggestionMenuIsVisible(), "An empty, focused field shows the suggestions.")

        click(at: NSPoint(x: 40, y: 40))

        XCTAssertFalse(suggestionMenuIsVisible(), "An outside click hides the suggestions.")
    }

    /// The clear button's own click needs an active app, which a test cannot be without taking
    /// the keyboard. `NoteSearchFieldTests` covers the monitor passing that click through.
    func testTypingFiltersAndShowsTheClearButtonInsideTheCapsule() throws {
        let field = try XCTUnwrap(searchTextField())
        click(at: capsulePoint(for: field, offset: 0))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)

        editor.insertText("funny", replacementRange: NSRange(location: NSNotFound, length: 0))
        pump(until: { self.model.text == "funny" })
        XCTAssertEqual(model.text, "funny")
        XCTAssertFalse(suggestionMenuIsVisible(), "Typed text hides the suggestions.")

        pump(until: { self.clearButtonArea() != nil })
        let clearButton = try XCTUnwrap(clearButtonArea(), "Typed text shows the clear button.")
        let clearFrame = clearButton.convert(clearButton.bounds, to: nil)
        let fieldFrame = field.convert(field.bounds, to: nil)
        XCTAssertGreaterThan(clearFrame.minX, fieldFrame.maxX, "The clear button sits after the text.")
        XCTAssertTrue(isEditing(field))
    }

    func testCommandFInsideTheSearchFieldOpensNoteFindNotLibrarySearch() throws {
        let field = try XCTUnwrap(searchTextField())
        click(at: capsulePoint(for: field, offset: 0))
        var findWindow: NSWindow?
        let observer = NotificationCenter.default.addObserver(
            forName: .showNoteFind,
            object: nil,
            queue: nil
        ) { notification in
            findWindow = notification.object as? NSWindow
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        post(keyDown: "f", modifiers: .command)

        XCTAssertTrue(findWindow === window, "Command-F asks this window's note to find.")
        XCTAssertEqual(model.text, "", "Command-F does not type into the library search.")
    }

    private func searchTextField() -> NSTextField? {
        guard let root = window.contentView?.superview else { return nil }
        return textField(in: root)
    }

    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == "Search" {
            return field
        }
        for child in view.subviews {
            if let field = textField(in: child) { return field }
        }
        return nil
    }

    /// The view the field places behind its clear button, while the button is shown.
    private func clearButtonArea() -> NSView? {
        guard let root = window.contentView?.superview else { return nil }
        return view(in: root) { String(describing: type(of: $0)).contains("SearchClearButtonArea") }
    }

    private func view(in root: NSView, where matches: (NSView) -> Bool) -> NSView? {
        if matches(root), root.window != nil { return root }
        for child in root.subviews {
            if let found = view(in: child, where: matches) { return found }
        }
        return nil
    }

    private func capsulePoint(for field: NSTextField, offset: CGFloat) -> NSPoint {
        let frame = field.convert(field.bounds, to: nil)
        let x = offset < 0 ? frame.minX - 14 : frame.midX + offset
        return NSPoint(x: x, y: frame.midY)
    }

    private func isEditing(_ field: NSTextField) -> Bool {
        (window.firstResponder as? NSText)?.delegate === field
    }

    private func suggestionMenuIsVisible() -> Bool {
        NSApp.windows.contains { $0 is SearchSuggestionPanel && $0.isVisible }
    }

    private func click(at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )!
            NSApp.postEvent(event, atStart: false)
        }
        pump(seconds: 0.3)
    }

    private func post(keyDown characters: String, modifiers: NSEvent.ModifierFlags) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 3
        )!
        NSApp.postEvent(event, atStart: false)
        pump(seconds: 0.3)
    }

    private func pump(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(
                matching: .any,
                until: Date().addingTimeInterval(0.01),
                inMode: .default,
                dequeue: true
            ) {
                NSApp.sendEvent(event)
            }
        }
    }

    private func pump(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            pump(seconds: 0.05)
        }
    }
}
