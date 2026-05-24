import Foundation
import UIKit

@Observable
@MainActor
final class CalendarViewModel {
    enum ProviderSelection: Equatable {
        case none
        case iCloud
        case google
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var visibleYear: Int
    var scrollToTodayTrigger = 0
    var selectedMonthID: Date
    var months: [CalendarMonth] = []
    var events: [CalendarEvent] = []
    var calendarSources: [CalendarSource] = []
    var accessState: EventKitService.AccessState = .notDetermined
    var loadState: LoadState = .idle
    var lastErrorMessage: String?
    var selectedProvider: ProviderSelection = .none
    var googleAuthState: GoogleCalendarService.AuthState = .signedOut
    var settings: CalendarAppSettings

    private let baseCalendar: Calendar
    private var calendar: Calendar
    private let eventKitService: EventKitService
    private let googleCalendarService: GoogleCalendarService
    private let preferencesStore: CalendarPreferencesStore
    private var observationTask: Task<Void, Never>?
    private let monthPageRadius = 12
    private var calendarPreferences: [String: CalendarPreferences]
    private var currentMonthAnchor: Date

    init(
        calendar: Calendar = .current,
        eventKitService: EventKitService = EventKitService(),
        googleCalendarService: GoogleCalendarService = GoogleCalendarService(),
        preferencesStore: CalendarPreferencesStore = CalendarPreferencesStore()
    ) {
        let storedState = preferencesStore.load()
        let configuredCalendar = Self.makeConfiguredCalendar(base: calendar, startOfWeek: storedState.settings.startOfWeek)
        let todayMonth = configuredCalendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        self.settings = storedState.settings
        self.baseCalendar = calendar
        self.calendar = configuredCalendar
        self.eventKitService = eventKitService
        self.googleCalendarService = googleCalendarService
        self.preferencesStore = preferencesStore
        self.calendarPreferences = storedState.preferences
        visibleYear = configuredCalendar.component(.year, from: todayMonth)
        selectedMonthID = todayMonth
        currentMonthAnchor = todayMonth
        months = Self.makeMonths(around: todayMonth, radius: monthPageRadius, calendar: configuredCalendar)
        accessState = eventKitService.currentAccessState()
        googleAuthState = googleCalendarService.authState
    }

    var hasConnectedCalendars: Bool {
        !calendarSources.isEmpty
    }

    var shouldShowCalendarUI: Bool {
        hasConnectedCalendars
    }

    var displayCalendar: Calendar {
        calendar
    }

    var hasWritableCalendars: Bool {
        visibleWritableCalendars.isEmpty == false
    }

    var orderedCalendarSources: [CalendarSource] {
        ordered(calendars: calendarSources)
    }

    var writableCalendars: [CalendarSource] {
        orderedCalendarSources.filter { $0.isWritable && $0.kind == .event }
    }

    var visibleWritableCalendars: [CalendarSource] {
        writableCalendars.filter(\.isVisible)
    }

    var visibleCalendarCount: Int {
        calendarSources.filter(\.isVisible).count
    }

    var iCloudCalendarCount: Int {
        calendarSources.filter { $0.provider == .iCloud }.count
    }

    var googleCalendarCount: Int {
        calendarSources.filter { $0.provider == .google }.count
    }

    var firstCalendarForNewEventsDisplayName: String {
        visibleWritableCalendars.first?.displayTitle ?? "No visible writable calendar"
    }

    var startOfWeekSummary: String {
        settings.startOfWeek.title
    }

    var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL"
        return formatter.string(from: selectedMonthID)
    }

    var lastICloudSyncDescription: String {
        Self.syncDescription(for: settings.lastICloudSyncAt)
    }

    var lastGoogleSyncDescription: String {
        Self.syncDescription(for: settings.lastGoogleSyncAt)
    }

    var canRefreshICloud: Bool {
        accessState == .granted
    }

    var canRefreshGoogle: Bool {
        googleAuthState.isSignedIn
    }

    func isCalendarWritable(_ calendarID: String) -> Bool {
        calendarSources.first(where: { $0.id == calendarID })?.isWritable == true
    }

    func editableCalendars(for event: CalendarEvent) -> [CalendarSource] {
        guard event.kind == .event else { return [] }
        let writable = visibleWritableCalendars
        guard let current = calendarSources.first(where: { $0.id == event.calendarID }) else {
            return writable
        }

        if writable.contains(current) {
            return writable
        }

        return [current] + writable
    }

    var statusMessage: String {
        switch accessState {
        case .notDetermined:
            return "Calendar access has not been requested yet."
        case .denied:
            return "Calendar access was denied. Enable access in Settings to load local calendars."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .writeOnly:
            return "Only write-only calendar access is available, so existing events cannot be read."
        case .unknown:
            return "Calendar authorization state is unknown."
        case .granted:
            if calendarSources.isEmpty {
                return "No local calendars are currently available."
            }
            return "Connected to local calendars through EventKit."
        }
    }

    func loadInitialData() async {
        accessState = eventKitService.currentAccessState()
        await googleCalendarService.restorePreviousSignInIfPossible()
        googleAuthState = googleCalendarService.authState

        if googleAuthState.isSignedIn {
            selectedProvider = .google
            await reloadGoogleCalendarsAndEvents()
        } else if accessState == .granted {
            selectedProvider = .iCloud
            await reloadCalendarsAndEvents()
            startObservingStoreChangesIfNeeded()
        }
    }

    func requestCalendarAccess() async {
        selectedProvider = .iCloud
        loadState = .loading

        do {
            accessState = try await eventKitService.requestAccess()

            if accessState == .granted {
                await reloadCalendarsAndEvents()
                startObservingStoreChangesIfNeeded()
            } else {
                calendarSources = []
                events = []
                loadState = .loaded
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }

    func selectProvider(_ provider: ProviderSelection) {
        selectedProvider = provider
    }

    func connectGoogle(presentingViewController: UIViewController) async {
        selectedProvider = .google
        loadState = .loading

        do {
            try await googleCalendarService.signIn(presentingViewController: presentingViewController)
            googleAuthState = googleCalendarService.authState
            await reloadGoogleCalendarsAndEvents()
        } catch {
            googleAuthState = googleCalendarService.authState
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }

    func disconnectGoogle() async {
        googleCalendarService.signOut()
        googleAuthState = googleCalendarService.authState

        if accessState == .granted {
            selectedProvider = .iCloud
            await reloadCalendarsAndEvents()
            startObservingStoreChangesIfNeeded()
        } else {
            selectedProvider = .none
            calendarSources = []
            events = []
            loadState = .idle
        }
    }

    func refreshICloudNow() async {
        guard accessState == .granted else { return }
        selectedProvider = .iCloud
        await reloadCalendarsAndEvents()
        startObservingStoreChangesIfNeeded()
    }

    func refreshGoogleNow() async {
        guard googleAuthState.isSignedIn else { return }
        selectedProvider = .google
        await reloadGoogleCalendarsAndEvents()
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        repeatOption: EventRepeatOption = .never,
        invitees: [String] = [],
        attachmentURL: String? = nil,
        alertOption: EventAlertOption = .none,
        visibility: EventVisibilityOption = .default,
        availability: EventAvailabilityOption = .busy
    ) async -> Bool {
        do {
            if calendarSources.first(where: { $0.id == calendarID })?.provider == .google {
                try await googleCalendarService.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    location: location,
                    notes: notes,
                    repeatOption: repeatOption,
                    invitees: invitees,
                    attachmentURL: attachmentURL,
                    alertOption: alertOption,
                    visibility: visibility,
                    availability: availability
                )
                await reloadGoogleCalendarsAndEvents()
            } else {
                try eventKitService.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    location: location,
                    notes: notes,
                    repeatOption: repeatOption,
                    invitees: invitees,
                    attachmentURL: attachmentURL,
                    alertOption: alertOption,
                    visibility: visibility,
                    availability: availability
                )
                await reloadCalendarsAndEvents()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func updateEvent(
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        repeatOption: EventRepeatOption = .never,
        invitees: [String] = [],
        attachmentURL: String? = nil,
        alertOption: EventAlertOption = .none,
        visibility: EventVisibilityOption = .default,
        availability: EventAvailabilityOption = .busy
    ) async -> Bool {
        do {
            if calendarSources.first(where: { $0.id == calendarID })?.provider == .google {
                try await googleCalendarService.updateEvent(
                    eventID: eventID,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    location: location,
                    notes: notes,
                    repeatOption: repeatOption,
                    invitees: invitees,
                    attachmentURL: attachmentURL,
                    alertOption: alertOption,
                    visibility: visibility,
                    availability: availability
                )
                await reloadGoogleCalendarsAndEvents()
            } else {
                try eventKitService.updateEvent(
                    eventID: eventID,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    location: location,
                    notes: notes,
                    repeatOption: repeatOption,
                    invitees: invitees,
                    attachmentURL: attachmentURL,
                    alertOption: alertOption,
                    visibility: visibility,
                    availability: availability
                )
                await reloadCalendarsAndEvents()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func deleteEvent(eventID: String, calendarID: String) async -> Bool {
        do {
            if calendarSources.first(where: { $0.id == calendarID })?.provider == .google {
                try await googleCalendarService.deleteEvent(eventID: eventID, calendarID: calendarID)
                await reloadGoogleCalendarsAndEvents()
            } else {
                try eventKitService.deleteEvent(eventID: eventID)
                await reloadCalendarsAndEvents()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func updateVisibleYear(for month: CalendarMonth) {
        visibleYear = calendar.component(.year, from: month.date)
    }

    func selectMonth(_ monthID: Date) {
        guard let month = months.first(where: { $0.id == monthID }) else { return }
        selectedMonthID = monthID
        updateVisibleYear(for: month)

        if monthID == months.first?.id || monthID == months.last?.id {
            shiftMonthWindow(to: monthID)
        }
    }

    func moveSelectedYear(by value: Int) {
        guard let targetMonth = calendar.date(byAdding: .year, value: value, to: selectedMonthID),
              let targetMonthStart = calendar.dateInterval(of: .month, for: targetMonth)?.start else {
            return
        }

        shiftMonthWindow(to: targetMonthStart)
    }

    func jumpToMonth(containing date: Date) {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return }
        shiftMonthWindow(to: monthStart)
    }

    func scrollToTodayMonth() {
        guard let todayMonth = calendar.dateInterval(of: .month, for: Date())?.start else { return }
        if todayMonth == currentMonthAnchor {
            selectedMonthID = todayMonth
            visibleYear = calendar.component(.year, from: todayMonth)
            return
        }

        shiftMonthWindow(to: todayMonth)
    }

    func events(on date: Date) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)

        return events
            .filter { event in
                calendarSources.first(where: { $0.id == event.calendarID })?.isVisible == true && event.intersects(interval)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func color(for event: CalendarEvent) -> String {
        calendarSources.first(where: { $0.id == event.calendarID })?.colorOverrideHex
            ?? calendarSources.first(where: { $0.id == event.calendarID })?.colorHex
            ?? "007AFF"
    }

    func setCalendarVisibility(calendarID: String, isVisible: Bool) {
        guard let index = calendarSources.firstIndex(where: { $0.id == calendarID }) else { return }
        calendarSources[index].isVisible = isVisible
        persistPreference(for: calendarSources[index])
    }

    func toggleCalendarVisibility(calendarID: String) {
        guard let index = calendarSources.firstIndex(where: { $0.id == calendarID }) else { return }
        calendarSources[index].isVisible.toggle()
        persistPreference(for: calendarSources[index])
    }

    func setCalendarColorOverride(calendarID: String, colorHex: String?) {
        guard let index = calendarSources.firstIndex(where: { $0.id == calendarID }) else { return }
        calendarSources[index].colorOverrideHex = colorHex
        persistPreference(for: calendarSources[index])
    }

    func setCalendarTitleOverride(calendarID: String, title: String?) {
        guard let index = calendarSources.firstIndex(where: { $0.id == calendarID }) else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        calendarSources[index].titleOverride = trimmed?.isEmpty == false ? trimmed : nil
        persistPreference(for: calendarSources[index])
    }

    func moveCalendar(from source: IndexSet, to destination: Int) {
        var orderedIDs = orderedCalendarSources.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        settings.calendarOrder = orderedIDs
        calendarSources = ordered(calendars: calendarSources)
        persistStoredState()
    }

    func calendarSource(id: String) -> CalendarSource? {
        calendarSources.first(where: { $0.id == id })
    }

    func day(for date: Date) -> CalendarDay {
        CalendarDay(
            date: calendar.startOfDay(for: date),
            monthDate: calendar.dateInterval(of: .month, for: date)?.start ?? date,
            isInDisplayedMonth: true
        )
    }

    func setStartOfWeek(_ option: StartOfWeekOption) {
        guard settings.startOfWeek != option else { return }
        settings.startOfWeek = option
        calendar = Self.makeConfiguredCalendar(base: baseCalendar, startOfWeek: option)
        currentMonthAnchor = calendar.dateInterval(of: .month, for: selectedMonthID)?.start ?? selectedMonthID
        months = Self.makeMonths(around: currentMonthAnchor, radius: monthPageRadius, calendar: calendar)
        selectedMonthID = currentMonthAnchor
        visibleYear = calendar.component(.year, from: selectedMonthID)
        persistStoredState()
        Task {
            await reloadEventsForVisibleInterval()
        }
    }

    func setShowsWeekNumbers(_ showsWeekNumbers: Bool) {
        guard settings.showsWeekNumbers != showsWeekNumbers else { return }
        settings.showsWeekNumbers = showsWeekNumbers
        persistStoredState()
    }

    private func reloadCalendarsAndEvents() async {
        loadState = .loading
        let calendars = eventKitService.fetchCalendars()
        let interval = visibleDateInterval()

        calendarSources = mergeLocalCalendarState(into: calendars)
        normalizeCalendarOrderIfNeeded()
        events = await eventKitService.fetchEvents(in: interval, calendars: calendars)
        settings.lastICloudSyncAt = Date()
        persistStoredState()
        loadState = .loaded
    }

    private func reloadGoogleCalendarsAndEvents() async {
        loadState = .loading

        do {
            let calendars = try await googleCalendarService.fetchCalendars()
            let interval = visibleDateInterval()
            calendarSources = mergeLocalCalendarState(into: calendars)
            normalizeCalendarOrderIfNeeded()
            events = try await googleCalendarService.fetchEvents(in: interval, calendars: calendars)
            googleAuthState = googleCalendarService.authState
            settings.lastGoogleSyncAt = Date()
            persistStoredState()
            loadState = .loaded
        } catch {
            calendarSources = []
            events = []
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }

    private func mergeLocalCalendarState(into calendars: [CalendarSource]) -> [CalendarSource] {
        let existingByID = Dictionary(uniqueKeysWithValues: calendarSources.map { ($0.id, $0) })

        let mergedCalendars = calendars.map { calendar in
            if let existing = existingByID[calendar.id] {
                var merged = calendar
                merged.isVisible = existing.isVisible
                merged.colorOverrideHex = existing.colorOverrideHex
                merged.titleOverride = existing.titleOverride
                return merged
            }

            guard let preference = calendarPreferences[calendar.id] else {
                return calendar
            }

            var merged = calendar
            merged.isVisible = preference.isVisible
            merged.colorOverrideHex = preference.colorOverrideHex
            merged.titleOverride = preference.titleOverride
            return merged
        }

        return ordered(calendars: mergedCalendars)
    }

    private func persistPreference(for calendar: CalendarSource) {
        calendarPreferences[calendar.id] = CalendarPreferences(
            isVisible: calendar.isVisible,
            colorOverrideHex: calendar.colorOverrideHex,
            titleOverride: calendar.titleOverride
        )
        persistStoredState()
    }

    private func normalizeCalendarOrderIfNeeded() {
        let currentIDs = calendarSources.map(\.id)
        let currentIDSet = Set(currentIDs)
        let normalized = settings.calendarOrder.filter { currentIDSet.contains($0) }
            + currentIDs.filter { !settings.calendarOrder.contains($0) }

        if settings.calendarOrder != normalized {
            settings.calendarOrder = normalized
        }

        if settings.defaultCalendarID != nil {
            settings.defaultCalendarID = nil
        }

        calendarSources = ordered(calendars: calendarSources)
    }

    private func ordered(calendars: [CalendarSource]) -> [CalendarSource] {
        let order = Dictionary(uniqueKeysWithValues: settings.calendarOrder.enumerated().map { ($0.element, $0.offset) })

        return calendars.sorted { lhs, rhs in
            switch (order[lhs.id], order[rhs.id]) {
            case let (lhsOrder?, rhsOrder?):
                return lhsOrder < rhsOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if lhs.provider != rhs.provider {
                    return lhs.provider.rawValue < rhs.provider.rawValue
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }

    private func persistStoredState() {
        preferencesStore.save(preferences: calendarPreferences, settings: settings)
    }

    private static func makeConfiguredCalendar(base: Calendar, startOfWeek: StartOfWeekOption) -> Calendar {
        var configured = base
        if let firstWeekday = startOfWeek.firstWeekdayOverride {
            configured.firstWeekday = firstWeekday
        }
        return configured
    }

    private static func syncDescription(for date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func shiftMonthWindow(to monthID: Date) {
        currentMonthAnchor = monthID
        months = Self.makeMonths(around: monthID, radius: monthPageRadius, calendar: calendar)
        selectedMonthID = monthID
        visibleYear = calendar.component(.year, from: monthID)
        Task {
            await reloadEventsForVisibleInterval()
        }
    }

    private func reloadEventsForVisibleInterval() async {
        switch selectedProvider {
        case .google where googleAuthState.isSignedIn:
            await reloadGoogleCalendarsAndEvents()
        case .iCloud where accessState == .granted:
            await reloadCalendarsAndEvents()
        default:
            break
        }
    }

    private func startObservingStoreChangesIfNeeded() {
        guard observationTask == nil else { return }

        observationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in eventKitService.observeChanges() {
                await self.reloadCalendarsAndEvents()
            }
        }
    }

    private func visibleDateInterval() -> DateInterval {
        guard let firstMonth = months.first?.date,
              let lastMonth = months.last?.date,
              let intervalEnd = calendar.date(byAdding: .month, value: 1, to: lastMonth) else {
            let now = Date()
            return DateInterval(start: now, duration: 60 * 60 * 24 * 365)
        }

        return DateInterval(start: firstMonth, end: intervalEnd)
    }

    private static func makeMonths(around date: Date, radius: Int, calendar: Calendar) -> [CalendarMonth] {
        (-radius...radius).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: date) else {
                return nil
            }

            return makeMonth(containing: month, calendar: calendar)
        }
    }

    private static func makeMonth(containing date: Date, calendar: Calendar) -> CalendarMonth? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstGridDate = gridStart(for: monthInterval.start, calendar: calendar),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastGridDate = gridEnd(for: lastDayOfMonth, calendar: calendar) else {
            return nil
        }

        let gridDayCount = (calendar.dateComponents([.day], from: firstGridDate, to: lastGridDate).day ?? 0) + 1
        let visibleDayCount = max(gridDayCount, 42)
        let days = (0..<visibleDayCount).compactMap { offset -> CalendarDay? in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: firstGridDate) else {
                return nil
            }

            return CalendarDay(
                date: dayDate,
                monthDate: monthInterval.start,
                isInDisplayedMonth: calendar.isDate(dayDate, equalTo: monthInterval.start, toGranularity: .month)
            )
        }

        let weeks = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }

        let weekNumbers = weeks.compactMap { week in
            week.first.map { calendar.component(.weekOfYear, from: $0.date) }
        }

        return CalendarMonth(date: monthInterval.start, weeks: weeks, weekNumbers: weekNumbers)
    }

    private static func gridStart(for monthStart: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: monthStart)
        let firstWeekday = calendar.firstWeekday
        let daysBack = (weekday - firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: monthStart)
    }

    private static func gridEnd(for monthEnd: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: monthEnd)
        let firstWeekday = calendar.firstWeekday
        let lastWeekday = ((firstWeekday + 5) % 7) + 1
        let daysForward = (lastWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysForward, to: monthEnd)
    }
}
