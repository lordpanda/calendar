import SwiftUI
import UIKit

struct CalendarDrawerView: View {
    @Bindable var viewModel: CalendarViewModel
    let onConnectGoogle: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var editSelection: CalendarEditSelection?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.calendarSources.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.tr("No calendars", language: language))
                                .font(.headline)
                            Text(drawerMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section {
                        ForEach(viewModel.orderedCalendarSources) { calendar in
                            HStack(spacing: 10) {
                                Button {
                                    viewModel.toggleCalendarVisibility(calendarID: calendar.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        CalendarVisibilityMark(calendar: calendar)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(calendar.displayTitle)
                                                .font(.body)
                                                .foregroundStyle(.primary)

                                            Text(calendar.provider.title(language: language))
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    editSelection = CalendarEditSelection(calendarID: calendar.id)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L.tr("Edit %@", language: language, calendar.displayTitle))
                            }
                            .padding(.vertical, 2)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 12))
                        }
                        .onMove { source, destination in
                            viewModel.moveCalendar(from: source, to: destination)
                        }
                    } footer: {
                        Text(L.tr("Drag to reorder. Hidden calendars are excluded from the new-event calendar choices.", language: language))
                    }
                }

                Section {
                    NavigationLink {
                        CalendarSettingsView(
                            viewModel: viewModel,
                            onConnectGoogle: onConnectGoogle
                        )
                    } label: {
                        Label(L.tr("Settings", language: language), systemImage: "gearshape")
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .listSectionSpacing(.compact)
            .navigationTitle(L.tr("Calendars", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editSelection) { selection in
                CalendarEditView(
                    viewModel: viewModel,
                    calendarID: selection.calendarID
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .tint(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityLabel(L.tr("Close", language: language))
                }
            }
        }
    }

    private var drawerMessage: String {
        switch viewModel.accessState {
        case .notDetermined:
            return L.tr("Calendar access has not been granted yet.", language: language)
        case .denied:
            return L.tr("Calendar access is denied.", language: language)
        case .restricted:
            return L.tr("Calendar access is restricted.", language: language)
        case .writeOnly:
            return L.tr("Only write-only access is available, so calendars cannot be listed.", language: language)
        case .unknown:
            return L.tr("Calendar access state is unknown.", language: language)
        case .granted:
            return L.tr("No EventKit calendars were returned on this device.", language: language)
        }
    }
}
