import SwiftUI
import UIKit

struct CalendarRootView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDay: CalendarDay?
    @State private var isDrawerPresented = false
    @State private var eventEditorContext: EventEditView.EventContext?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if viewModel.shouldShowCalendarUI {
                    MonthScrollView(
                        viewModel: viewModel,
                        selectedDay: $selectedDay,
                        isDrawerPresented: $isDrawerPresented,
                        onCreateEvent: { date in
                            eventEditorContext = .create(seedDate: date)
                        },
                        onSelectEvent: openEventFromCalendar
                    )

                    BottomFloatingBar(
                        onToday: { viewModel.scrollToTodayTrigger += 1 },
                        onAdd: {
                            eventEditorContext = .create(seedDate: Date())
                        },
                        isAddEnabled: viewModel.hasWritableCalendars
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .zIndex(2)
                } else {
                    CalendarConnectionView(
                        selectedProvider: viewModel.selectedProvider,
                        accessState: viewModel.accessState,
                        googleAuthState: viewModel.googleAuthState,
                        isLoading: viewModel.loadState == .loading,
                        statusMessage: statusMessage,
                        onChooseICloud: {
                            Task {
                                await viewModel.requestCalendarAccess()
                            }
                        },
                        onChooseGoogle: {
                            connectGoogle()
                        },
                        onConnectICloud: {
                            Task {
                                await viewModel.requestCalendarAccess()
                            }
                        },
                        onConnectGoogle: {
                            connectGoogle()
                        },
                        onOpenSettings: openSystemSettings,
                        onBack: {
                            viewModel.selectProvider(.none)
                        }
                    )
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(CalendarTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadInitialData()
            }
            .sheet(item: $selectedDay) { day in
                DayScheduleView(
                    date: day.date,
                    events: viewModel.events(on: day.date),
                    colorForEvent: { viewModel.color(for: $0) },
                    onPreviousDay: { selectedDay = viewModel.day(for: Calendar.current.date(byAdding: .day, value: -1, to: day.date) ?? day.date) },
                    onNextDay: { selectedDay = viewModel.day(for: Calendar.current.date(byAdding: .day, value: 1, to: day.date) ?? day.date) },
                    onCreateEvent: {
                        presentEditorAfterDismissingDay(.create(seedDate: day.date))
                    },
                    onSelectEvent: { event in
                        guard event.kind == .event else { return }
                        presentEditorAfterDismissingDay(.edit(event))
                    }
                )
                .presentationDetents([.large])
                .presentationBackground(.thinMaterial)
            }
            .sheet(item: $eventEditorContext) { context in
                eventEditorView(for: context)
                .presentationDetents([.large])
            }
            .fullScreenCover(isPresented: $isDrawerPresented) {
                CalendarDrawerView(
                    viewModel: viewModel,
                    onConnectGoogle: connectGoogle
                )
            }
        }
        .tint(.accentColor)
    }

    private func connectGoogle() {
        guard let controller = topViewController() else { return }
        Task {
            await viewModel.connectGoogle(presentingViewController: controller)
        }
    }

    private func openEventFromCalendar(_ event: CalendarEvent) {
        guard event.kind == .event else {
            selectedDay = viewModel.day(for: event.startDate)
            return
        }

        selectedDay = nil
        eventEditorContext = .edit(event)
    }

    private func presentEditorAfterDismissingDay(_ context: EventEditView.EventContext) {
        selectedDay = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            eventEditorContext = context
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
            .map(findTopViewController)
    }

    private func findTopViewController(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return findTopViewController(presented)
        }

        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return findTopViewController(visible)
        }

        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return findTopViewController(selected)
        }

        return controller
    }

    private var statusMessage: String {
        switch viewModel.selectedProvider {
        case .none:
            return "Choose one provider to start."
        case .iCloud:
            return viewModel.statusMessage
        case .google:
            switch viewModel.googleAuthState {
            case .signedOut:
                return "Sign in with Google to load Google Calendar data."
            case .signedIn(let email):
                return "Signed in as \(email)."
            case .unavailable(let message):
                return message
            }
        }
    }

    @ViewBuilder
    private func eventEditorView(for context: EventEditView.EventContext) -> some View {
        switch context.mode {
        case .create(let seedDate):
            EventEditView(
                mode: .create,
                calendars: viewModel.visibleWritableCalendars,
                seedDate: seedDate
            ) { draft in
                await viewModel.createEvent(
                    title: draft.title,
                    startDate: draft.startDate,
                    endDate: draft.endDate,
                    isAllDay: draft.isAllDay,
                    calendarID: draft.calendarID,
                    location: draft.location.isEmpty ? nil : draft.location,
                    notes: draft.notes.isEmpty ? nil : draft.notes,
                    repeatOption: draft.repeatOption,
                    invitees: draft.invitees,
                    attachmentURL: draft.attachmentURL.isEmpty ? nil : draft.attachmentURL,
                    alertOption: draft.alertOption,
                    visibility: draft.visibility,
                    availability: draft.availability
                )
            }
        case .edit(let event):
            let canModify = viewModel.isCalendarWritable(event.calendarID)
            EventEditView(
                mode: .edit(eventID: event.id),
                calendars: viewModel.editableCalendars(for: event),
                existingEvent: event,
                onSave: { draft in
                    await viewModel.updateEvent(
                        eventID: event.id,
                        title: draft.title,
                        startDate: draft.startDate,
                        endDate: draft.endDate,
                        isAllDay: draft.isAllDay,
                        calendarID: draft.calendarID,
                        location: draft.location.isEmpty ? nil : draft.location,
                        notes: draft.notes.isEmpty ? nil : draft.notes,
                        repeatOption: draft.repeatOption,
                        invitees: draft.invitees,
                        attachmentURL: draft.attachmentURL.isEmpty ? nil : draft.attachmentURL,
                        alertOption: draft.alertOption,
                        visibility: draft.visibility,
                        availability: draft.availability
                    )
                },
                onDelete: canModify ? {
                    await viewModel.deleteEvent(eventID: event.id, calendarID: event.calendarID)
                } : nil
            )
        }
    }
}

private struct CalendarConnectionView: View {
    let selectedProvider: CalendarViewModel.ProviderSelection
    let accessState: EventKitService.AccessState
    let googleAuthState: GoogleCalendarService.AuthState
    let isLoading: Bool
    let statusMessage: String
    let onChooseICloud: () -> Void
    let onChooseGoogle: () -> Void
    let onConnectICloud: () -> Void
    let onConnectGoogle: () -> Void
    let onOpenSettings: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect a calendar")
                    .font(.largeTitle.bold())

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if selectedProvider != .none {
                selectedProviderCard(selectedProvider)
            } else {
                VStack(spacing: 12) {
                    providerButton(
                        title: "iCloud Calendar",
                        systemImage: "icloud",
                        trailing: "Available",
                        action: onChooseICloud
                    )

                    providerButton(
                        title: "Google Calendar",
                        systemImage: "g.circle",
                        trailing: "Available",
                        action: onChooseGoogle
                    )
                }
            }

            Spacer()
        }
        .frame(maxWidth: 520)
    }

    private var subtitle: String {
        selectedProvider == .none
            ? "Choose one provider to start."
            : "Continue with the selected provider."
    }

    @ViewBuilder
    private func selectedProviderCard(_ provider: CalendarViewModel.ProviderSelection) -> some View {
        switch provider {
        case .iCloud:
            VStack(alignment: .leading, spacing: 14) {
                headerRow(title: "iCloud Calendar", systemImage: "icloud")

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: onConnectICloud) {
                    HStack {
                        Text(accessState == .denied ? "Try Again" : "Continue with iCloud")
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                if accessState == .denied || accessState == .restricted {
                    Button("Open Settings", action: onOpenSettings)
                        .font(.subheadline.weight(.semibold))
                }

                Button("Choose a different provider", action: onBack)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(20)
            .background(CalendarTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        case .google:
            VStack(alignment: .leading, spacing: 14) {
                headerRow(title: "Google Calendar", systemImage: "g.circle")

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: onConnectGoogle) {
                    HStack {
                        Text("Continue with Google")
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || googleAuthState.isUnavailable)

                Button("Choose a different provider", action: onBack)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(20)
            .background(CalendarTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        case .none:
            EmptyView()
        }
    }

    private func providerButton(
        title: String,
        systemImage: String,
        trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(CalendarTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func headerRow(title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Spacer()

            Button("Back", action: onBack)
                .font(.subheadline.weight(.semibold))
        }
    }
}
