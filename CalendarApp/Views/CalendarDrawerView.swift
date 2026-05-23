import SwiftUI

struct CalendarDrawerView: View {
    let calendars: [CalendarSource]
    let accessState: EventKitService.AccessState

    var body: some View {
        NavigationStack {
            List {
                if calendars.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No calendars")
                                .font(.headline)
                            Text(drawerMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ForEach(CalendarProviderKind.allCases) { provider in
                        let providerCalendars = calendars.filter { $0.provider == provider }

                        if !providerCalendars.isEmpty {
                            Section(provider.rawValue) {
                                ForEach(providerCalendars) { calendar in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(calendar.displayColor)
                                            .frame(width: 12, height: 12)

                                        Text(calendar.title)

                                        Spacer()

                                        Image(systemName: calendar.isVisible ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(calendar.isVisible ? Color.accentColor : .secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsPlaceholderView(calendars: calendars)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Calendars")
        }
    }

    private var drawerMessage: String {
        switch accessState {
        case .notDetermined:
            return "Calendar access has not been granted yet."
        case .denied:
            return "Calendar access is denied."
        case .restricted:
            return "Calendar access is restricted."
        case .writeOnly:
            return "Only write-only access is available, so calendars cannot be listed."
        case .unknown:
            return "Calendar access state is unknown."
        case .granted:
            return "No EventKit calendars were returned on this device."
        }
    }
}

private struct SettingsPlaceholderView: View {
    let calendars: [CalendarSource]

    var body: some View {
        List {
            Section("Accounts & Sync") {
                LabeledContent("Status", value: "Not implemented")
                Text("EventKit permission flow, iCloud sync, and Google OAuth are not wired yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar Appearance") {
                LabeledContent("Status", value: "Placeholder only")
                Text("Start of week, week numbers, default calendar, and color overrides are not implemented yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar Colors") {
                if calendars.isEmpty {
                    Text("No connected calendars")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendars) { calendar in
                        HStack {
                            Circle()
                                .fill(calendar.displayColor)
                                .frame(width: 12, height: 12)
                            Text(calendar.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
