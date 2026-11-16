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

        var buckets: [String: (label: String, notes: [NoteSummary])] = [:]
        for note in notes {
            let classified = classify(
                date: date(for: note, field: arrangement.field, calendar: calendar),
                now: now,
                calendar: calendar
            )
            var bucket = buckets[classified.key] ?? (classified.label, [])
            bucket.notes.append(note)
            buckets[classified.key] = bucket
        }

        var ordered: [Group] = []
        func add(_ key: String, _ fallback: String) {
            guard let bucket = buckets[key], !bucket.notes.isEmpty else { return }
            ordered.append(Group(
                key: key,
                label: bucket.label.isEmpty ? fallback : bucket.label,
                notes: sorted(bucket.notes, field: arrangement.field, newestFirst: newestFirst, calendar: calendar)
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

    /// The list date, such as 11/6/26.
    static func format(_ note: NoteSummary, calendar: Calendar = .current) -> String {
        guard let date = effectiveDate(note, calendar: calendar) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: date)
    }

    static func heading(_ raw: String, calendar: Calendar = .current) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Date" }
        guard let date = parse(trimmed, calendar: calendar) else { return trimmed }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
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

    private static func sorted(
        _ notes: [NoteSummary],
        field: NoteSortField,
        newestFirst: Bool,
        calendar: Calendar
    ) -> [NoteSummary] {
        notes.sorted { left, right in
            if field == .title {
                let order = titleKey(left).localizedCaseInsensitiveCompare(titleKey(right))
                if order == .orderedSame { return left.id < right.id }
                return newestFirst ? order == .orderedAscending : order == .orderedDescending
            }
            let leftDate = date(for: left, field: field, calendar: calendar)
            let rightDate = date(for: right, field: field, calendar: calendar)
            switch (leftDate, rightDate) {
            case (nil, nil):
                return left.id < right.id
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (leftDate?, rightDate?):
                if leftDate == rightDate { return left.id < right.id }
                return newestFirst ? leftDate > rightDate : leftDate < rightDate
            }
        }
    }

    private static func titleKey(_ note: NoteSummary) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private static func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in formats {
            formatter.dateFormat = format
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
