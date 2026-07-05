import Foundation

/// Which "add" sheet the calendar is presenting, carrying the day it should seed.
enum CalendarSheet: Identifiable {
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

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var displayedMonth = Date()
    @Published var selectedDate = Date()
    @Published var activeSheet: CalendarSheet?
    @Published var enabledKinds: Set<CalendarEventKind> = Set(CalendarEventKind.allCases)

    let calendar = Calendar.current

    /// Kinds shown in the filter row, in a stable display order.
    let filterableKinds: [CalendarEventKind] = CalendarEventKind.allCases

    // MARK: Filtering

    var isFiltering: Bool {
        enabledKinds.count != CalendarEventKind.allCases.count
    }

    func isEnabled(_ kind: CalendarEventKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func toggle(_ kind: CalendarEventKind) {
        if enabledKinds.contains(kind) {
            enabledKinds.remove(kind)
        } else {
            enabledKinds.insert(kind)
        }
    }

    func enableAllKinds() {
        enabledKinds = Set(CalendarEventKind.allCases)
    }

    // MARK: Navigation

    func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }

    func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    func select(_ day: Date) {
        selectedDate = day
    }

    // MARK: Add sheets

    func presentNewPractice() { activeSheet = .newPractice(selectedDate) }
    func presentNewGame() { activeSheet = .newGame(selectedDate) }
    func presentNewEvent() { activeSheet = .newEvent(selectedDate) }

    // MARK: Grid

    var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        guard shift > 0, shift < symbols.count else { return symbols }
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// A fixed six-week grid whose first cell is the start of the week containing
    /// the first of the displayed month. This always fully covers the month.
    var gridDays: [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDate)
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    // MARK: Items

    func itemsForSelectedDay(in store: AppStore) -> [CalendarItem] {
        store.calendarItems
            .filter { enabledKinds.contains($0.kind) && $0.covers(selectedDate, calendar: calendar) }
            .sorted { $0.date < $1.date }
    }

    func kinds(on day: Date, in store: AppStore) -> [CalendarEventKind] {
        var seen: [CalendarEventKind] = []
        for item in store.calendarItems where enabledKinds.contains(item.kind) && item.covers(day, calendar: calendar) {
            if !seen.contains(item.kind) {
                seen.append(item.kind)
            }
        }
        return seen
    }

    /// Keeps the tapped day but snaps to a sensible default start time.
    func startOfHour(_ day: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 17
        components.minute = 0
        return calendar.date(from: components) ?? day
    }
}
