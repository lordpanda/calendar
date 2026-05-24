import SwiftUI

struct MonthScrollView: View {
    @Bindable var viewModel: CalendarViewModel
    @Binding var selectedDay: CalendarDay?
    @Binding var isDrawerPresented: Bool
    let onCreateEvent: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void
    @State private var isSearchPresented = false
    @State private var isYearOverviewPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            if isYearOverviewPresented {
                YearOverviewView(
                    year: viewModel.visibleYear,
                    calendar: viewModel.displayCalendar,
                    selectedMonth: viewModel.selectedMonthID,
                    onSelectMonth: { month in
                        viewModel.jumpToMonth(containing: month)
                        isYearOverviewPresented = false
                    }
                )
            } else {
                TabView(selection: Binding(
                    get: { viewModel.selectedMonthID },
                    set: { viewModel.selectMonth($0) }
                )) {
                    ForEach(viewModel.months) { month in
                        MonthSectionView(
                            month: month,
                            calendar: viewModel.displayCalendar,
                            showsWeekNumbers: viewModel.settings.showsWeekNumbers,
                            contentScale: viewModel.settings.monthContentScale.factor,
                            eventsForDay: { viewModel.events(on: $0) },
                            colorForEvent: { viewModel.color(for: $0) },
                            onSelectDay: { day in
                                if viewModel.events(on: day.date).isEmpty {
                                    onCreateEvent(day.date)
                                } else {
                                    selectedDay = day
                                }
                            },
                            onSelectEvent: onSelectEvent
                        )
                        .tag(month.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            HeaderView(
                year: viewModel.visibleYear,
                monthTitle: viewModel.currentMonthTitle,
                contentScale: viewModel.settings.monthContentScale.factor,
                onShowYearOverview: { isYearOverviewPresented.toggle() },
                onSearch: { isSearchPresented = true },
                onMenu: { isDrawerPresented = true }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .zIndex(1)
        }
        .onChange(of: viewModel.scrollToTodayTrigger) { _, _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isYearOverviewPresented = false
                viewModel.scrollToTodayMonth()
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            EventSearchView(
                events: viewModel.events,
                colorForEvent: { viewModel.color(for: $0) },
                onSelectEvent: { event in
                    isSearchPresented = false
                    onSelectEvent(event)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct HeaderView: View {
    let year: Int
    let monthTitle: String
    let contentScale: CGFloat
    let onShowYearOverview: () -> Void
    let onSearch: () -> Void
    let onMenu: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onShowYearOverview) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text(String(year))
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassCapsule(horizontal: 12, vertical: 10)
            .contentShape(Capsule())

            Spacer()

            Text(monthTitle)
                .font(.system(size: 17 * contentScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            HStack(spacing: 20) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .regular))
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(L.tr("Search", language: language))

                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .regular))
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(L.tr("Calendars and settings", language: language))
            }
            .foregroundStyle(.primary)
            .frame(height: 44)
            .glassCapsule(horizontal: 8, vertical: 0)
        }
    }
}

private struct YearOverviewView: View {
    let year: Int
    let calendar: Calendar
    let selectedMonth: Date
    let onSelectMonth: (Date) -> Void

    init(
        year: Int,
        calendar: Calendar,
        selectedMonth: Date,
        onSelectMonth: @escaping (Date) -> Void
    ) {
        self.year = year
        self.calendar = calendar
        self.selectedMonth = selectedMonth
        self.onSelectMonth = onSelectMonth
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 38) {
                    ForEach(years, id: \.self) { year in
                        YearOverviewSection(
                            year: year,
                            calendar: calendar,
                            selectedMonth: selectedMonth,
                            onSelectMonth: onSelectMonth
                        )
                        .id(year)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 92)
                .padding(.bottom, 120)
            }
            .background(CalendarTheme.background.ignoresSafeArea())
            .onAppear {
                proxy.scrollTo(year, anchor: .top)
            }
            .onChange(of: year) { _, newYear in
                proxy.scrollTo(newYear, anchor: .top)
            }
        }
    }

    private var years: [Int] {
        Array((year - 20)...(year + 20))
    }
}

private struct YearOverviewSection: View {
    let year: Int
    let calendar: Calendar
    let selectedMonth: Date
    let onSelectMonth: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Rectangle()
                .fill(Color(.separator).opacity(0.35))
                .frame(height: 1)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 34) {
                ForEach(monthStarts, id: \.self) { month in
                    MiniMonthView(
                        month: month,
                        calendar: calendar,
                        isSelectedMonth: calendar.isDate(month, equalTo: selectedMonth, toGranularity: .month),
                        onSelect: { onSelectMonth(month) }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(String(year))
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Self.accent)

            Spacer()
        }
    }

    private var monthStarts: [Date] {
        (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    private static let accent = Color(hex: "00C8B3") ?? .mint
}

private struct MiniMonthView: View {
    let month: Date
    let calendar: Calendar
    let isSelectedMonth: Bool
    let onSelect: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                Text(monthTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isSelectedMonth ? Self.accent : .primary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7), spacing: 5) {
                    ForEach(days, id: \.self) { day in
                        if let day {
                            let isToday = calendar.isDateInToday(day)
                            Text(String(calendar.component(.day, from: day)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isToday ? .white : .primary)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 15)
                                .background {
                                    if isToday {
                                        Circle().fill(Self.accent)
                                            .frame(width: 16, height: 16)
                                    }
                                }
                        } else {
                            Color.clear.frame(height: 15)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        month.formatted(.dateTime.month(.abbreviated).locale(language.locale))
    }

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day else {
            return []
        }

        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    private static let accent = Color(hex: "00C8B3") ?? .mint
}

private struct EventSearchView: View {
    let events: [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectEvent: (CalendarEvent) -> Void
    @Environment(\.appLanguage) private var language
    @State private var query = ""

    private var filteredEvents: [CalendarEvent] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return events.sorted { $0.startDate < $1.startDate }
        }

        return events
            .filter { event in
                event.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || event.location?.localizedCaseInsensitiveContains(normalizedQuery) == true
                    || event.notes?.localizedCaseInsensitiveContains(normalizedQuery) == true
            }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        NavigationStack {
            List(filteredEvents) { event in
                Button(action: { onSelectEvent(event) }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(event.kind == .reminder ? .orange : (Color(hex: colorForEvent(event)) ?? .accentColor))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(nil)

                            Text(subtitle(for: event))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L.tr("Search", language: language))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        }
    }

    private func subtitle(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return event.startDate.formatted(.dateTime.month(.abbreviated).day().locale(language.locale))
        }

        return event.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.locale))
    }
}

private struct MonthSectionView: View {
    let month: CalendarMonth
    let calendar: Calendar
    let showsWeekNumbers: Bool
    let contentScale: CGFloat
    let eventsForDay: (Date) -> [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectDay: (CalendarDay) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            let headerTop = proxy.safeAreaInsets.top + 57

            VStack(alignment: .leading, spacing: 0) {
                WeekdayHeaderView(
                    calendar: calendar,
                    showsWeekNumbers: showsWeekNumbers,
                    contentScale: contentScale
                )
                .frame(height: 22 * contentScale)

                VStack(spacing: 0) {
                    ForEach(Array(month.weeks.enumerated()), id: \.offset) { index, week in
                        let isLast = index == month.weeks.count - 1

                        WeekRowView(
                            week: week,
                            weekNumber: month.weekNumbers[index],
                            showsWeekNumbers: showsWeekNumbers,
                            calendar: calendar,
                            contentScale: contentScale,
                            eventsForDay: eventsForDay,
                            colorForEvent: colorForEvent,
                            onSelectDay: onSelectDay,
                            onSelectEvent: onSelectEvent
                        )
                        .frame(minHeight: 110, maxHeight: isLast ? .infinity : 110)
                        .overlay(alignment: .top) {
                            if index == 0 {
                                Rectangle()
                                    .fill(Self.separatorColor)
                                    .frame(height: 0.25)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if !isLast {
                                Rectangle()
                                    .fill(Self.separatorColor)
                                    .frame(height: 0.25)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.top, headerTop)
        }
    }

    private static let separatorColor = Color(hex: "C6C6C8") ?? Color(.opaqueSeparator)
}

private struct WeekdayHeaderView: View {
    let calendar: Calendar
    let showsWeekNumbers: Bool
    let contentScale: CGFloat
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 0) {
            if showsWeekNumbers {
                Text(L.tr("W", language: language))
                    .font(.system(size: 11 * contentScale, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28)
            }

            ForEach(reorderedSymbols, id: \.self) { symbol in
                Text(String(symbol.prefix(1)))
                    .font(.system(size: 11 * contentScale, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var reorderedSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            let weekday = ((calendar.firstWeekday - 1 + offset) % 7) + 1
            return symbols[max(min(weekday - 1, symbols.count - 1), 0)]
        }
    }
}

private struct WeekRowView: View {
    let week: [CalendarDay]
    let weekNumber: Int
    let showsWeekNumbers: Bool
    let calendar: Calendar
    let contentScale: CGFloat
    let eventsForDay: (Date) -> [CalendarEvent]
    let colorForEvent: (CalendarEvent) -> String
    let onSelectDay: (CalendarDay) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if showsWeekNumbers {
                        Text(String(weekNumber))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    }

                    ForEach(week, id: \.id) { day in
                        DayCellView(
                            day: day,
                            calendar: calendar,
                            contentScale: contentScale,
                            onSelectDay: { onSelectDay(day) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ForEach(visibleEventSegments) { segment in
                    let width = segmentWidth(segment, totalWidth: proxy.size.width)
                    Button(action: { onSelectEvent(segment.event) }) {
                        EventBarView(
                            event: segment.event,
                            colorHex: colorForEvent(segment.event),
                            leadingStyle: segment.startsInWeek ? .rounded : .square,
                            trailingStyle: segment.endsInWeek ? .rounded : .square,
                            contentScale: contentScale
                        )
                        .frame(width: width, height: eventHeight, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(
                        width: width,
                        height: eventHeight
                    )
                    .offset(
                        x: segmentX(segment, totalWidth: proxy.size.width),
                        y: eventTop + CGFloat(segment.slot) * eventStride
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var eventTop: CGFloat { 32 + (contentScale - 1) * 20 }
    private var eventHeight: CGFloat { 17 * contentScale }
    private var eventStride: CGFloat { 20 * contentScale }
    private static let eventInset: CGFloat = 2
    private static let weekNumberWidth: CGFloat = 28

    private var eventSegments: [WeekEventSegment] {
        let events = uniqueWeekEvents()
        var occupiedSlots: [[Bool]] = []
        var segments: [WeekEventSegment] = []

        for event in events {
            guard let range = dayRange(for: event) else { continue }
            let slot = firstAvailableSlot(in: occupiedSlots, range: range)
            while occupiedSlots.count <= slot {
                occupiedSlots.append(Array(repeating: false, count: week.count))
            }
            for index in range {
                occupiedSlots[slot][index] = true
            }

            segments.append(
                WeekEventSegment(
                    event: event,
                    startIndex: range.lowerBound,
                    endIndex: range.upperBound - 1,
                    slot: slot,
                    startsInWeek: calendar.isDate(event.startDate, inSameDayAs: week[range.lowerBound].date),
                    endsInWeek: eventEnds(on: week[range.upperBound - 1].date, event: event)
                )
            )
        }

        return segments
    }

    private var visibleEventSegments: [WeekEventSegment] {
        eventSegments.filter { $0.slot < visibleEventSlotCount }
    }

    private var visibleEventSlotCount: Int {
        if contentScale >= 1.5 {
            return 2
        }
        if contentScale >= 1.25 {
            return 3
        }
        return 4
    }

    private func uniqueWeekEvents() -> [CalendarEvent] {
        var seen = Set<String>()
        let events = week.flatMap { eventsForDay($0.date) }
            .filter { seen.insert("\($0.calendarID)|\($0.id)").inserted }

        return events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }

            let lhsSpan = dayRange(for: lhs)?.count ?? 0
            let rhsSpan = dayRange(for: rhs)?.count ?? 0
            if lhsSpan != rhsSpan {
                return lhsSpan > rhsSpan
            }

            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func dayRange(for event: CalendarEvent) -> Range<Int>? {
        let matchingIndices = week.indices.filter { index in
            let start = calendar.startOfDay(for: week[index].date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
            return event.intersects(DateInterval(start: start, end: end))
        }

        guard let first = matchingIndices.first, let last = matchingIndices.last else {
            return nil
        }

        return first..<(last + 1)
    }

    private func firstAvailableSlot(in occupiedSlots: [[Bool]], range: Range<Int>) -> Int {
        for (slot, occupiedDays) in occupiedSlots.enumerated() {
            if range.allSatisfy({ !occupiedDays[$0] }) {
                return slot
            }
        }
        return occupiedSlots.count
    }

    private func eventEnds(on date: Date, event: CalendarEvent) -> Bool {
        guard let eventLastInstant = calendar.date(byAdding: .second, value: -1, to: event.endDate) else {
            return false
        }
        return calendar.isDate(eventLastInstant, inSameDayAs: date)
    }

    private func segmentX(_ segment: WeekEventSegment, totalWidth: CGFloat) -> CGFloat {
        let leadingWidth = showsWeekNumbers ? Self.weekNumberWidth : 0
        let dayWidth = max((totalWidth - leadingWidth) / CGFloat(max(week.count, 1)), 0)
        let inset = segment.startsInWeek ? Self.eventInset : 0
        return leadingWidth + CGFloat(segment.startIndex) * dayWidth + inset
    }

    private func segmentWidth(_ segment: WeekEventSegment, totalWidth: CGFloat) -> CGFloat {
        let leadingWidth = showsWeekNumbers ? Self.weekNumberWidth : 0
        let dayWidth = max((totalWidth - leadingWidth) / CGFloat(max(week.count, 1)), 0)
        let leadingInset = segment.startsInWeek ? Self.eventInset : 0
        let trailingInset = segment.endsInWeek ? Self.eventInset : 0
        return max(CGFloat(segment.endIndex - segment.startIndex + 1) * dayWidth - leadingInset - trailingInset, 0)
    }
}

private struct DayCellView: View {
    let day: CalendarDay
    let calendar: Calendar
    let contentScale: CGFloat
    let onSelectDay: () -> Void

    private var isToday: Bool {
        calendar.isDateInToday(day.date)
    }

    private static let todayColor = Color(hex: "00C8B3") ?? .accentColor
    private static let separatorColor = Color(hex: "C6C6C8") ?? Color(.opaqueSeparator)

    var body: some View {
        Button(action: onSelectDay) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(calendar.component(.day, from: day.date)))
                    .font(.system(size: 13 * contentScale, weight: .medium))
                    .frame(width: 28 * contentScale, height: 28 * contentScale)
                    .background {
                        if isToday {
                            Circle().fill(Self.todayColor)
                        }
                    }
                    .foregroundStyle(
                        isToday
                            ? AnyShapeStyle(.white)
                            : day.isInDisplayedMonth
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(Color.secondary.opacity(0.45))
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CalendarTheme.background)
            .overlay {
                Rectangle().stroke(Self.separatorColor, lineWidth: 0.25)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WeekEventSegment: Identifiable {
    let event: CalendarEvent
    let startIndex: Int
    let endIndex: Int
    let slot: Int
    let startsInWeek: Bool
    let endsInWeek: Bool

    var id: String {
        "\(event.calendarID)-\(event.id)-\(startIndex)-\(endIndex)"
    }
}

private enum EventBarEdgeStyle {
    case rounded
    case square
}

private struct EventBarView: View {
    let event: CalendarEvent
    let colorHex: String
    let leadingStyle: EventBarEdgeStyle
    let trailingStyle: EventBarEdgeStyle
    let contentScale: CGFloat

    private var color: Color {
        if event.kind == .reminder {
            return .orange
        }
        return Color(hex: colorHex) ?? .accentColor
    }

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: leadingStyle == .rounded ? 4 : 0,
                bottomLeadingRadius: leadingStyle == .rounded ? 4 : 0,
                bottomTrailingRadius: trailingStyle == .rounded ? 4 : 0,
                topTrailingRadius: trailingStyle == .rounded ? 4 : 0,
                style: .continuous
            )
            .fill(color)

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if event.kind == .reminder {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10 * contentScale, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 11 * contentScale, height: eventHeight)
                    }

                    Text(event.title)
                        .font(.system(size: 11 * contentScale, weight: .medium))
                        .lineLimit(1)
                        .strikethrough(event.isCompleted, color: .white)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipped()
            }
            .padding(.horizontal, event.kind == .reminder ? 3 : 2)
            .frame(height: eventHeight)
        }
        .frame(height: eventHeight, alignment: .leading)
        .opacity(event.isCompleted ? 0.55 : 1)
        .accessibilityLabel(event.title)
    }

    private var eventHeight: CGFloat {
        17 * contentScale
    }
}
