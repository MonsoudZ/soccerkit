import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = CalendarViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                monthGrid
                filterChips
                Divider()
                agenda
            }
            .padding()
        }
        .screenBackground()
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.goToToday()
                } label: {
                    Text("Today")
                }
            }

            ToolbarItem {
                Menu {
                    Button {
                        viewModel.presentNewPractice()
                    } label: {
                        Label("New Practice", systemImage: CalendarEventKind.practice.symbol)
                    }
                    Button {
                        viewModel.presentNewGame()
                    } label: {
                        Label("New Game", systemImage: CalendarEventKind.game.symbol)
                    }
                    Button {
                        viewModel.presentNewEvent()
                    } label: {
                        Label("New Tournament / Event", systemImage: CalendarEventKind.tournament.symbol)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .newPractice(let date):
                    SessionFormView(initialDate: viewModel.startOfHour(date))
                case .newGame(let date):
                    GameFormView(initialDate: viewModel.startOfHour(date))
                case .newEvent(let date):
                    EventFormView(initialDate: viewModel.startOfHour(date))
                }
            }
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(viewModel.displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                viewModel.changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
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
            ForEach(viewModel.gridDays, id: \.self) { day in
                DayCell(
                    day: day,
                    isInDisplayedMonth: viewModel.isInDisplayedMonth(day),
                    isSelected: viewModel.isSelected(day),
                    isToday: viewModel.isToday(day),
                    kinds: viewModel.kinds(on: day, in: store)
                )
                .onTapGesture {
                    viewModel.select(day)
                }
            }
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.headline)

            let items = viewModel.itemsForSelectedDay(in: store)
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.isFiltering ? "line.3.horizontal.decrease.circle" : "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                    Text(viewModel.isFiltering
                        ? "Nothing matches the current filter on this day."
                        : "Nothing scheduled. Use + to add practice, a game, or a tournament.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .surfaceStyle()
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

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Filter by type")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isFiltering {
                    Button("Show All") {
                        viewModel.enableAllKinds()
                    }
                    .font(.caption)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(viewModel.filterableKinds, id: \.self) { kind in
                    Button {
                        viewModel.toggle(kind)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(kind.color)
                                .frame(width: 8, height: 8)
                            Text(kind.label)
                                .font(.caption)
                            Spacer(minLength: 0)
                            Image(systemName: viewModel.isEnabled(kind) ? "checkmark" : "circle")
                                .font(.caption2)
                                .foregroundStyle(viewModel.isEnabled(kind) ? Color.accentColor : Color.secondary)
                        }
                        .opacity(viewModel.isEnabled(kind) ? 1 : 0.45)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
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
        .surfaceStyle()
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
