import SwiftUI

struct CalendarRootView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDay: CalendarDay?
    @State private var isDrawerPresented = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MonthScrollView(
                    viewModel: viewModel,
                    selectedDay: $selectedDay,
                    isDrawerPresented: $isDrawerPresented
                )

                BottomFloatingBar(
                    onToday: { viewModel.scrollToTodayTrigger += 1 },
                    onAdd: {
                        selectedDay = viewModel.day(for: Date())
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .background(CalendarTheme.background.ignoresSafeArea())
            .sheet(item: $selectedDay) { day in
                DayScheduleView(
                    date: day.date,
                    events: viewModel.events(on: day.date),
                    onPreviousDay: { selectedDay = viewModel.day(for: Calendar.current.date(byAdding: .day, value: -1, to: day.date) ?? day.date) },
                    onNextDay: { selectedDay = viewModel.day(for: Calendar.current.date(byAdding: .day, value: 1, to: day.date) ?? day.date) }
                )
                .presentationDetents([.large])
                .presentationBackground(.thinMaterial)
            }
            .sheet(isPresented: $isDrawerPresented) {
                CalendarDrawerView(calendars: viewModel.calendarSources)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
            }
        }
        .tint(.accentColor)
    }
}
