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
    var isICloudSyncInProgress = false
    var isGoogleSyncInProgress = false
    var isInitialLoadComplete = false

    private let baseCalendar: Calendar
    private var calendar: Calendar
    private let eventKitService: EventKitService
    private let googleCalendarService: GoogleCalendarService
    private let preferencesStore: CalendarPreferencesStore
    private var observationTask: Task<Void, Never>?
    private var visibleIntervalReloadTask: Task<Void, Never>?
    private let monthPageRadius = 12
    private let eventFetchRadius = 2
    private var calendarPreferences: [String: CalendarPreferences]
    private var currentMonthAnchor: Date
    private var loadedEventIntervals: [CalendarProviderKind: DateInterval] = [:]

    init(
        calendar: Calendar = .current,
        eventKitService: EventKitService = EventKitService(),
        googleCalendarService: GoogleCalendarService = GoogleCalendarService(),
        preferencesStore: CalendarPreferencesStore = CalendarPreferencesStore()
    ) {
        let storedState = preferencesStore.load()
        let storedSettings = storedState.settings
        let configuredCalendar = CalendarMonthBuilder.configuredCalendar(
            base: calendar,
            startOfWeek: storedSettings.startOfWeek
        )
        let todayMonth = configuredCalendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        self.settings = storedSettings
        self.baseCalendar = calendar
        self.calendar = configuredCalendar
        self.eventKitService = eventKitService
        self.googleCalendarService = googleCalendarService
        self.preferencesStore = preferencesStore
        self.calendarPreferences = storedState.preferences
        visibleYear = configuredCalendar.component(.year, from: todayMonth)
        selectedMonthID = todayMonth
        currentMonthAnchor = todayMonth
        months = CalendarMonthBuilder.makeMonths(
            around: todayMonth,
            radius: monthPageRadius,
            calendar: configuredCalendar
        )
        calendarSources = mergeLocalCalendarState(into: storedState.cachedCalendarSources)
        events = storedState.cachedEvents.filter { event in
            calendarSources.contains { $0.id == event.calendarID }
        }
        accessState = eventKitService.currentAccessState()
        googleAuthState = googleCalendarService.authState
    }

    var hasConnectedCalendars: Bool {
        !calendarSources.isEmpty
    }

    var shouldShowCalendarUI: Bool {
        hasConnectedCalendars || (settings.isICloudSyncEnabled && accessState == .granted)
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

    var visibleWritableTaskCalendars: [CalendarSource] {
        orderedCalendarSources.filter { $0.isWritable && $0.kind == .reminder && $0.isVisible }
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
        visibleWritableCalendars.first?.displayTitle ?? L.tr("No visible writable calendar", language: settings.language)
    }

    var startOfWeekSummary: String {
        settings.startOfWeek.title(language: settings.language)
    }

    var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = settings.language.locale
        formatter.dateFormat = "LLLL"
        return formatter.string(from: selectedMonthID)
    }

    var lastICloudSyncDescription: String {
        CalendarSyncDescriptionFormatter.string(for: settings.lastICloudSyncAt, language: settings.language)
    }

    var lastGoogleSyncDescription: String {
        CalendarSyncDescriptionFormatter.string(for: settings.lastGoogleSyncAt, language: settings.language)
    }

    var canRefreshICloud: Bool {
        accessState == .granted || accessState == .notDetermined
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
            return L.tr("Calendar access has not been requested yet.", language: settings.language)
        case .denied:
            return L.tr("Calendar access was denied. Enable access in Settings to load local calendars.", language: settings.language)
        case .restricted:
            return L.tr("Calendar access is restricted on this device.", language: settings.language)
        case .writeOnly:
            return L.tr("Only write-only calendar access is available, so existing events cannot be read.", language: settings.language)
        case .unknown:
            return L.tr("Calendar authorization state is unknown.", language: settings.language)
        case .granted:
            if calendarSources.isEmpty {
                return L.tr("No local calendars are currently available.", language: settings.language)
            }
            return L.tr("Connected to local calendars through EventKit.", language: settings.language)
        }
    }

    func loadInitialData() async {
        guard !isInitialLoadComplete else { return }
        loadState = .loading
        defer { isInitialLoadComplete = true }

        accessState = eventKitService.currentAccessState()
        await googleCalendarService.restorePreviousSignInIfPossible()
        googleAuthState = googleCalendarService.authState

        if googleAuthState.isSignedIn || (settings.isICloudSyncEnabled && accessState == .granted) {
            if googleAuthState.isSignedIn {
                selectedProvider = .google
            } else {
                selectedProvider = .iCloud
            }

            await reloadConnectedProvidersForVisibleInterval()

            if settings.isICloudSyncEnabled && accessState == .granted {
                startObservingStoreChangesIfNeeded()
            }
        } else {
            loadState = .idle
        }
    }

    func requestCalendarAccess() async {
        isICloudSyncInProgress = true
        let timeoutTask = startICloudProgressTimeout()
        defer { isICloudSyncInProgress = false }
        defer { timeoutTask.cancel() }

        settings.isICloudSyncEnabled = true
        persistStoredState()
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

    func refreshCalendarAccessState() {
        accessState = eventKitService.currentAccessState()
    }

    func selectProvider(_ provider: ProviderSelection) {
        selectedProvider = provider
    }

    func connectGoogle(presentingViewController: UIViewController) async {
        isGoogleSyncInProgress = true
        let timeoutTask = startGoogleProgressTimeout()
        defer { isGoogleSyncInProgress = false }
        defer { timeoutTask.cancel() }

        selectedProvider = .google
        loadState = .loading

        do {
            googleAuthState = try await googleCalendarService.signIn(presentingViewController: presentingViewController)
            await reloadGoogleCalendarsAndEvents()
        } catch {
            googleAuthState = googleCalendarService.authState
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }

    func disconnectGoogle() async {
        isGoogleSyncInProgress = true
        defer { isGoogleSyncInProgress = false }

        googleCalendarService.signOut()
        googleAuthState = googleCalendarService.authState

        if settings.isICloudSyncEnabled && accessState == .granted {
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
        isICloudSyncInProgress = true
        let timeoutTask = startICloudProgressTimeout()
        defer { isICloudSyncInProgress = false }
        defer { timeoutTask.cancel() }

        settings.isICloudSyncEnabled = true
        persistStoredState()
        refreshCalendarAccessState()

        if accessState == .notDetermined {
            await requestCalendarAccess()
            return
        }

        guard accessState == .granted else { return }
        selectedProvider = .iCloud
        await reloadCalendarsAndEvents()
        startObservingStoreChangesIfNeeded()
    }

    func disconnectICloud() {
        isICloudSyncInProgress = true
        defer { isICloudSyncInProgress = false }

        settings.isICloudSyncEnabled = false
        calendarSources.removeAll { $0.provider == .iCloud }
        events.removeAll { event in
            calendarSources.first(where: { $0.id == event.calendarID }) == nil
        }
        if googleAuthState.isSignedIn {
            selectedProvider = .google
        } else {
            selectedProvider = .none
            loadState = .idle
        }
        persistStoredState()
    }

    func refreshGoogleNow() async {
        guard googleAuthState.isSignedIn else { return }
        isGoogleSyncInProgress = true
        let timeoutTask = startGoogleProgressTimeout()
        defer { isGoogleSyncInProgress = false }
        defer { timeoutTask.cancel() }

        selectedProvider = .google
        await reloadGoogleCalendarsAndEvents()
    }

    func refreshAfterReturningToForeground() async {
        guard isInitialLoadComplete else { return }

        refreshCalendarAccessState()
        await googleCalendarService.restorePreviousSignInIfPossible()
        googleAuthState = googleCalendarService.authState

        guard googleAuthState.isSignedIn || (settings.isICloudSyncEnabled && accessState == .granted) else {
            return
        }

        await reloadConnectedProvidersForVisibleInterval()

        if settings.isICloudSyncEnabled && accessState == .granted {
            startObservingStoreChangesIfNeeded()
        }
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
                let createdEvent = try await googleCalendarService.createEvent(
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
                upsertCachedEvent(createdEvent)
                scheduleVisibleIntervalReload()
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
                insertCachedEvent(
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
                scheduleVisibleIntervalReload()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func createTask(
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String? = nil
    ) async -> Bool {
        do {
            if calendarSources.first(where: { $0.id == calendarID })?.provider == .google {
                let createdTask = try await googleCalendarService.createTask(
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    notes: notes
                )
                upsertCachedEvent(createdTask)
                scheduleVisibleIntervalReload()
            } else {
                try eventKitService.createReminder(
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    notes: notes
                )
                insertCachedTask(
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    notes: notes
                )
                scheduleVisibleIntervalReload()
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
        availability: EventAvailabilityOption = .busy,
        recurringEventID: String? = nil,
        editScope: RecurringEventEditScope = .thisEvent
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
                    availability: availability,
                    recurringEventID: recurringEventID,
                    editScope: editScope
                )
                updateCachedEvent(
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
                scheduleVisibleIntervalReload()
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
                    availability: availability,
                    editScope: editScope
                )
                updateCachedEvent(
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
                scheduleVisibleIntervalReload()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func updateTask(
        eventID: String,
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String? = nil
    ) async -> Bool {
        do {
            if calendarSources.first(where: { $0.id == calendarID })?.provider == .google {
                try await googleCalendarService.updateTask(
                    eventID: eventID,
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    notes: notes
                )
                updateCachedTask(
                    eventID: eventID,
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    notes: notes
                )
                scheduleVisibleIntervalReload()
            } else {
                try eventKitService.updateReminder(
                    reminderID: eventID,
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    calendarID: calendarID,
                    notes: notes
                )
                updateCachedTask(
                    eventID: eventID,
                    title: title,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    notes: notes
                )
                scheduleVisibleIntervalReload()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func setTaskCompletion(eventID: String, calendarID: String, isCompleted: Bool) async -> Bool {
        do {
            let provider = calendarSources.first(where: { $0.id == calendarID })?.provider
            if provider == .google {
                try await googleCalendarService.setTaskCompletion(eventID: eventID, isCompleted: isCompleted)
            } else {
                try eventKitService.setReminderCompletion(reminderID: eventID, isCompleted: isCompleted)
            }
            updateCachedTaskCompletion(eventID: eventID, isCompleted: isCompleted)
            Task {
                await reloadEventsForVisibleInterval()
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func deleteEvent(
        eventID: String,
        calendarID: String,
        recurringEventID: String? = nil,
        deleteScope: RecurringEventDeleteScope = .thisEvent,
        cachedEvent: CalendarEvent? = nil
    ) async -> Bool {
        if eventID.hasPrefix("local-") {
            finalizeDeletedEvent(cachedEvent)
            return true
        }

        do {
            let source = calendarSources.first(where: { $0.id == calendarID })
            if source?.kind == .reminder {
                if source?.provider == .google {
                    try await googleCalendarService.deleteTask(eventID: eventID)
                    finalizeDeletedEvent(cachedEvent)
                } else {
                    try eventKitService.deleteReminder(reminderID: eventID)
                    finalizeDeletedEvent(cachedEvent)
                }
            } else if source?.provider == .google {
                try await googleCalendarService.deleteEvent(
                    eventID: eventID,
                    calendarID: calendarID,
                    recurringEventID: recurringEventID,
                    deleteScope: deleteScope
                )
                finalizeDeletedEvent(cachedEvent)
            } else {
                try eventKitService.deleteEvent(
                    eventID: eventID,
                    recurringEventID: recurringEventID,
                    deleteScope: deleteScope
                )
                finalizeDeletedEvent(cachedEvent)
            }
            return true
        } catch {
            if sourceIsGoogle(calendarID), isNotFoundError(error) {
                finalizeDeletedEvent(cachedEvent)
                return true
            }
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
        } else {
            Task {
                await reloadEventsForSelectedMonthIfNeeded()
            }
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
        calendar = CalendarMonthBuilder.configuredCalendar(base: baseCalendar, startOfWeek: option)
        currentMonthAnchor = calendar.dateInterval(of: .month, for: selectedMonthID)?.start ?? selectedMonthID
        months = CalendarMonthBuilder.makeMonths(
            around: currentMonthAnchor,
            radius: monthPageRadius,
            calendar: calendar
        )
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

    func setShowsCompletedTasks(_ showsCompletedTasks: Bool) {
        guard settings.showsCompletedTasks != showsCompletedTasks else { return }
        settings.showsCompletedTasks = showsCompletedTasks
        persistStoredState()
        Task {
            await reloadEventsForVisibleInterval()
        }
    }

    func setMosaicModeEnabled(_ isEnabled: Bool) {
        guard settings.isMosaicModeEnabled != isEnabled else { return }
        settings.isMosaicModeEnabled = isEnabled
        persistStoredState()
    }

    func setMonthContentScale(_ scale: MonthContentScale) {
        guard settings.monthContentScale != scale else { return }
        settings.monthContentScale = scale
        persistStoredState()
    }

    func setLanguage(_ language: AppLanguage) {
        guard settings.language != language else { return }
        settings.language = language
        persistStoredState()
    }

    func setUsesDeviceTimeZone(_ usesDeviceTimeZone: Bool) {
        guard settings.usesDeviceTimeZone != usesDeviceTimeZone else { return }
        settings.usesDeviceTimeZone = usesDeviceTimeZone
        persistStoredState()
    }

    private func reloadCalendarsAndEvents() async {
        loadState = .loading
        try? await eventKitService.requestReminderAccessIfNeeded()
        let eventKitService = eventKitService
        let calendars = await Task.detached {
            eventKitService.fetchCalendars()
        }.value
        let interval = eventFetchInterval(around: selectedMonthID)

        replaceCalendarSources(for: .iCloud, with: calendars)
        normalizeCalendarOrderIfNeeded()
        let showsCompletedTasks = settings.showsCompletedTasks
        let iCloudEvents = await Task.detached {
            await eventKitService.fetchEvents(
                in: interval,
                calendars: calendars,
                showsCompletedTasks: showsCompletedTasks
            )
        }.value
        replaceEvents(for: .iCloud, in: interval, with: iCloudEvents)
        loadedEventIntervals[.iCloud] = interval
        settings.lastICloudSyncAt = Date()
        persistStoredState()
        loadState = .loaded
    }

    private func startICloudProgressTimeout() -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isICloudSyncInProgress else { return }
                self.isICloudSyncInProgress = false
                self.loadState = .failed("iCloud sync timed out.")
            }
        }
    }

    private func startGoogleProgressTimeout() -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isGoogleSyncInProgress else { return }
                self.isGoogleSyncInProgress = false
                self.lastErrorMessage = L.tr("Google sync timed out.", language: .system)
                self.loadState = .failed(self.lastErrorMessage ?? L.tr("Google sync timed out.", language: .system))
            }
        }
    }

    private func reloadGoogleCalendarsAndEvents() async {
        loadState = .loading
        let hasExistingGoogleData = calendarSources.contains { $0.provider == .google }
            || events.contains { event in
                calendarSources.first(where: { $0.id == event.calendarID })?.provider == .google
            }

        do {
            let calendars = try await googleCalendarService.fetchCalendars()
            let interval = eventFetchInterval(around: selectedMonthID)
            replaceCalendarSources(for: .google, with: calendars)
            normalizeCalendarOrderIfNeeded()
            let googleEvents = try await googleCalendarService.fetchEvents(
                in: interval,
                calendars: calendars,
                showsCompletedTasks: settings.showsCompletedTasks
            )
            replaceEvents(for: .google, in: interval, with: googleEvents)
            loadedEventIntervals[.google] = interval
            googleAuthState = googleCalendarService.authState
            settings.lastGoogleSyncAt = Date()
            persistStoredState()
            loadState = .loaded
        } catch {
            googleAuthState = googleCalendarService.authState
            lastErrorMessage = error.localizedDescription
            loadState = hasExistingGoogleData ? .loaded : .failed(error.localizedDescription)
        }
    }

    private func replaceCalendarSources(for provider: CalendarProviderKind, with calendars: [CalendarSource]) {
        let otherCalendars = calendarSources.filter { $0.provider != provider }
        calendarSources = mergeLocalCalendarState(into: otherCalendars + calendars)
    }

    private func replaceEvents(for provider: CalendarProviderKind, in interval: DateInterval, with providerEvents: [CalendarEvent]) {
        let providerCalendarIDs = Set(calendarSources.filter { $0.provider == provider }.map(\.id))
        if provider == .google {
            events.removeAll { event in
                providerCalendarIDs.contains(event.calendarID) && event.intersects(interval)
            }
            events.append(contentsOf: providerEvents)
            events.sort { $0.startDate < $1.startDate }
            return
        }

        let pendingLocalEvents = events.filter { event in
            event.id.hasPrefix("local-")
                && providerCalendarIDs.contains(event.calendarID)
                && event.intersects(interval)
        }
        events.removeAll { event in
            providerCalendarIDs.contains(event.calendarID)
                && event.intersects(interval)
                && !event.id.hasPrefix("local-")
        }
        let unmatchedPendingLocalEvents = pendingLocalEvents.filter { localEvent in
            !providerEvents.contains { serverEvent in
                eventsMatchForReconciliation(localEvent, serverEvent)
            }
        }
        events.append(contentsOf: unmatchedPendingLocalEvents)
        events.append(contentsOf: providerEvents)
        events.sort { $0.startDate < $1.startDate }
    }

    private func upsertCachedEvent(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        events.append(event)
        events.sort { $0.startDate < $1.startDate }
        persistStoredState()
    }

    private func eventsMatchForReconciliation(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        guard lhs.calendarID == rhs.calendarID,
              lhs.kind == rhs.kind,
              lhs.isAllDay == rhs.isAllDay,
              lhs.title.trimmingCharacters(in: .whitespacesAndNewlines) == rhs.title.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        let startDelta = abs(lhs.startDate.timeIntervalSince(rhs.startDate))
        let endDelta = abs(lhs.endDate.timeIntervalSince(rhs.endDate))
        guard startDelta < 60, endDelta < 60 else {
            return false
        }

        let lhsNotes = lhs.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsNotes = rhs.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lhsLocation = lhs.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsLocation = rhs.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsNotes == rhsNotes && lhsLocation == rhsLocation
    }

    private func updateCachedTaskCompletion(eventID: String, isCompleted: Bool) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].isCompleted = isCompleted
        persistStoredState()
    }

    private func removeCachedEvent(matching event: CalendarEvent) {
        let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)

        events.removeAll { cached in
            guard cached.calendarID == event.calendarID,
                  cached.kind == event.kind,
                  cached.isAllDay == event.isAllDay,
                  cached.title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTitle else {
                return false
            }

            let startDelta = abs(cached.startDate.timeIntervalSince(event.startDate))
            let endDelta = abs(cached.endDate.timeIntervalSince(event.endDate))
            guard startDelta < 60, endDelta < 60 else {
                return false
            }

            let cachedNotes = cached.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cachedLocation = cached.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            return cachedNotes == trimmedNotes && cachedLocation == trimmedLocation
        }

        persistStoredState()
    }

    private func finalizeDeletedEvent(_ cachedEvent: CalendarEvent?) {
        if let cachedEvent {
            removeCachedEvent(matching: cachedEvent)
        }
        scheduleVisibleIntervalReload()
    }

    private func sourceIsGoogle(_ calendarID: String) -> Bool {
        calendarSources.first(where: { $0.id == calendarID })?.provider == .google
    }

    private func isNotFoundError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "GoogleCalendarService", nsError.userInfo["httpStatusCode"] as? Int == 404 {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        return description.contains("not found") || description.contains("notfound")
    }

    private func insertCachedEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String?,
        notes: String?,
        repeatOption: EventRepeatOption,
        invitees: [String],
        attachmentURL: String?,
        alertOption: EventAlertOption,
        visibility: EventVisibilityOption,
        availability: EventAvailabilityOption
    ) {
        let event = CalendarEvent(
            id: "local-\(UUID().uuidString)",
            calendarID: calendarID,
            recurringEventID: nil,
            kind: .event,
            title: title.isEmpty ? L.tr("Untitled", language: .system) : title,
            location: location,
            notes: notes,
            startDate: startDate,
            endDate: max(endDate, startDate.addingTimeInterval(60)),
            isAllDay: isAllDay,
            repeatOption: repeatOption,
            invitees: invitees,
            attachmentURL: attachmentURL,
            alertOption: alertOption,
            visibility: visibility,
            availability: availability
        )
        events.append(event)
        events.sort { $0.startDate < $1.startDate }
        persistStoredState()
    }

    private func insertCachedTask(
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String?
    ) {
        let startDate = isAllDay ? calendar.startOfDay(for: dueDate) : dueDate
        let endDate = isAllDay
            ? calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
            : dueDate.addingTimeInterval(60 * 30)
        let task = CalendarEvent(
            id: "local-\(UUID().uuidString)",
            calendarID: calendarID,
            recurringEventID: nil,
            kind: .reminder,
            title: title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title,
            location: nil,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            isCompleted: false
        )
        events.append(task)
        events.sort { $0.startDate < $1.startDate }
        persistStoredState()
    }

    private func updateCachedEvent(
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String?,
        notes: String?,
        repeatOption: EventRepeatOption,
        invitees: [String],
        attachmentURL: String?,
        alertOption: EventAlertOption,
        visibility: EventVisibilityOption,
        availability: EventAvailabilityOption
    ) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].title = title.isEmpty ? L.tr("Untitled", language: .system) : title
        events[index].startDate = startDate
        events[index].endDate = max(endDate, startDate.addingTimeInterval(60))
        events[index].isAllDay = isAllDay
        events[index].calendarID = calendarID
        events[index].location = location
        events[index].notes = notes
        events[index].repeatOption = repeatOption
        events[index].invitees = invitees
        events[index].attachmentURL = attachmentURL
        events[index].alertOption = alertOption
        events[index].visibility = visibility
        events[index].availability = availability
        events.sort { $0.startDate < $1.startDate }
        persistStoredState()
    }

    private func updateCachedTask(
        eventID: String,
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        notes: String?
    ) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].title = title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title
        events[index].startDate = isAllDay ? calendar.startOfDay(for: dueDate) : dueDate
        events[index].endDate = isAllDay
            ? calendar.date(byAdding: .day, value: 1, to: events[index].startDate) ?? events[index].startDate.addingTimeInterval(86400)
            : dueDate.addingTimeInterval(60 * 30)
        events[index].isAllDay = isAllDay
        events[index].notes = notes
        events.sort { $0.startDate < $1.startDate }
        persistStoredState()
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
        preferencesStore.save(
            preferences: calendarPreferences,
            settings: settings,
            cachedCalendarSources: calendarSources,
            cachedEvents: events
        )
    }

    private func shiftMonthWindow(to monthID: Date) {
        currentMonthAnchor = monthID
        months = CalendarMonthBuilder.makeMonths(around: monthID, radius: monthPageRadius, calendar: calendar)
        selectedMonthID = monthID
        visibleYear = calendar.component(.year, from: monthID)
        Task {
            await reloadEventsForVisibleInterval()
        }
    }

    private func reloadEventsForVisibleInterval() async {
        await reloadConnectedProvidersForVisibleInterval()
    }

    private func scheduleVisibleIntervalReload() {
        visibleIntervalReloadTask?.cancel()
        visibleIntervalReloadTask = Task {
            await reloadEventsForVisibleInterval()
        }
    }

    private func reloadEventsForSelectedMonthIfNeeded() async {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonthID) else {
            return
        }

        let needsReload = activeEventProviders().contains { provider in
            guard let loadedInterval = loadedEventIntervals[provider] else {
                return true
            }

            return loadedInterval.start > monthInterval.start || loadedInterval.end < monthInterval.end
        }

        if !needsReload {
            return
        }

        await reloadEventsForVisibleInterval()
    }

    private func activeEventProviders() -> [CalendarProviderKind] {
        var providers: [CalendarProviderKind] = []

        if settings.isICloudSyncEnabled && accessState == .granted {
            providers.append(.iCloud)
        }

        if googleAuthState.isSignedIn {
            providers.append(.google)
        }

        return providers
    }

    private func reloadConnectedProvidersForVisibleInterval() async {
        var reloadedAnyProvider = false

        if settings.isICloudSyncEnabled && accessState == .granted {
            await reloadCalendarsAndEvents()
            reloadedAnyProvider = true
        }

        if googleAuthState.isSignedIn {
            await reloadGoogleCalendarsAndEvents()
            reloadedAnyProvider = true
        }

        if !reloadedAnyProvider {
            loadState = .idle
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

    private func eventFetchInterval(around monthID: Date) -> DateInterval {
        guard let monthStart = calendar.dateInterval(of: .month, for: monthID)?.start,
              let intervalStart = calendar.date(byAdding: .month, value: -eventFetchRadius, to: monthStart),
              let lastMonth = calendar.date(byAdding: .month, value: eventFetchRadius, to: monthStart),
              let intervalEnd = calendar.date(byAdding: .month, value: 1, to: lastMonth) else {
            let now = Date()
            return DateInterval(start: now, duration: 60 * 60 * 24 * 150)
        }

        return DateInterval(start: intervalStart, end: intervalEnd)
    }

}
