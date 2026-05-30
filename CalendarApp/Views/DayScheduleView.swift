import SwiftUI

struct DayScheduleView: View {
    let date: Date
    let events: [CalendarEvent]
    let isMosaicModeEnabled: Bool
    let colorForEvent: (CalendarEvent) -> String
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onCreateEvent: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    private let hourHeight: CGFloat = 60
    private let timelineLeadingOffset: CGFloat = 58
    private let hourLineTopOffset: CGFloat = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                allDayEvents

                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geometry in
                            ZStack(alignment: .topLeading) {
                                hourGrid
                                hourTapTargets(availableWidth: max(0, geometry.size.width - 58))
                                eventBlocks(availableWidth: max(0, geometry.size.width - 58))
                                currentTimeIndicator
                                initialScrollAnchor
                            }
                        }
                        .frame(height: timelineHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .id("timeline")
                    }
                    .onAppear {
                        scrollToInitialPosition(with: proxy)
                    }
                    .onChange(of: date) { _, _ in
                        scrollToInitialPosition(with: proxy)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 35)
                        .onEnded { value in
                            if value.translation.width > 70 {
                                onPreviousDay()
                            } else if value.translation.width < -70 {
                                onNextDay()
                            }
                        }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCreateEvent(date)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .glassCircle(size: 38)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .principal) {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(language.locale)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .glassCapsule(horizontal: 14, vertical: 8)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L.tr("Close", language: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .glassCapsule(horizontal: 14, vertical: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var allDayEvents: some View {
        let allDay = events.filter(\.isAllDay)

        return VStack(alignment: .leading, spacing: 6) {
            if !allDay.isEmpty {
                ForEach(allDay) { event in
                    Button {
                        onSelectEvent(event)
                    } label: {
                        HStack(spacing: 6) {
                            if event.kind == .reminder {
                                Image(systemName: "checkmark.circle")
                            }

                            Text(displayTitle(for: event))
                                .font(.caption.weight(.semibold))
                                .strikethrough(event.isCompleted, color: backgroundColor(for: event))
                        }
                        .foregroundStyle(backgroundColor(for: event))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundColor(for: event).opacity(0.18), in: Capsule())
                        .opacity(event.isCompleted ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, allDay.isEmpty ? 0 : 10)
        .background(.thinMaterial)
    }

    private func backgroundColor(for event: CalendarEvent) -> Color {
        if event.kind == .reminder {
            return .orange
        }

        return Color(hex: colorForEvent(event)) ?? .accentColor
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                let isNoon = hour == 12

                HStack(alignment: .top, spacing: 10) {
                    Text(hour.formatted(.number.precision(.integerLength(2))) + ":00")
                        .font(.caption2.monospacedDigit().weight(isNoon ? .semibold : .regular))
                        .foregroundStyle(isNoon ? .primary : .secondary)
                        .frame(width: 44, alignment: .trailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(isNoon ? 0.42 : 0.18))
                        .frame(height: isNoon ? 0.9 : 0.6)
                        .padding(.top, hourLineTopOffset)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func hourTapTargets(availableWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Button {
                    onCreateEvent(date(atHour: hour))
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: availableWidth, height: hourHeight)
                .accessibilityLabel(newEventAccessibilityLabel(for: hour))
            }
        }
        .offset(x: timelineLeadingOffset)
    }

    private func eventBlocks(availableWidth: CGFloat) -> some View {
        let timed = layout(events: events.filter { !$0.isAllDay }, availableWidth: availableWidth)

        return ForEach(timed) { item in
            DayEventBlock(
                event: item.event,
                color: backgroundColor(for: item.event),
                displayTitle: displayTitle(for: item.event),
                onTap: { onSelectEvent(item.event) }
            )
                .frame(width: item.width, height: item.height)
                .offset(x: timelineLeadingOffset + item.x, y: item.y)
        }
    }

    @ViewBuilder
    private var currentTimeIndicator: some View {
        if Calendar.current.isDateInToday(date) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            let y = yOffset(forMinutes: minutes)

            HStack(spacing: 6) {
                Text(Date().formatted(.dateTime.hour().minute()))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)

                Rectangle()
                    .fill(.red)
                    .frame(height: 1.5)
            }
            .offset(x: 2, y: y)
        }
    }

    private func layout(events: [CalendarEvent], availableWidth: CGFloat) -> [PositionedEvent] {
        let sorted = events.sorted { $0.startDate < $1.startDate }

        return sorted.enumerated().map { index, event in
            let start = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
            let end = Calendar.current.dateComponents([.hour, .minute], from: event.endDate)
            let startMinutes = CGFloat((start.hour ?? 0) * 60 + (start.minute ?? 0))
            let endMinutes = CGFloat((end.hour ?? 0) * 60 + (end.minute ?? 0))
            let overlapsPrevious = index > 0 && sorted[index - 1].endDate > event.startDate
            let width = overlapsPrevious ? availableWidth / 2 - 4 : availableWidth
            let x = overlapsPrevious ? availableWidth / 2 + 4 : 0

            return PositionedEvent(
                event: event,
                x: x,
                y: yOffset(forMinutes: startMinutes),
                width: width,
                height: max(32, (endMinutes - startMinutes) / 60 * hourHeight)
            )
        }
    }

    private var initialScrollAnchor: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: initialScrollY)

            Color.clear
                .frame(width: 1, height: 1)
                .id(initialScrollAnchorID)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func scrollToInitialPosition(with proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(initialScrollAnchorID, anchor: .top)
            }
        }
    }

    private var initialScrollY: CGFloat {
        if let firstTimedEvent {
            return yOffset(for: firstTimedEvent.startDate)
        }

        if Calendar.current.isDateInToday(date) {
            return yOffset(for: Date())
        }

        return yOffset(forMinutes: 8 * 60)
    }

    private var firstTimedEvent: CalendarEvent? {
        events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private var initialScrollAnchorID: String {
        "initial-scroll-anchor"
    }

    private func yOffset(for date: Date) -> CGFloat {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return yOffset(forMinutes: minutes)
    }

    private func yOffset(forMinutes minutes: CGFloat) -> CGFloat {
        max(0, min(hourLineTopOffset + minutes / 60 * hourHeight, timelineHeight))
    }

    private var timelineHeight: CGFloat {
        hourLineTopOffset + hourHeight * 24
    }

    private func date(atHour hour: Int) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
    }

    private func newEventAccessibilityLabel(for hour: Int) -> String {
        let startDate = date(atHour: hour)
        return L.tr(
            "New Event at %@",
            language: language,
            startDate.formatted(.dateTime.hour().locale(language.locale))
        )
    }

    private func displayTitle(for event: CalendarEvent) -> String {
        isMosaicModeEnabled ? EventTitleMosaic.title(for: event, language: language) : event.title
    }
}

private struct PositionedEvent: Identifiable {
    let event: CalendarEvent
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var id: String { event.id }
}

private struct DayEventBlock: View {
    let event: CalendarEvent
    let color: Color
    let displayTitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if event.kind == .reminder {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                    }

                    Text(displayTitle)
                        .font(.caption.weight(.bold))
                        .lineLimit(nil)
                        .strikethrough(event.isCompleted, color: .primary)
                }

                Text(event.startDate.formatted(.dateTime.hour().minute()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
            .opacity(event.isCompleted ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }
}
