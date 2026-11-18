import XCTest

final class NoteCalendarTests: XCTestCase {
    func testEmptyNoteUsesTheListPlaceholders() {
        XCTAssertEqual(NoteCalendar.listTitle(""), "New Note")
        XCTAssertEqual(NoteCalendar.listTitle("   "), "New Note")
        XCTAssertEqual(NoteCalendar.listTitle("Spartan Race"), "Spartan Race")
        XCTAssertEqual(NoteCalendar.listPreview(""), "No additional text")
        XCTAssertEqual(NoteCalendar.listPreview("Hello"), "Hello")
    }

    func testGroupsMatchTheNoteListBuckets() {
        let calendar = newYork()
        let now = date(2026, 11, 15, 18, calendar)
        let today = note(iso(now, calendar), "today")
        let recent = note(iso(calendar.date(byAdding: .day, value: -10, to: now)!, calendar), "recent")
        let january = note(iso(date(2026, 1, 4, 12, calendar), calendar), "january")
        let older = note(iso(date(2020, 5, 2, 12, calendar), calendar), "older")
        let unknown = NoteSummary(
            id: "unknown",
            title: "Unknown",
            createdAtSource: "",
            modifiedAtSource: "not a date",
            folderID: nil
        )
        let groups = NoteCalendar.group(
            [older, unknown, january, recent, today],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(groups.map(\.key), ["today", "previous30", "month-0", "year-2020", "unknown"])
        XCTAssertEqual(groups.map(\.label), ["Today", "Previous 30 Days", "January", "2020", "Unknown Date"])
        XCTAssertEqual(groups[0].notes.map(\.id), ["today"])
    }

    func testFolderSelectionKeepsTheOpenNoteOrShowsTheFirst() {
        let calendar = newYork()
        let now = date(2026, 11, 15, 18, calendar)
        let older = note(iso(date(2026, 11, 15, 8, calendar), calendar), "older")
        let newer = note(iso(date(2026, 11, 15, 17, calendar), calendar), "newer")
        let notes = [older, newer]
        XCTAssertEqual(
            NoteCalendar.noteIDForSelection(in: notes, selectedID: "older", now: now, calendar: calendar),
            "older"
        )
        XCTAssertEqual(
            NoteCalendar.noteIDForSelection(in: notes, selectedID: "elsewhere", now: now, calendar: calendar),
            "newer"
        )
        XCTAssertNil(
            NoteCalendar.noteIDForSelection(in: [], selectedID: "older", now: now, calendar: calendar)
        )
    }

    func testDeleteSelectsTheNextVisibleNote() {
        let calendar = newYork()
        let now = date(2026, 11, 15, 18, calendar)
        let newest = note(iso(date(2026, 11, 15, 17, calendar), calendar), "newest")
        let middle = note(iso(date(2026, 11, 15, 9, calendar), calendar), "middle")
        let oldest = note(iso(date(2026, 11, 15, 8, calendar), calendar), "oldest")
        let notes = [oldest, newest, middle]
        XCTAssertEqual(
            NoteCalendar.noteIDAfterDelete(notes, deletedID: "newest", now: now, calendar: calendar),
            "middle"
        )
        XCTAssertEqual(
            NoteCalendar.noteIDAfterDelete(notes, deletedID: "middle", now: now, calendar: calendar),
            "oldest"
        )
        XCTAssertEqual(
            NoteCalendar.noteIDAfterDelete(notes, deletedID: "oldest", now: now, calendar: calendar),
            "middle"
        )
        XCTAssertNil(NoteCalendar.noteIDAfterDelete([middle], deletedID: "middle", now: now, calendar: calendar))
        XCTAssertNil(NoteCalendar.noteIDAfterDelete(notes, deletedID: "missing", now: now, calendar: calendar))
    }

    func testDeleteAtTheEndOfTheListSelectsThePreviousNote() {
        let calendar = newYork()
        let now = date(2026, 11, 15, 18, calendar)
        let today = note(iso(now, calendar), "today")
        let recent = note(iso(calendar.date(byAdding: .day, value: -10, to: now)!, calendar), "recent")
        let notes = [recent, today]
        XCTAssertEqual(
            NoteCalendar.noteIDAfterDelete(notes, deletedID: "today", now: now, calendar: calendar),
            "recent"
        )
        XCTAssertEqual(
            NoteCalendar.noteIDAfterDelete(notes, deletedID: "recent", now: now, calendar: calendar),
            "today"
        )
    }

    func testWeekdayDateWithSecondsParses() {
        let calendar = newYork()
        let parsed = NoteCalendar.parse(
            "Wednesday, June 3, 2026 at 8:10:03 PM",
            calendar: calendar
        )
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: parsed ?? .distantPast
        )
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 3)
        XCTAssertEqual(parts.hour, 20)
        XCTAssertEqual(parts.minute, 10)
        XCTAssertEqual(parts.second, 3)

        let narrowSpace = NoteCalendar.parse(
            "Friday, April 10, 2026 at 10:11:11\u{202f}AM",
            calendar: calendar
        )
        let morning = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: narrowSpace ?? .distantPast
        )
        XCTAssertEqual(morning.year, 2026)
        XCTAssertEqual(morning.month, 4)
        XCTAssertEqual(morning.day, 10)
        XCTAssertEqual(morning.hour, 10)
        XCTAssertEqual(morning.minute, 11)
    }

    func testSortAndGroupingFollowTheListMenu() {
        let calendar = newYork()
        let now = date(2026, 11, 15, 18, calendar)
        let notes = menuNotes(calendar: calendar)

        let edited = NoteCalendar.arrange(
            notes,
            arrangement: NoteListArrangement(field: .dateEdited, direction: .newestFirst, grouping: .groupsOff),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(edited.map(\.label), [""])
        XCTAssertEqual(edited.flatMap(\.notes).map(\.id), ["edited", "created"])

        let created = NoteCalendar.arrange(
            notes,
            arrangement: NoteListArrangement(field: .dateCreated, direction: .oldestFirst, grouping: .groupsOff),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(created.flatMap(\.notes).map(\.id), ["edited", "created"])

        let titles = NoteCalendar.arrange(
            notes,
            arrangement: NoteListArrangement(field: .title, direction: .newestFirst, grouping: .groupsOff),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(titles.flatMap(\.notes).map(\.id), ["created", "edited"])
        let reversedTitles = NoteCalendar.arrange(
            notes,
            arrangement: NoteListArrangement(field: .title, direction: .oldestFirst, grouping: .groupsOff),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(reversedTitles.flatMap(\.notes).map(\.id), ["edited", "created"])

        let oldestGroups = NoteCalendar.arrange(
            notes,
            arrangement: NoteListArrangement(
                field: .dateEditedDefault,
                direction: .oldestFirst,
                grouping: .onByDefault
            ),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(oldestGroups.map(\.key), ["year-2020", "today"])
    }

    func testListDateIsMonthDayAndShortYear() {
        let calendar = newYork()
        let november = note(iso(date(2026, 11, 6, 15, calendar), calendar), "november")
        let september = note(iso(date(2026, 9, 27, 9, calendar), calendar), "september")
        XCTAssertEqual(NoteCalendar.format(november, calendar: calendar), "11/6/26")
        XCTAssertEqual(NoteCalendar.format(september, calendar: calendar), "9/27/26")
        let missing = NoteSummary(
            id: "blank",
            title: "Blank",
            createdAtSource: "",
            modifiedAtSource: "",
            folderID: nil
        )
        XCTAssertEqual(NoteCalendar.format(missing, calendar: calendar), "")
    }

    func testHeadingDropsTheWeekdayAndSeconds() {
        let calendar = newYork()
        XCTAssertEqual(
            NoteCalendar.heading("Thursday, July 31, 2025 at 7:09:13 PM", calendar: calendar),
            "July 31, 2025 at 7:09 PM"
        )
        XCTAssertEqual(NoteCalendar.heading("  ", calendar: calendar), "Unknown Date")
        XCTAssertEqual(NoteCalendar.heading("not a date", calendar: calendar), "not a date")
    }

    func testAppleNoteDateWithAtParses() {
        let calendar = newYork()
        let parsed = NoteCalendar.parse("April 15, 2026 at 3:22 PM", calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed ?? .distantPast)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 4)
        XCTAssertEqual(parts.day, 15)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 22)
    }

    private func menuNotes(calendar: Calendar) -> [NoteSummary] {
        let editedLater = NoteSummary(
            id: "edited",
            title: "Bravo",
            createdAtSource: iso(date(2020, 5, 2, 12, calendar), calendar),
            modifiedAtSource: iso(date(2026, 11, 15, 17, calendar), calendar),
            folderID: nil
        )
        let createdLater = NoteSummary(
            id: "created",
            title: "alpha",
            createdAtSource: iso(date(2026, 11, 15, 9, calendar), calendar),
            modifiedAtSource: iso(date(2020, 1, 4, 12, calendar), calendar),
            folderID: nil
        )
        return [createdLater, editedLater]
    }

    /// One note list render: arrange about 300 notes, then format each row's date.
    func testListOfThreeHundredNotesArrangesQuickly() {
        let calendar = newYork()
        let spelled = DateFormatter()
        spelled.calendar = calendar
        spelled.locale = Locale(identifier: "en_US_POSIX")
        spelled.timeZone = calendar.timeZone
        spelled.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        let notes = (0..<300).map { index -> NoteSummary in
            let day = date(2020 + index % 7, 1 + index % 12, 1 + index % 28, index % 24, calendar)
            let source = index.isMultiple(of: 2) ? iso(day, calendar) : spelled.string(from: day)
            return note(source, "note-\(index)")
        }
        let now = date(2026, 11, 18, 12, calendar)
        measure {
            let groups = NoteCalendar.arrange(notes, now: now, calendar: calendar)
            let dates = groups.flatMap(\.notes).map { NoteCalendar.format($0, calendar: calendar) }
            XCTAssertEqual(dates.count, notes.count)
        }
    }

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return calendar.date(from: parts)!
    }

    private func iso(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func note(_ source: String, _ id: String) -> NoteSummary {
        NoteSummary(
            id: id,
            title: id,
            createdAtSource: source,
            modifiedAtSource: source,
            folderID: nil
        )
    }
}
