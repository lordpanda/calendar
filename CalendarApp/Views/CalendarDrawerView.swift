import SwiftUI

struct CalendarDrawerView: View {
    @Bindable var viewModel: CalendarViewModel
    let onConnectGoogle: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editSelection: CalendarEditSelection?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.calendarSources.isEmpty {
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
                    Section {
                        ForEach(viewModel.orderedCalendarSources) { calendar in
                            HStack(spacing: 12) {
                                Button {
                                    viewModel.toggleCalendarVisibility(calendarID: calendar.id)
                                } label: {
                                    HStack(spacing: 14) {
                                        CalendarVisibilityMark(calendar: calendar)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(calendar.displayTitle)
                                                .font(.body)
                                                .foregroundStyle(.primary)

                                            Text(calendar.provider.title)
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
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(calendar.displayTitle)")
                            }
                            .padding(.vertical, 5)
                        }
                        .onMove { source, destination in
                            viewModel.moveCalendar(from: source, to: destination)
                        }
                    } header: {
                        Text("Calendars")
                    } footer: {
                        Text("Drag to reorder. Hidden calendars are excluded from the new-event calendar choices.")
                    }
                }

                Section {
                    NavigationLink {
                        CalendarSettingsView(
                            viewModel: viewModel,
                            onConnectGoogle: onConnectGoogle
                        )
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Calendars")
            .sheet(item: $editSelection) { selection in
                CalendarEditView(
                    viewModel: viewModel,
                    calendarID: selection.calendarID
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var drawerMessage: String {
        switch viewModel.accessState {
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

private struct CalendarEditSelection: Identifiable {
    let calendarID: String
    var id: String { calendarID }
}

private struct CalendarVisibilityMark: View {
    let calendar: CalendarSource

    var body: some View {
        ZStack {
            Circle()
                .fill(calendar.isVisible ? calendar.displayColor : Color.clear)
                .overlay {
                    Circle()
                        .stroke(calendar.displayColor, lineWidth: calendar.isVisible ? 0 : 2)
                }

            if calendar.isVisible {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private struct CalendarSettingsView: View {
    @Bindable var viewModel: CalendarViewModel
    let onConnectGoogle: () -> Void

    var body: some View {
        List {
            Section("Accounts & Sync") {
                providerStatusRow(
                    title: "iCloud",
                    subtitle: "Last sync: \(viewModel.lastICloudSyncDescription)",
                    count: viewModel.iCloudCalendarCount,
                    systemImage: "icloud"
                )

                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await viewModel.refreshICloudNow()
                    }
                } label: {
                    syncButtonLabel(title: "Sync iCloud Now")
                }
                .disabled(!viewModel.canRefreshICloud || viewModel.loadState == .loading)

                providerStatusRow(
                    title: "Google",
                    subtitle: "Last sync: \(viewModel.lastGoogleSyncDescription)",
                    count: viewModel.googleCalendarCount,
                    systemImage: "g.circle"
                )

                Text(googleStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if viewModel.canRefreshGoogle {
                    Button {
                        Task {
                            await viewModel.refreshGoogleNow()
                        }
                    } label: {
                        syncButtonLabel(title: "Sync Google Now")
                    }
                    .disabled(viewModel.loadState == .loading)

                    Button("Disconnect Google", role: .destructive) {
                        Task {
                            await viewModel.disconnectGoogle()
                        }
                    }
                    .disabled(viewModel.loadState == .loading)
                } else {
                    Button {
                        onConnectGoogle()
                    } label: {
                        syncButtonLabel(title: "Connect Google")
                    }
                    .disabled(viewModel.loadState == .loading || viewModel.googleAuthState.isUnavailable)
                }

                LabeledContent("Visible Calendars", value: "\(viewModel.visibleCalendarCount) / \(viewModel.calendarSources.count)")
            }

            Section {
                LabeledContent("Current Start", value: viewModel.startOfWeekSummary)

                Picker("Start of Week", selection: Binding(
                    get: { viewModel.settings.startOfWeek },
                    set: { viewModel.setStartOfWeek($0) }
                )) {
                    ForEach(StartOfWeekOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Toggle("Show Week Numbers", isOn: Binding(
                    get: { viewModel.settings.showsWeekNumbers },
                    set: { viewModel.setShowsWeekNumbers($0) }
                ))

                LabeledContent("First Calendar for New Events", value: viewModel.firstCalendarForNewEventsDisplayName)
            } header: {
                Text("Calendar Appearance")
            } footer: {
                Text("New events use the first visible writable calendar in the calendar list order.")
            }

            if viewModel.calendarSources.isEmpty {
                Section("Calendar Colors") {
                    Text("No connected calendars")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(CalendarProviderKind.allCases) { provider in
                    let providerCalendars = viewModel.orderedCalendarSources.filter { $0.provider == provider }

                    if !providerCalendars.isEmpty {
                        Section {
                            ForEach(providerCalendars) { calendar in
                                NavigationLink {
                                    CalendarColorOverrideView(
                                        viewModel: viewModel,
                                        calendarID: calendar.id,
                                        onSelectColor: { hex in
                                            viewModel.setCalendarColorOverride(calendarID: calendar.id, colorHex: hex)
                                        },
                                        onReset: {
                                            viewModel.setCalendarColorOverride(calendarID: calendar.id, colorHex: nil)
                                        }
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(calendar.displayColor)
                                            .frame(width: 12, height: 12)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(calendar.displayTitle)
                                            Text(calendar.isVisible ? "Visible" : "Hidden")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if calendar.colorOverrideHex != nil {
                                            Text("Custom")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Calendar Colors · \(provider.title)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var googleStatusText: String {
        switch viewModel.googleAuthState {
        case .signedOut:
            return "Not signed in"
        case .signedIn(let email):
            return email
        case .unavailable(let message):
            return message
        }
    }

    @ViewBuilder
    private func syncButtonLabel(title: String) -> some View {
        if viewModel.loadState == .loading {
            HStack(spacing: 10) {
                ProgressView()
                Text(title)
            }
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func providerStatusRow(
        title: String,
        subtitle: String,
        count: Int,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CalendarEditView: View {
    @Bindable var viewModel: CalendarViewModel
    let calendarID: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 14)]
    private let palette = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE", "32ADE6",
        "007AFF", "5856D6", "AF52DE", "FF2D55", "8E8E93", "636366",
        "D35400", "2ECC71", "16A085", "2980B9", "6C5CE7", "C0392B"
    ]

    var body: some View {
        NavigationStack {
            List {
                if let calendar {
                    Section {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(calendar.displayColor)
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.displayTitle)
                                    .font(.body)
                                Text(calendar.provider.title)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Section {
                        TextField("Display Name", text: $draftName)
                            .textInputAutocapitalization(.never)

                        Button("Reset to Original Name") {
                            draftName = calendar.title
                            viewModel.setCalendarTitleOverride(calendarID: calendarID, title: nil)
                        }
                        .disabled(calendar.titleOverride == nil)
                    } header: {
                        Text("Name")
                    } footer: {
                        Text("Original name: \(calendar.title)")
                    }

                    Section {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(palette, id: \.self) { hex in
                                Button {
                                    viewModel.setCalendarColorOverride(calendarID: calendarID, colorHex: hex)
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .accentColor)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Circle()
                                                .stroke(selectedColorHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select color \(hex)")
                            }
                        }
                        .padding(.vertical, 6)

                        Button("Reset to Original Color", role: .destructive) {
                            viewModel.setCalendarColorOverride(calendarID: calendarID, colorHex: nil)
                        }
                        .disabled(calendar.colorOverrideHex == nil)
                    } header: {
                        Text("Color")
                    }
                }
            }
            .navigationTitle("Edit Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.setCalendarTitleOverride(calendarID: calendarID, title: draftName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draftName = calendar?.displayTitle ?? ""
            }
        }
    }

    private var calendar: CalendarSource? {
        viewModel.calendarSource(id: calendarID)
    }

    private var selectedColorHex: String? {
        guard let calendar else { return nil }
        return calendar.colorOverrideHex ?? calendar.colorHex
    }
}

private struct CalendarColorOverrideView: View {
    @Bindable var viewModel: CalendarViewModel
    let calendarID: String
    let onSelectColor: (String) -> Void
    let onReset: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 14)]
    private let palette = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE", "32ADE6",
        "007AFF", "5856D6", "AF52DE", "FF2D55", "8E8E93", "636366",
        "D35400", "2ECC71", "16A085", "2980B9", "6C5CE7", "C0392B"
    ]

    var body: some View {
        List {
            Section {
                if let calendar {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(calendar.displayColor)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.displayTitle)
                            Text(calendar.provider.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Palette") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(palette, id: \.self) { hex in
                        Button {
                            onSelectColor(hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .accentColor)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            selectedColorHex == hex ? Color.primary : Color.clear,
                                            lineWidth: 2
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select color \(hex)")
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Button("Reset to Original Color", role: .destructive, action: onReset)
                    .disabled(calendar?.colorOverrideHex == nil)
            } footer: {
                Text("Color overrides are local to this app and do not change the original calendar color.")
            }
        }
        .navigationTitle("Calendar Color")
    }

    private var calendar: CalendarSource? {
        viewModel.calendarSource(id: calendarID)
    }

    private var selectedColorHex: String? {
        guard let calendar else { return nil }
        return calendar.colorOverrideHex ?? calendar.colorHex
    }
}

private extension CalendarProviderKind {
    var title: String {
        switch self {
        case .iCloud:
            return "iCloud"
        case .google:
            return "Google"
        }
    }
}
