import EventKit
import Foundation

@MainActor
final class EventKitService {
    enum AccessState: Equatable {
        case unknown
        case notDetermined
        case granted
        case denied
        case restricted
        case writeOnly
    }

    private let eventStore = EKEventStore()

    func currentAccessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestAccess() async throws -> AccessState {
        _ = try await eventStore.requestFullAccessToEvents()
        return currentAccessState()
    }

    func fetchCalendars() -> [CalendarSource] {
        eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { calendar in
                CalendarSource(
                    id: calendar.calendarIdentifier,
                    provider: .iCloud,
                    title: calendar.title,
                    colorHex: calendar.cgColor.hexRGB ?? "007AFF",
                    colorOverrideHex: nil,
                    isVisible: true,
                    isWritable: calendar.allowsContentModifications
                )
            }
    }

    func fetchEvents(in interval: DateInterval, calendars: [CalendarSource]) -> [CalendarEvent] {
        let ids = Set(calendars.map(\.id))
        let selectedCalendars = eventStore.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selectedCalendars)

        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    calendarID: event.calendar.calendarIdentifier,
                    title: event.title?.isEmpty == false ? event.title : "Untitled",
                    location: event.location,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
    }
}

private extension CGColor {
    var hexRGB: String? {
        guard let converted = converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }

        let red = Int(round(components[0] * 255))
        let green = Int(round(components[1] * 255))
        let blue = Int(round(components[2] * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
