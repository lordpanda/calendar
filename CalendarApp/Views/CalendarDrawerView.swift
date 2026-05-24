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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection(title: L.tr("Accounts & Sync", language: language)) {
                    accountToggleRow(
                        title: L.tr("Apple", language: language),
                        subtitle: iCloudStatusText,
                        isOn: Binding(
                            get: { isICloudConnected },
                            set: { setICloudConnected($0) }
                        ),
                        isLoading: viewModel.isICloudSyncInProgress,
                        isDisabled: viewModel.isICloudSyncInProgress
                    )

                    settingsDivider

                    accountToggleRow(
                        title: "Google",
                        subtitle: googleStatusText,
                        isOn: Binding(
                            get: { viewModel.googleAuthState.isSignedIn },
                            set: { setGoogleConnected($0) }
                        ),
                        isLoading: viewModel.isGoogleSyncInProgress,
                        isDisabled: viewModel.googleAuthState.isUnavailable || viewModel.isGoogleSyncInProgress
                    )
                }

                settingsSection(title: L.tr("Calendar Appearance", language: language)) {
                    menuRow(
                        title: L.tr("Language", language: language),
                        value: viewModel.settings.language.title(language: language)
                    ) {
                        ForEach(AppLanguage.allCases) { option in
                            Button(option.title(language: language)) {
                                viewModel.setLanguage(option)
                            }
                        }
                    }

                    settingsDivider

                    menuRow(
                        title: L.tr("Start of Week", language: language),
                        value: viewModel.settings.startOfWeek.title(language: language)
                    ) {
                        ForEach(StartOfWeekOption.allCases) { option in
                            Button(option.title(language: language)) {
                                viewModel.setStartOfWeek(option)
                            }
                        }
                    }

                    settingsDivider

                    settingsToggleRow(
                        title: L.tr("Show Week Numbers", language: language),
                        isOn: Binding(
                            get: { viewModel.settings.showsWeekNumbers },
                            set: { viewModel.setShowsWeekNumbers($0) }
                        )
                    )

                    settingsDivider

                    settingsToggleRow(
                        title: L.tr("Show Completed Tasks", language: language),
                        isOn: Binding(
                            get: { viewModel.settings.showsCompletedTasks },
                            set: { viewModel.setShowsCompletedTasks($0) }
                        )
                    )

                    settingsDivider

                    menuRow(
                        title: L.tr("Main View Font Size", language: language),
                        value: viewModel.settings.monthContentScale.title
                    ) {
                        ForEach(MonthContentScale.allCases) { option in
                            Button(option.title) {
                                viewModel.setMonthContentScale(option)
                            }
                        }
                    }
                }

                settingsSection {
                    settingsToggleRow(
                        title: L.tr("Use Device Time Zone", language: language),
                        isOn: Binding(
                            get: { viewModel.settings.usesDeviceTimeZone },
                            set: { viewModel.setUsesDeviceTimeZone($0) }
                        )
                    )

                    settingsDivider

                    HStack(spacing: 8) {
                        Text(timeZoneDisplayName)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.tr("Back", language: language))
            }

            ToolbarItem(placement: .principal) {
                Text(L.tr("Settings", language: language))
                    .font(.headline)
            }
        }
        .onAppear {
            viewModel.refreshCalendarAccessState()
        }
    }

    private var isICloudConnected: Bool {
        viewModel.settings.isICloudSyncEnabled && viewModel.accessState == .granted
    }

    private var iCloudStatusText: String {
        guard isICloudConnected else {
            return L.tr("Not connected", language: language)
        }
        return viewModel.iCloudCalendarCount == 0
            ? viewModel.statusMessage
            : L.tr("Last sync: %@", language: language, viewModel.lastICloudSyncDescription)
    }

    private var googleStatusText: String {
        switch viewModel.googleAuthState {
        case .signedOut:
            return L.tr("Not connected", language: language)
        case .signedIn(let email):
            return email
        case .unavailable(let message):
            return message
        }
    }

    private var timeZoneDisplayName: String {
        let timeZone = TimeZone.autoupdatingCurrent
        return timeZone.localizedName(for: .standard, locale: language.locale) ?? timeZone.identifier
    }

    private func setICloudConnected(_ isConnected: Bool) {
        if isConnected {
            Task {
                await viewModel.refreshICloudNow()
            }
        } else {
            viewModel.disconnectICloud()
        }
    }

    private func setGoogleConnected(_ isConnected: Bool) {
        if isConnected {
            onConnectGoogle()
        } else {
            Task {
                await viewModel.disconnectGoogle()
            }
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color(.separator))
            .padding(.horizontal, 16)
    }

    private func accountToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isLoading: Bool,
        isDisabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color(red: 0.0, green: 0.77, blue: 0.68))
                    .disabled(isDisabled)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 18, height: 31)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.0, green: 0.77, blue: 0.68))
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }

    private func menuRow<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16)

            Menu {
                content()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CalendarEditView: View {
    @Bindable var viewModel: CalendarViewModel
    let calendarID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var draftName = ""
    @State private var customColor = Color.accentColor

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 48), spacing: 12)]
    private let palette = CalendarColorPalette.swatches

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
                                Text(calendar.provider.title(language: language))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Section {
                        TextField(L.tr("Display Name", language: language), text: $draftName)
                            .textInputAutocapitalization(.never)

                        Button(L.tr("Reset to Original Name", language: language)) {
                            draftName = calendar.title
                            viewModel.setCalendarTitleOverride(calendarID: calendarID, title: nil)
                        }
                        .disabled(calendar.titleOverride == nil)
                    } header: {
                        Text(L.tr("Name", language: language))
                    } footer: {
                        Text(L.tr("Original name: %@", language: language, calendar.title))
                    }

                    Section {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(palette) { swatch in
                                Button {
                                    viewModel.setCalendarColorOverride(calendarID: calendarID, colorHex: swatch.hex)
                                    customColor = swatch.color
                                } label: {
                                    Circle()
                                        .fill(swatch.color)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Circle()
                                                .stroke(selectedColorHex == swatch.hex ? Color.primary : Color.clear, lineWidth: 2)
                                        }
                                        .overlay {
                                            if selectedColorHex == swatch.hex {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L.tr("Select %@", language: language, swatch.name(language: language)))
                            }
                        }
                        .padding(.vertical, 6)

                        ColorPicker(L.tr("Custom Color", language: language), selection: Binding(
                            get: { customColor },
                            set: { color in
                                customColor = color
                                if let hex = color.hexString {
                                    viewModel.setCalendarColorOverride(calendarID: calendarID, colorHex: hex)
                                }
                            }
                        ), supportsOpacity: false)

                        Button(L.tr("Reset to Original Color", language: language), role: .destructive) {
                            viewModel.setCalendarColorOverride(calendarID: calendarID, colorHex: nil)
                        }
                        .disabled(calendar.colorOverrideHex == nil)
                    } header: {
                        Text(L.tr("Color", language: language))
                    }
                }
            }
            .navigationTitle(L.tr("Edit Calendar", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.tr("Cancel", language: language)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.tr("Done", language: language)) {
                        viewModel.setCalendarTitleOverride(calendarID: calendarID, title: draftName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draftName = calendar?.displayTitle ?? ""
                customColor = calendar?.displayColor ?? .accentColor
            }
        }
    }

    private var calendar: CalendarSource? {
        viewModel.calendarSource(id: calendarID)
    }

    private var selectedColorHex: String? {
        guard let calendar else { return nil }
        return (calendar.colorOverrideHex ?? calendar.colorHex).uppercased()
    }
}

private struct CalendarColorSwatch: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) ?? .accentColor }
    func name(language: AppLanguage) -> String {
        L.tr(name, language: language)
    }
}

private enum CalendarColorPalette {
    static let swatches: [CalendarColorSwatch] = [
        .init(name: "Red", hex: "FF3B30"),
        .init(name: "Orange", hex: "FF9500"),
        .init(name: "Yellow", hex: "FFCC00"),
        .init(name: "Green", hex: "34C759"),
        .init(name: "Mint", hex: "00C7BE"),
        .init(name: "Teal", hex: "30B0C7"),
        .init(name: "Cyan", hex: "32ADE6"),
        .init(name: "Blue", hex: "007AFF"),
        .init(name: "Indigo", hex: "5856D6"),
        .init(name: "Purple", hex: "AF52DE"),
        .init(name: "Pink", hex: "FF2D55"),
        .init(name: "Brown", hex: "A2845E"),
        .init(name: "Gray", hex: "8E8E93"),
        .init(name: "Dark Gray", hex: "636366"),
        .init(name: "Light Red", hex: "FF6961"),
        .init(name: "Coral", hex: "FF7A59"),
        .init(name: "Amber", hex: "FFB340"),
        .init(name: "Gold", hex: "D9A300"),
        .init(name: "Lime", hex: "7ED957"),
        .init(name: "Emerald", hex: "2ECC71"),
        .init(name: "Sea Green", hex: "16A085"),
        .init(name: "Sky", hex: "64D2FF"),
        .init(name: "Steel Blue", hex: "2980B9"),
        .init(name: "Navy", hex: "0A84FF"),
        .init(name: "Lavender", hex: "BF5AF2"),
        .init(name: "Violet", hex: "6C5CE7"),
        .init(name: "Rose", hex: "FF375F"),
        .init(name: "Magenta", hex: "DA70D6"),
        .init(name: "Terracotta", hex: "D35400"),
        .init(name: "Brick", hex: "C0392B")
    ]
}

private extension Color {
    var hexString: String? {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

private extension CalendarProviderKind {
    func title(language: AppLanguage) -> String {
        switch self {
        case .iCloud:
            return L.tr("Apple", language: language)
        case .google:
            return "Google"
        }
    }
}
