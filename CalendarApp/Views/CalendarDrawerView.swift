import SwiftUI

struct CalendarDrawerView: View {
    let calendars: [CalendarSource]

    var body: some View {
        NavigationStack {
            List {
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
}

private struct SettingsPlaceholderView: View {
    let calendars: [CalendarSource]

    var body: some View {
        List {
            Section("Accounts & Sync") {
                Label("iCloud", systemImage: "icloud")
                Label("Google", systemImage: "g.circle")
            }

            Section("Calendar Appearance") {
                LabeledContent("Start of the week", value: "System")
                LabeledContent("Show week numbers", value: "Off")
                LabeledContent("Default calendar", value: calendars.first?.title ?? "None")
            }

            Section("Calendar Colors") {
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
        .navigationTitle("Settings")
    }
}
