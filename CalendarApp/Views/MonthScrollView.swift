import SwiftUI

struct MonthScrollView: View {
    @Bindable var viewModel: CalendarViewModel
    @Binding var selectedDay: CalendarDay?
    @Binding var isDrawerPresented: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                    HeaderView(
                        year: viewModel.visibleYear,
                        onSearch: {},
                        onMenu: { isDrawerPresented = true }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    ForEach(viewModel.months) { month in
                        MonthSectionView(
                            month: month,
                            eventsForDay: { viewModel.events(on: $0) },
                            colorForEvent: { viewModel.color(for: $0) },
                            onSelectDay: { selectedDay = $0 }
                        )
                        .id(month.id)
                        .padding(.horizontal, 16)
                        .onAppear {
                            viewModel.updateVisibleYear(for: month)
                        }
                    }

                    Color.clear.frame(height: 96)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.scrollToTodayTrigger) { _, _ in
                let todayMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start
                guard let todayMonth else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(todayMonth, anchor: .top)
                }
            }
        }
    }
}

private struct HeaderView: View {
    let year: Int
    let onSearch: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack {
            Text(String(year))
                .font(.headline.weight(.semibold))
                .glassCapsule()

            Spacer()

            HStack(spacing: 10) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")

                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Calendars and settings")
            }
            .font(.headline)
            .glassCapsule()
        }
    }
}

private struct MonthSectionView: View {
    let month: CalendarMonth
    let eventsForDay: (Date) -> [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectDay: (CalendarDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthFormatter.string(from: month.date))
                .font(.largeTitle.bold())
                .padding(.leading, 2)

            WeekdayHeaderView()

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(month.weeks.flatMap(\.self)) { day in
                    DayCellView(
                        day: day,
                        events: Array(eventsForDay(day.date).prefix(3)),
                        colorForEvent: colorForEvent,
                        onTap: { onSelectDay(day) }
                    )
                }
            }
        }
    }
}

private struct WeekdayHeaderView: View {
    private let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    var body: some View {
        HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DayCellView: View {
    let day: CalendarDay
    let events: [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onTap: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(Calendar.current.component(.day, from: day.date)))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(day.isInDisplayedMonth ? .primary : .secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            if isToday {
                                Circle().fill(Color.accentColor)
                            }
                        }
                        .foregroundStyle(isToday ? .white : (day.isInDisplayedMonth ? .primary : .secondary))

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events) { event in
                        EventPillView(event: event, colorHex: colorForEvent(event))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(minHeight: 86, maxHeight: 96, alignment: .topLeading)
            .background(CalendarTheme.cellBackground.opacity(day.isInDisplayedMonth ? 0.72 : 0.34), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct EventPillView: View {
    let event: CalendarEvent
    let colorHex: String

    private var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(event.title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.18), in: Capsule())
    }
}
