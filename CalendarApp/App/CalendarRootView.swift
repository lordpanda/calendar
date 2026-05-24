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
                        isLoading: viewModel.loadState == .loading,
                        onChooseICloud: {
                            Task {
                                await viewModel.requestCalendarAccess()
                            }
                        },
                        onChooseGoogle: {
                            connectGoogle()
                        }
                    )
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
    let isLoading: Bool
    let onChooseICloud: () -> Void
    let onChooseGoogle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text("연동할 달력을 선택하세요.")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                calendarCard(
                    title: "iCloud Calendar",
                    description: "지금 이 기기에서 사용 중인 iCloud 캘린더, 리마인더와 연동합니다.",
                    showSpinner: isLoading,
                    action: onChooseICloud
                )

                calendarCard(
                    title: "Google Calendar",
                    description: "Google 계정에 로그인 후 연동합니다.",
                    showSpinner: false,
                    action: onChooseGoogle
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarCard(
        title: String,
        description: String,
        showSpinner: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if showSpinner {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }

                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalendarTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
