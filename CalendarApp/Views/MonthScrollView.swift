import SwiftUI

struct MonthScrollView: View {
    @Bindable var viewModel: CalendarViewModel
    @Binding var selectedDay: CalendarDay?
    @Binding var isDrawerPresented: Bool
    let onRequestAccess: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                        HeaderView(
                            year: viewModel.visibleYear,
                            onSearch: {},
                            onMenu: { isDrawerPresented = true }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        ForEach(viewModel.months) { month in
                            MonthSectionView(
                                month: month,
                                eventsForDay: { viewModel.events(on: $0) },
                                colorForEvent: { viewModel.color(for: $0) },
                                onSelectDay: { selectedDay = $0 }
                            )
                            .id(month.id)
                            .padding(.horizontal, 12)
                            .onAppear {
                                viewModel.updateVisibleYear(for: month)
                            }
                        }

                        Color.clear.frame(height: 110)
                    }
                }
                .scrollIndicators(.hidden)

                if !viewModel.hasConnectedCalendars {
                    EmptyCalendarStateView(
                        accessState: viewModel.accessState,
                        statusMessage: viewModel.statusMessage,
                        isLoading: viewModel.loadState == .loading,
                        onRequestAccess: onRequestAccess
                    )
                        .padding(.horizontal, 24)
                }
            }
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

private struct EmptyCalendarStateView: View {
    let accessState: EventKitService.AccessState
    let statusMessage: String
    let isLoading: Bool
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No calendars connected")
                .font(.headline)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if accessState == .notDetermined {
                Button(action: onRequestAccess) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Allow Calendar Access")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Google sync and calendar appearance settings are still not implemented.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: 420)
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
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 10) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Search")

                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Calendars and settings")
            }
            .font(.body.weight(.semibold))
        }
        .padding(.vertical, 6)
    }
}

private struct MonthSectionView: View {
    let month: CalendarMonth
    let eventsForDay: (Date) -> [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectDay: (CalendarDay) -> Void

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthFormatter.string(from: month.date))
                .font(.largeTitle.bold())
                .padding(.horizontal, 4)

            WeekdayHeaderView()

            VStack(spacing: 0) {
                ForEach(Array(month.weeks.enumerated()), id: \.offset) { index, week in
                    WeekRowView(
                        week: week,
                        eventsForDay: eventsForDay,
                        colorForEvent: colorForEvent,
                        onSelectDay: onSelectDay
                    )

                    if index < month.weeks.count - 1 {
                        Rectangle()
                            .fill(CalendarTheme.separator)
                            .frame(height: 0.5)
                    }
                }
            }
            .overlay {
                Rectangle()
                    .stroke(CalendarTheme.separator, lineWidth: 0.5)
            }
        }
    }
}

private struct WeekdayHeaderView: View {
    private let symbols = Calendar.current.shortStandaloneWeekdaySymbols

    var body: some View {
        HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct WeekRowView: View {
    let week: [CalendarDay]
    let eventsForDay: (Date) -> [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectDay: (CalendarDay) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                DayCellView(
                    day: day,
                    events: Array(eventsForDay(day.date).prefix(3)),
                    colorForEvent: colorForEvent,
                    onTap: { onSelectDay(day) }
                )

                if index < week.count - 1 {
                    Rectangle()
                        .fill(CalendarTheme.separator)
                        .frame(width: 0.5)
                }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(String(Calendar.current.component(.day, from: day.date)))
                    .font(.system(size: 21, weight: isToday ? .semibold : .regular))
                    .frame(width: 28, height: 28, alignment: .center)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }
                    .foregroundStyle(isToday ? AnyShapeStyle(.white) : (day.isInDisplayedMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.secondary.opacity(0.55))))

                ForEach(events) { event in
                    EventBarView(event: event, colorHex: colorForEvent(event))
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 5)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
            .background(day.isInDisplayedMonth ? CalendarTheme.background : CalendarTheme.secondaryBackground.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

private struct EventBarView: View {
    let event: CalendarEvent
    let colorHex: String

    private var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Rectangle()
                .fill(color)
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))

            Text(event.title)
                .lineLimit(1)
                .foregroundStyle(color)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
