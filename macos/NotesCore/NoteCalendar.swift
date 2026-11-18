import Foundation

enum NoteSortField: String, Equatable {
    case dateEditedDefault = "default"
    case dateEdited = "edited"
    case dateCreated = "created"
    case title
}

enum NoteSortDirection: String, Equatable {
    case newestFirst = "newest"
    case oldestFirst = "oldest"
}

enum NoteDateGrouping: String, Equatable {
    case onByDefault = "default"
    case groupsOn = "on"
    case groupsOff = "off"

    var showsGroups: Bool { self != .groupsOff }
}

struct NoteListArrangement: Equatable {
    var field: NoteSortField = .dateEditedDefault
    var direction: NoteSortDirection = .newestFirst
    var grouping: NoteDateGrouping = .onByDefault

    private static let fieldKey = "notes.list.field"
    private static let directionKey = "notes.list.direction"
    private static let groupingKey = "notes.list.grouping"

    static var stored: NoteListArrangement {
        let defaults = UserDefaults.standard
        return NoteListArrangement(
            field: NoteSortField(rawValue: defaults.string(forKey: fieldKey) ?? "") ?? .dateEditedDefault,
            direction: NoteSortDirection(rawValue: defaults.string(forKey: directionKey) ?? "") ?? .newestFirst,
            grouping: NoteDateGrouping(rawValue: defaults.string(forKey: groupingKey) ?? "") ?? .onByDefault
        )
    }

    func store() {
        let defaults = UserDefaults.standard
        defaults.set(field.rawValue, forKey: Self.fieldKey)
        defaults.set(direction.rawValue, forKey: Self.directionKey)
        defaults.set(grouping.rawValue, forKey: Self.groupingKey)
    }
}

enum NoteCalendar {
    static let monthLabels = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    struct Group: Identifiable, Equatable {
        var key: String
        var label: String
        var notes: [NoteSummary]
        var id: String { key }
    }

    static func effectiveDate(
        _ note: NoteSummary,
        calendar: Calendar = .current
    ) -> Date? {
        parse(note.modifiedAtSource, calendar: calendar)
            ?? parse(note.createdAtSource, calendar: calendar)
    }

    static func group(
        _ notes: [NoteSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Group] {
        arrange(notes, now: now, calendar: calendar)
    }

    static func arrange(
        _ notes: [NoteSummary],
        arrangement: NoteListArrangement = NoteListArrangement(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Group] {
        let newestFirst = arrangement.direction == .newestFirst
        if !arrangement.grouping.showsGroups {
            let ordered = sorted(notes, field: arrangement.field, newestFirst: newestFirst, calendar: calendar)
            return ordered.isEmpty ? [] : [Group(key: "all", label: "", notes: ordered)]
        }

        var buckets: [String: (label: String, notes: [DatedNote])] = [:]
        for note in notes {
            let dated = DatedNote(note: note, date: date(for: note, field: arrangement.field, calendar: calendar))
            let classified = classify(date: dated.date, now: now, calendar: calendar)
            var bucket = buckets[classified.key] ?? (classified.label, [])
            bucket.notes.append(dated)
            buckets[classified.key] = bucket
        }

        var ordered: [Group] = []
        func add(_ key: String, _ fallback: String) {
            guard let bucket = buckets[key], !bucket.notes.isEmpty else { return }
            ordered.append(Group(
                key: key,
                label: bucket.label.isEmpty ? fallback : bucket.label,
                notes: sorted(bucket.notes, field: arrangement.field, newestFirst: newestFirst)
            ))
        }

        add("today", "Today")
        add("previous30", "Previous 30 Days")
        for (month, label) in monthLabels.enumerated() {
            add("month-\(month)", label)
        }
        let years = buckets.keys.compactMap { key -> Int? in
            guard key.hasPrefix("year-") else { return nil }
            return Int(key.dropFirst("year-".count))
        }.sorted(by: >)
        for year in years {
            add("year-\(year)", String(year))
        }
        add("unknown", "Unknown Date")
        if !newestFirst {
            ordered.reverse()
        }
        return ordered
    }

    static func noteIDAfterDelete(
        _ notes: [NoteSummary],
        deletedID: String,
        arrangement: NoteListArrangement = NoteListArrangement(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let ordered = arrange(notes, arrangement: arrangement, now: now, calendar: calendar).flatMap(\.notes)
        guard let index = ordered.firstIndex(where: { $0.id == deletedID }) else { return nil }
        if index + 1 < ordered.count {
            return ordered[index + 1].id
        }
        if index > 0 {
            return ordered[index - 1].id
        }
        return nil
    }

    /// The note to open for this list.
    ///
    /// Keeps `selectedID` when that note is still in `notes`. Otherwise returns the first note
    /// in list order. An empty list returns nil, which leaves the note column blank.
    static func noteIDForSelection(
        in notes: [NoteSummary],
        selectedID: String?,
        arrangement: NoteListArrangement = NoteListArrangement(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        if let selectedID, notes.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return arrange(notes, arrangement: arrangement, now: now, calendar: calendar)
            .lazy
            .compactMap(\.notes.first)
            .first?
            .id
    }

    /// The list date, such as 11/6/26.
    static func format(_ note: NoteSummary, calendar: Calendar = .current) -> String {
        guard let date = effectiveDate(note, calendar: calendar) else {
            return ""
        }
        return CachedFormatters.dateFormatter("M/d/yy", locale: "en_US_POSIX", calendar: calendar)
            .string(from: date)
    }

    static func heading(_ raw: String, calendar: Calendar = .current) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Date" }
        guard let date = parse(trimmed, calendar: calendar) else { return trimmed }
        return CachedFormatters.dateFormatter("MMMM d, yyyy 'at' h:mm a", locale: "en_US", calendar: calendar)
            .string(from: date)
    }

    static func parse(_ raw: String?, calendar: Calendar = .current) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = parseISO(trimmed) { return date }
        let withoutAt = trimmed.replacingOccurrences(
            of: #"\s+at\s+"#,
            with: " ",
            options: .regularExpression
        )
        if withoutAt != trimmed, let date = parseISO(withoutAt) { return date }
        if let date = parseFormatted(trimmed, calendar: calendar) { return date }
        if withoutAt != trimmed, let date = parseFormatted(withoutAt, calendar: calendar) { return date }
        return parseDay(trimmed, calendar: calendar)
    }

    private static func date(
        for note: NoteSummary,
        field: NoteSortField,
        calendar: Calendar
    ) -> Date? {
        switch field {
        case .dateCreated:
            return parse(note.createdAtSource, calendar: calendar) ?? parse(note.modifiedAtSource, calendar: calendar)
        case .dateEditedDefault, .dateEdited, .title:
            return parse(note.modifiedAtSource, calendar: calendar) ?? parse(note.createdAtSource, calendar: calendar)
        }
    }

    private static func classify(
        date: Date?,
        now: Date,
        calendar: Calendar
    ) -> (key: String, label: String) {
        guard let date else {
            return ("unknown", "Unknown Date")
        }
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        if date >= todayStart && date < tomorrowStart {
            return ("today", "Today")
        }
        let previousLower = calendar.date(byAdding: .day, value: -30, to: todayStart) ?? todayStart
        if date >= previousLower && date < todayStart {
            return ("previous30", "Previous 30 Days")
        }
        let noteYear = calendar.component(.year, from: date)
        if noteYear == calendar.component(.year, from: now) {
            let month = calendar.component(.month, from: date) - 1
            let label = monthLabels.indices.contains(month) ? monthLabels[month] : "Unknown Date"
            return ("month-\(month)", label)
        }
        return ("year-\(noteYear)", String(noteYear))
    }

    /// A note with its sort date parsed once, so sorting does not parse it again for every comparison.
    private struct DatedNote {
        var note: NoteSummary
        var date: Date?
    }

    private static func sorted(
        _ notes: [NoteSummary],
        field: NoteSortField,
        newestFirst: Bool,
        calendar: Calendar
    ) -> [NoteSummary] {
        let dated = notes.map { DatedNote(note: $0, date: date(for: $0, field: field, calendar: calendar)) }
        return sorted(dated, field: field, newestFirst: newestFirst)
    }

    private static func sorted(
        _ notes: [DatedNote],
        field: NoteSortField,
        newestFirst: Bool
    ) -> [NoteSummary] {
        notes.sorted { left, right in
            if field == .title {
                let order = titleKey(left.note).localizedCaseInsensitiveCompare(titleKey(right.note))
                if order == .orderedSame { return left.note.id < right.note.id }
                return newestFirst ? order == .orderedAscending : order == .orderedDescending
            }
            switch (left.date, right.date) {
            case (nil, nil):
                return left.note.id < right.note.id
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (leftDate?, rightDate?):
                if leftDate == rightDate { return left.note.id < right.note.id }
                return newestFirst ? leftDate > rightDate : leftDate < rightDate
            }
        }
        .map(\.note)
    }

    /// The list title. An empty note is "New Note" until a title is typed.
    static func listTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    /// The list preview. An empty body is "No additional text".
    static func listPreview(_ opening: String) -> String {
        let trimmed = opening.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No additional text" : trimmed
    }

    private static func titleKey(_ note: NoteSummary) -> String {
        listTitle(note.title)
    }

    private static func parseISO(_ value: String) -> Date? {
        // An ISO date starts with the year. Spelled-out dates skip two failed parses.
        guard value.first?.isNumber == true else { return nil }
        if let date = CachedFormatters.fractionalISO.date(from: value) { return date }
        return CachedFormatters.iso.date(from: value)
    }

    private static func parseFormatted(_ value: String, calendar: Calendar) -> Date? {
        let formats = [
            "EEEE, MMMM d, yyyy 'at' h:mm:ss a",
            "EEEE, MMMM d, yyyy h:mm:ss a",
            "EEEE, MMMM d, yyyy 'at' h:mm a",
            "EEEE, MMMM d, yyyy h:mm a",
            "MMMM d, yyyy 'at' h:mm:ss a",
            "MMMM d, yyyy h:mm:ss a",
            "MMMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy h:mm a",
            "MMMM d, yyyy"
        ]
        for format in formats {
            let formatter = CachedFormatters.dateFormatter(format, locale: "en_US_POSIX", calendar: calendar)
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseDay(_ value: String, calendar: Calendar) -> Date? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let yearRange = Range(match.range(at: 1), in: value),
              let monthRange = Range(match.range(at: 2), in: value),
              let dayRange = Range(match.range(at: 3), in: value),
              let year = Int(value[yearRange]),
              let month = Int(value[monthRange]),
              let day = Int(value[dayRange])
        else {
            return nil
        }
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts)
    }
}

/// Date formatters are slow to create, and the note list formats every row on each update.
private enum CachedFormatters {
    static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let lock = NSLock()
    private static var dateFormatters: [String: DateFormatter] = [:]

    static func dateFormatter(_ format: String, locale: String, calendar: Calendar) -> DateFormatter {
        let key = "\(format)|\(locale)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = dateFormatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: locale)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        dateFormatters[key] = formatter
        return formatter
    }
}
