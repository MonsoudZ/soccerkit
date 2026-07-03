import SwiftUI

// MARK: - Unified calendar item

/// A single kind of thing that can appear on the coach's calendar. This unifies
/// training sessions, games, and general team events (tournaments, socials, ...)
/// into one colour-coded vocabulary for the calendar UI.
enum CalendarEventKind: Hashable {
    case practice
    case game
    case tournament
    case scrimmage
    case social
    case meeting
    case other

    init(_ eventKind: TeamEventKind) {
        switch eventKind {
        case .tournament: self = .tournament
        case .scrimmage: self = .scrimmage
        case .social: self = .social
        case .meeting: self = .meeting
        case .other: self = .other
        }
    }

    var label: String {
        switch self {
        case .practice: return "Practice"
        case .game: return "Game"
        case .tournament: return "Tournament"
        case .scrimmage: return "Scrimmage"
        case .social: return "Team Event"
        case .meeting: return "Meeting"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .practice: return "figure.run"
        case .game: return "soccerball"
        case .tournament: return "trophy"
        case .scrimmage: return "sportscourt"
        case .social: return "party.popper"
        case .meeting: return "person.2.wave.2"
        case .other: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .practice: return .teal
        case .game: return .blue
        case .tournament: return .orange
        case .scrimmage: return .green
        case .social: return .pink
        case .meeting: return .indigo
        case .other: return .gray
        }
    }
}

/// A read-only projection of a session/game/event used purely for rendering the
/// calendar. The `reference` lets the agenda navigate to the real detail screen.
struct CalendarItem: Identifiable {
    enum Reference: Hashable {
        case session(UUID)
        case game(UUID)
        case event(UUID)
    }

    let id: UUID
    let date: Date
    let endDate: Date?
    let title: String
    let subtitle: String
    let location: String
    let kind: CalendarEventKind
    let reference: Reference

    var isMultiDay: Bool {
        guard let endDate else { return false }
        return Calendar.current.startOfDay(for: endDate) > Calendar.current.startOfDay(for: date)
    }

    /// True when `day` falls on or between the item's start and end day.
    func covers(_ day: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate ?? date)
        return target >= start && target <= end
    }
}

extension AppStore {
    /// Every schedule item for the selected team, sorted by start time.
    var calendarItems: [CalendarItem] {
        let practices = teamSessions.map { session in
            CalendarItem(
                id: session.id,
                date: session.date,
                endDate: nil,
                title: session.title,
                subtitle: "Practice",
                location: "",
                kind: .practice,
                reference: .session(session.id)
            )
        }

        let matches = teamGames.map { game in
            CalendarItem(
                id: game.id,
                date: game.date,
                endDate: nil,
                title: "vs \(game.opponent)",
                subtitle: game.isHome ? "Home Game" : "Away Game",
                location: game.location,
                kind: .game,
                reference: .game(game.id)
            )
        }

        let others = teamEvents.map { event in
            CalendarItem(
                id: event.id,
                date: event.date,
                endDate: event.endDate,
                title: event.title,
                subtitle: event.kind.rawValue,
                location: event.location,
                kind: CalendarEventKind(event.kind),
                reference: .event(event.id)
            )
        }

        return (practices + matches + others).sorted { $0.date < $1.date }
    }
}

// MARK: - Calendar view

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var activeSheet: CalendarSheet?

    private let calendar = Calendar.current

    private enum CalendarSheet: Identifiable {
        case newPractice(Date)
        case newGame(Date)
        case newEvent(Date)

        var id: String {
            switch self {
            case .newPractice: return "practice"
            case .newGame: return "game"
            case .newEvent: return "event"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                monthGrid
                Divider()
                agenda
                legend
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem {
                Button {
                    displayedMonth = Date()
                    selectedDate = Date()
                } label: {
                    Text("Today")
                }
            }

            ToolbarItem {
                Menu {
                    Button {
                        activeSheet = .newPractice(selectedDate)
                    } label: {
                        Label("New Practice", systemImage: CalendarEventKind.practice.symbol)
                    }
                    Button {
                        activeSheet = .newGame(selectedDate)
                    } label: {
                        Label("New Game", systemImage: CalendarEventKind.game.symbol)
                    }
                    Button {
                        activeSheet = .newEvent(selectedDate)
                    } label: {
                        Label("New Tournament / Event", systemImage: CalendarEventKind.tournament.symbol)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .newPractice(let date):
                    SessionFormView(initialDate: startOfHour(date))
                case .newGame(let date):
                    GameFormView(initialDate: startOfHour(date))
                case .newEvent(let date):
                    EventFormView(initialDate: startOfHour(date))
                }
            }
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDays, id: \.self) { day in
                DayCell(
                    day: day,
                    isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(day),
                    kinds: kinds(on: day)
                )
                .onTapGesture {
                    selectedDate = day
                }
            }
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.headline)

            let items = itemsForSelectedDay
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Nothing scheduled. Use + to add practice, a game, or a tournament.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        AgendaRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let kinds: [CalendarEventKind] = [.practice, .game, .tournament, .scrimmage, .social, .meeting]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(kind.color)
                            .frame(width: 8, height: 8)
                        Text(kind.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func destination(for item: CalendarItem) -> some View {
        switch item.reference {
        case .session(let id):
            SessionDetailView(sessionID: id)
        case .game(let id):
            GameDetailView(gameID: id)
        case .event(let id):
            EventDetailView(eventID: id)
        }
    }

    // MARK: Data helpers

    private var itemsForSelectedDay: [CalendarItem] {
        store.calendarItems
            .filter { $0.covers(selectedDate, calendar: calendar) }
            .sorted { $0.date < $1.date }
    }

    private func kinds(on day: Date) -> [CalendarEventKind] {
        var seen: [CalendarEventKind] = []
        for item in store.calendarItems where item.covers(day, calendar: calendar) {
            if !seen.contains(item.kind) {
                seen.append(item.kind)
            }
        }
        return seen
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        guard shift > 0, shift < symbols.count else { return symbols }
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// A fixed six-week grid whose first cell is the start of the week containing
    /// the first of the displayed month. This always fully covers the month.
    private var gridDays: [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    /// Keeps the tapped day but snaps to a sensible default start time.
    private func startOfHour(_ day: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 17
        components.minute = 0
        return calendar.date(from: components) ?? day
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let isInDisplayedMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let kinds: [CalendarEventKind]

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber)
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.15) : .clear))
                )

            HStack(spacing: 3) {
                ForEach(Array(kinds.prefix(3).enumerated()), id: \.offset) { _, kind in
                    Circle()
                        .fill(kind.color)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(isInDisplayedMonth ? 1 : 0.3)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }
}

// MARK: - Agenda row

private struct AgendaRow: View {
    let item: CalendarItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.kind.color)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: item.kind.symbol)
                        .font(.caption)
                        .foregroundStyle(item.kind.color)
                    Text(item.title)
                        .font(.headline)
                }

                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !item.location.isEmpty {
                    Label(item.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(item.subtitle)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(item.kind.color.opacity(0.16))
                .foregroundStyle(item.kind.color)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var timeText: String {
        if item.isMultiDay, let endDate = item.endDate {
            let start = item.date.formatted(date: .abbreviated, time: .omitted)
            let end = endDate.formatted(date: .abbreviated, time: .omitted)
            return "\(start) – \(end)"
        }
        return item.date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Event form

struct EventFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let event: TeamEvent?
    @State private var title: String
    @State private var kind: TeamEventKind
    @State private var date: Date
    @State private var isMultiDay: Bool
    @State private var endDate: Date
    @State private var location: String
    @State private var notes: String

    init(event: TeamEvent? = nil, initialDate: Date? = nil) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _kind = State(initialValue: event?.kind ?? .tournament)
        let start = event?.date ?? initialDate ?? Date()
        _date = State(initialValue: start)
        _isMultiDay = State(initialValue: event?.endDate != nil)
        _endDate = State(initialValue: event?.endDate ?? start)
        _location = State(initialValue: event?.location ?? "")
        _notes = State(initialValue: event?.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) {
                    ForEach(TeamEventKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                DatePicker("Starts", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Toggle("Multi-day event", isOn: $isMultiDay)
                if isMultiDay {
                    DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: [.date])
                }
                TextField("Location", text: $location)
                LabeledContent("Team", value: store.selectedTeam.name)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(event == nil ? "New Event" : "Edit Event")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEnd: Date? = isMultiDay ? max(endDate, date) : nil

        if let event {
            var updated = event
            updated.title = cleanTitle
            updated.kind = kind
            updated.date = date
            updated.endDate = resolvedEnd
            updated.location = cleanLocation
            updated.notes = cleanNotes
            store.updateEvent(updated)
        } else {
            store.addEvent(
                title: cleanTitle,
                kind: kind,
                date: date,
                endDate: resolvedEnd,
                location: cleanLocation,
                notes: cleanNotes
            )
        }
    }
}

// MARK: - Event detail

struct EventDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID
    @State private var showingEditEvent = false

    private var event: TeamEvent? {
        store.events.first { $0.id == eventID }
    }

    var body: some View {
        Group {
            if let event {
                List {
                    Section("Event") {
                        LabeledContent("Title", value: event.title)
                        LabeledContent("Type", value: event.kind.rawValue)
                        LabeledContent("Team", value: store.teamName(for: event.teamID))
                        if event.isMultiDay, let endDate = event.endDate {
                            LabeledContent("Starts", value: event.date.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Ends", value: endDate.formatted(date: .abbreviated, time: .omitted))
                        } else {
                            LabeledContent("Date", value: event.date.formatted(date: .abbreviated, time: .omitted))
                            LabeledContent("Time", value: event.date.formatted(date: .omitted, time: .shortened))
                        }
                        if !event.location.isEmpty {
                            LabeledContent("Location", value: event.location)
                        }
                    }

                    if !event.notes.isEmpty {
                        Section("Notes") {
                            Text(event.notes)
                        }
                    }

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: event.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: event)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(event.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }
                }
            } else {
                EmptyStateView(title: "Event Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(event?.title ?? "Event")
        .toolbar {
            if let event {
                Button {
                    showingEditEvent = true
                } label: {
                    Label("Edit Event", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deleteEvent(event)
                    dismiss()
                } label: {
                    Label("Delete Event", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditEvent) {
            if let event {
                NavigationStack {
                    EventFormView(event: event)
                }
            }
        }
    }
}
