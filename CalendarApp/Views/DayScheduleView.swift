import SwiftUI

struct DayScheduleView: View {
    let date: Date
    let events: [CalendarEvent]
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let hourHeight: CGFloat = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                allDayEvents

                ScrollView {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            hourGrid
                            eventBlocks(availableWidth: max(0, geometry.size.width - 58))
                            currentTimeIndicator
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
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
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var allDayEvents: some View {
        let allDay = events.filter(\.isAllDay)

        return VStack(alignment: .leading, spacing: 6) {
            if !allDay.isEmpty {
                ForEach(allDay) { event in
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, allDay.isEmpty ? 0 : 10)
        .background(.thinMaterial)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 10) {
                    Text(hour.formatted(.number.precision(.integerLength(2))) + ":00")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 0.6)
                        .padding(.top, 7)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func eventBlocks(availableWidth: CGFloat) -> some View {
        let timed = layout(events: events.filter { !$0.isAllDay }, availableWidth: availableWidth)

        return ForEach(timed) { item in
            DayEventBlock(event: item.event)
                .frame(width: item.width, height: item.height)
                .offset(x: 58 + item.x, y: item.y)
        }
    }

    @ViewBuilder
    private var currentTimeIndicator: some View {
        if Calendar.current.isDateInToday(date) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            let y = minutes / 60 * hourHeight

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
                y: startMinutes / 60 * hourHeight,
                width: width,
                height: max(32, (endMinutes - startMinutes) / 60 * hourHeight)
            )
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .font(.caption.weight(.bold))
                .lineLimit(2)

            Text(event.startDate.formatted(.dateTime.hour().minute()))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
        }
    }
}
