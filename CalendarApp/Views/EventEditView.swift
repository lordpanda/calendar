import SwiftUI
import MapKit

struct EventEditView: View {
    struct EventContext: Identifiable {
        enum Mode {
            case create(seedDate: Date)
            case edit(CalendarEvent)
        }

        let mode: Mode
        let id: String

        static func create(seedDate: Date) -> EventContext {
            EventContext(mode: .create(seedDate: seedDate), id: "create-\(seedDate.timeIntervalSinceReferenceDate)")
        }

        static func edit(_ event: CalendarEvent) -> EventContext {
            EventContext(mode: .edit(event), id: "edit-\(event.id)")
        }
    }

    struct Draft {
        var title = ""
        var location = ""
        var notes = ""
        var startDate: Date
        var endDate: Date
        var isAllDay = false
        var calendarID: String
        var repeatOption: EventRepeatOption = .never
        var invitees: [String] = []
        var attachmentURL = ""
        var alertOption: EventAlertOption = .none
        var visibility: EventVisibilityOption = .default
        var availability: EventAvailabilityOption = .busy
    }

    enum Mode {
        case create
        case edit(eventID: String)
    }

    private enum PickerFocus: Equatable {
        case startDate, startTime, endDate, endTime
    }

    private enum FocusField: Hashable {
        case title
    }

    let mode: Mode
    let calendars: [CalendarSource]
    let onSave: (Draft) async -> Bool
    let onDelete: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft
    @State private var isSaving = false
    @State private var expandedPicker: PickerFocus?
    @State private var isMapSearchPresented = false
    @State private var isInviteesPresented = false
    @State private var isAttachmentPresented = false
    @State private var isCustomRepeatPresented = false
    @FocusState private var focusedField: FocusField?

    init(
        mode: Mode,
        calendars: [CalendarSource],
        preferredCalendarID: String? = nil,
        seedDate: Date? = nil,
        existingEvent: CalendarEvent? = nil,
        onSave: @escaping (Draft) async -> Bool,
        onDelete: (() async -> Bool)? = nil
    ) {
        self.mode = mode
        self.calendars = calendars
        self.onSave = onSave
        self.onDelete = onDelete

        if let existingEvent {
            _draft = State(initialValue: Draft(
                title: existingEvent.title,
                location: existingEvent.location ?? "",
                notes: existingEvent.notes ?? "",
                startDate: existingEvent.startDate,
                endDate: existingEvent.endDate,
                isAllDay: existingEvent.isAllDay,
                calendarID: existingEvent.calendarID,
                repeatOption: existingEvent.repeatOption,
                invitees: existingEvent.invitees,
                attachmentURL: existingEvent.attachmentURL ?? "",
                alertOption: existingEvent.alertOption,
                visibility: existingEvent.visibility,
                availability: existingEvent.availability
            ))
        } else {
            let start = Self.defaultStartDate(seedDate: seedDate)
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
            let defaultID = calendars.first(where: { $0.id == preferredCalendarID })?.id ?? calendars.first?.id ?? ""
            _draft = State(initialValue: Draft(startDate: start, endDate: end, calendarID: defaultID))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    titleCard
                    scheduleCard
                    calendarSection
                    detailsCard
                    alertCard
                    if onDelete != nil {
                        deleteCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                focusTitleIfNeeded()
            }
            .sheet(isPresented: $isMapSearchPresented) {
                LocationSearchView { location in
                    draft.location = location
                    isMapSearchPresented = false
                }
            }
            .sheet(isPresented: $isInviteesPresented) {
                InviteesEditView(invitees: $draft.invitees)
            }
            .sheet(isPresented: $isAttachmentPresented) {
                AttachmentEditView(attachmentURL: $draft.attachmentURL)
            }
            .fullScreenCover(isPresented: $isCustomRepeatPresented) {
                CustomRepeatEditView(selection: $draft.repeatOption)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        Task {
                            isSaving = true
                            let saved = await onSave(draft)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving || draft.calendarID.isEmpty || !selectedCalendarIsWritable)
                }
            }
        }
    }

    // MARK: - Section Views

    private var titleCard: some View {
        TextField("Title", text: $draft.title)
            .font(.system(size: 28, weight: .bold))
            .focused($focusedField, equals: .title)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var scheduleCard: some View {
        VStack(spacing: 0) {
            EventRow {
                Toggle("All-day", isOn: $draft.isAllDay)
                    .onChange(of: draft.isAllDay) { _, _ in
                        expandedPicker = nil
                    }
            }

            EventDivider()

            VStack(spacing: 0) {
                dateTimeRow(date: $draft.startDate, dateFocus: .startDate, timeFocus: .startTime)

                expandedDatePicker(for: $draft.startDate, dateFocus: .startDate, timeFocus: .startTime)
            }

            EventDivider()

            VStack(spacing: 0) {
                dateTimeRow(date: $draft.endDate, dateFocus: .endDate, timeFocus: .endTime)

                expandedDatePicker(for: $draft.endDate, dateFocus: .endDate, timeFocus: .endTime)
            }

            EventDivider()

            repeatRow
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var calendarSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if calendars.isEmpty {
                        Text("No writable calendars")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(calendars) { cal in
                            Button {
                                if cal.isWritable { draft.calendarID = cal.id }
                            } label: {
                                CalendarChip(calendar: cal, isSelected: draft.calendarID == cal.id)
                            }
                            .buttonStyle(.plain)
                            .disabled(!cal.isWritable)
                            .id(cal.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                scrollToSelectedCalendar(with: proxy, animated: false)
            }
            .onChange(of: draft.calendarID) { _, _ in
                scrollToSelectedCalendar(with: proxy, animated: true)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            EventRow {
                TextField("Location", text: $draft.location)
                Button("Map") {
                    isMapSearchPresented = true
                }
                    .foregroundStyle(.blue)
            }

            EventDivider()

            EventRow {
                Text("Video Call")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Add") {}
                    .foregroundStyle(.blue)
            }

            EventDivider()

            Button {
                isInviteesPresented = true
            } label: {
                EventRow {
                    Text("Invitees")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(draft.invitees.isEmpty ? "None" : "\(draft.invitees.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            EventDivider()

            Button {
                isAttachmentPresented = true
            } label: {
                EventRow {
                    Text("Attachment")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(draft.attachmentURL.isEmpty ? "None" : "1")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var repeatRow: some View {
        EventRow {
            Text("Repeat")
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(EventRepeatOption.presetOptions) { option in
                    Button(option.title) {
                        draft.repeatOption = option
                    }
                }

                Divider()

                Button("Custom...") {
                    isCustomRepeatPresented = true
                }
            } label: {
                HStack(spacing: 5) {
                    Text(draft.repeatOption.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var alertCard: some View {
        VStack(spacing: 0) {
            pickerRow("Alert", selection: $draft.alertOption, values: EventAlertOption.allCases)

            EventDivider()

            pickerRow("Visibility", selection: $draft.visibility, values: EventVisibilityOption.allCases)

            EventDivider()

            pickerRow("Show As", selection: $draft.availability, values: EventAvailabilityOption.allCases)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            Task {
                guard let onDelete else { return }
                isSaving = true
                let deleted = await onDelete()
                isSaving = false
                if deleted { dismiss() }
            }
        } label: {
            Text("Delete Event")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .disabled(isSaving)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    // MARK: - Helper Views

    private func dateTimeRow(date: Binding<Date>, dateFocus: PickerFocus, timeFocus: PickerFocus) -> some View {
        EventRow {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    expandedPicker = expandedPicker == dateFocus ? nil : dateFocus
                }
            } label: {
                Text(date.wrappedValue, format: .dateTime.weekday(.wide).month().day())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !draft.isAllDay {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        expandedPicker = expandedPicker == timeFocus ? nil : timeFocus
                    }
                } label: {
                    Text(date.wrappedValue, format: .dateTime.hour().minute())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(expandedPicker == timeFocus ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func expandedDatePicker(
        for date: Binding<Date>,
        dateFocus: PickerFocus,
        timeFocus: PickerFocus
    ) -> some View {
        if expandedPicker == dateFocus {
            DatePicker("", selection: dateSelectionBinding(for: dateFocus), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if expandedPicker == timeFocus {
            DatePicker("", selection: timeSelectionBinding(for: timeFocus), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func dateSelectionBinding(for focus: PickerFocus) -> Binding<Date> {
        Binding {
            switch focus {
            case .startDate:
                return draft.startDate
            case .endDate:
                return draft.endDate
            case .startTime:
                return draft.startDate
            case .endTime:
                return draft.endDate
            }
        } set: { newDate in
            switch focus {
            case .startDate:
                shiftStartDate(to: newDate)
                withAnimation(.spring(duration: 0.3)) {
                    expandedPicker = draft.isAllDay ? .endDate : .startTime
                }
            case .endDate:
                draft.endDate = newDate
                withAnimation(.spring(duration: 0.3)) {
                    expandedPicker = nil
                }
            case .startTime, .endTime:
                break
            }
        }
    }

    private func timeSelectionBinding(for focus: PickerFocus) -> Binding<Date> {
        Binding {
            switch focus {
            case .startDate, .startTime:
                return draft.startDate
            case .endDate, .endTime:
                return draft.endDate
            }
        } set: { newDate in
            switch focus {
            case .startTime:
                shiftStartDate(to: newDate)
            case .endTime:
                draft.endDate = newDate
            case .startDate, .endDate:
                break
            }
        }
    }

    private func shiftStartDate(to newDate: Date) {
        let delta = newDate.timeIntervalSince(draft.startDate)
        draft.startDate = newDate
        draft.endDate = draft.endDate.addingTimeInterval(delta)
    }

    private func pickerRow<Option: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Option>,
        values: Option.AllCases
    ) -> some View where Option: Equatable, Option.AllCases: RandomAccessCollection, Option.AllCases.Element == Option {
        EventRow {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(values) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func optionTitle<Option>(_ option: Option) -> String {
        switch option {
        case let option as EventAlertOption:
            return option.title
        case let option as EventVisibilityOption:
            return option.title
        case let option as EventAvailabilityOption:
            return option.title
        default:
            return String(describing: option)
        }
    }

    // MARK: - Computed Properties

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Event"
        case .edit: return "Edit Event"
        }
    }

    private var confirmButtonTitle: String {
        switch mode {
        case .create: return "Add"
        case .edit: return "Save"
        }
    }

    private var selectedCalendarIsWritable: Bool {
        calendars.first(where: { $0.id == draft.calendarID })?.isWritable == true
    }

    private func scrollToSelectedCalendar(with proxy: ScrollViewProxy, animated: Bool) {
        guard calendars.contains(where: { $0.id == draft.calendarID }) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if animated {
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(draft.calendarID, anchor: .center)
                }
            } else {
                proxy.scrollTo(draft.calendarID, anchor: .center)
            }
        }
    }

    private func focusTitleIfNeeded() {
        guard case .create = mode else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            focusedField = .title
        }
    }

    private func hideKeyboard() {
        focusedField = nil
    }

    private static func defaultStartDate(seedDate: Date?) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.minute, .second, .nanosecond], from: now)
        let minute = nowComponents.minute ?? 0
        let second = nowComponents.second ?? 0
        let nanosecond = nowComponents.nanosecond ?? 0
        let shouldAdvanceHour = minute > 0 || second > 0 || nanosecond > 0
        let roundedNow = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let roundedHour = shouldAdvanceHour
            ? (calendar.date(byAdding: .hour, value: 1, to: roundedNow) ?? roundedNow)
            : roundedNow

        guard let seedDate else {
            return roundedHour
        }

        let time = calendar.dateComponents([.hour, .minute], from: roundedHour)
        var day = calendar.dateComponents([.year, .month, .day], from: seedDate)
        day.hour = time.hour
        day.minute = time.minute
        return calendar.date(from: day) ?? seedDate
    }
}

// MARK: - Sub-components

private struct EventRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.body)
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }
}

private struct EventDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

private struct CalendarChip: View {
    let calendar: CalendarSource
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSelected ? Color.white : calendar.displayColor)
                .frame(width: 9, height: 9)
            Text(calendar.displayTitle)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? Color.white : Color(.label))
        .background(isSelected ? calendar.displayColor : Color(.systemBackground))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(isSelected ? Color.clear : Color(.separator).opacity(0.5), lineWidth: 1)
        }
    }
}

private struct CustomRepeatEditView: View {
    @Binding var selection: EventRepeatOption
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var customRule: CustomRepeatRule
    @State private var showsEveryPicker = false

    init(selection: Binding<EventRepeatOption>) {
        _selection = selection
        if case .custom(let rule) = selection.wrappedValue {
            _customRule = State(initialValue: rule)
        } else {
            _customRule = State(initialValue: CustomRepeatRule())
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    roundedCard {
                        VStack(spacing: 0) {
                            frequencyRow
                            Divider().padding(.leading, 20)
                            everyRow
                            if showsEveryPicker {
                                Divider().padding(.leading, 20)
                                everyPicker
                                    .padding(.top, 8)
                                    .padding(.bottom, 14)
                            }
                        }
                    }

                    Text(summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)

                    switch customRule.frequency {
                    case .daily:
                        EmptyView()
                    case .weekly:
                        weeklySection
                    case .monthly:
                        monthlySection
                    case .yearly:
                        yearlySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Custom Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selection = .custom(customRule)
                        dismiss()
                    }
                }
            }
        }
    }

    private var frequencyRow: some View {
        HStack {
            Text("Frequency")
            Spacer()
            Picker("Frequency", selection: $customRule.frequency) {
                ForEach(EventRepeatFrequency.allCases) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var everyRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsEveryPicker.toggle()
            }
        } label: {
            HStack {
                Text("Every")
                Spacer()
                Text(customIntervalTitle)
                    .foregroundStyle(showsEveryPicker ? Color.accentColor : .primary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var everyPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $customRule.interval) {
                ForEach(1..<100, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Picker("", selection: $customRule.frequency) {
                ForEach(EventRepeatFrequency.allCases) { option in
                    Text(option.intervalUnitTitle(interval: customRule.interval)).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .frame(height: 150)
    }

    private var weeklySection: some View {
        roundedCard {
            VStack(spacing: 0) {
                ForEach(Array(weekdayRows.enumerated()), id: \.element.id) { index, item in
                    Button {
                        toggleWeekday(item.id)
                    } label: {
                        optionRow(title: item.name, isSelected: selectedWeekdays.contains(item.id))
                    }
                    .buttonStyle(.plain)
                    if index < weekdayRows.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private var monthlySection: some View {
        roundedCard {
            VStack(spacing: 0) {
                monthlyModeRow(title: "Each", mode: .eachDate)
                Divider().padding(.leading, 20)
                monthlyModeRow(title: "On the...", mode: .nthWeekday)
                Divider()
                if customRule.monthlyPattern == .eachDate {
                    monthDaysGrid.padding(.top, 2)
                } else {
                    nthSelectorPicker.padding(.top, 8).padding(.bottom, 14)
                }
            }
        }
    }

    private var yearlySection: some View {
        VStack(spacing: 14) {
            roundedCard { monthGrid }
            roundedCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Days of Week")
                        Spacer()
                        Toggle("", isOn: $customRule.yearlyUsesWeekdays)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)

                    if customRule.yearlyUsesWeekdays {
                        Divider().padding(.leading, 20)
                        nthSelectorPicker.padding(.top, 8).padding(.bottom, 14)
                    }
                }
            }
        }
    }

    private func monthlyModeRow(title: String, mode: CustomRepeatMonthlyPattern) -> some View {
        Button {
            customRule.monthlyPattern = mode
        } label: {
            optionRow(title: title, isSelected: customRule.monthlyPattern == mode)
        }
        .buttonStyle(.plain)
    }

    private var monthDaysGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(1...31, id: \.self) { day in
                Button {
                    toggleMonthDay(day)
                } label: {
                    Text("\(day)")
                        .font(.title3)
                        .foregroundStyle(selectedMonthDays.contains(day) ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(selectedMonthDays.contains(day) ? Color.accentColor : Color.clear)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(Color(.separator).opacity(0.4)).frame(height: 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5)
                }
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
            ForEach(monthRows, id: \.id) { month in
                Button {
                    toggleMonth(month.id)
                } label: {
                    Text(month.name)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedMonths.contains(month.id) ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(selectedMonths.contains(month.id) ? Color.accentColor.opacity(0.9) : Color.clear)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(Color(.separator).opacity(0.4)).frame(height: 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5)
                }
            }
        }
    }

    private var nthSelectorPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $customRule.weekdayOrdinal) {
                ForEach(CustomRepeatWeekdayOrdinal.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Picker("", selection: $customRule.nthDaySelector) {
                ForEach(CustomRepeatNthDaySelector.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .frame(height: 150)
    }

    private func roundedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func optionRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var customIntervalTitle: String {
        let interval = max(1, customRule.interval)
        if interval == 1 {
            return customRule.frequency.intervalUnitTitle(interval: interval)
        }
        return "\(interval) \(customRule.frequency.pluralTitle)"
    }

    private var summaryText: String {
        customRule.frequency.summarySentence(interval: customRule.interval)
    }

    private var selectedWeekdays: [Int] {
        customRule.weekdays.isEmpty ? [Calendar.current.component(.weekday, from: Date())] : customRule.weekdays
    }

    private var selectedMonthDays: [Int] {
        customRule.monthDays.isEmpty ? [Calendar.current.component(.day, from: Date())] : customRule.monthDays
    }

    private var selectedMonths: [Int] {
        customRule.months.isEmpty ? [Calendar.current.component(.month, from: Date())] : customRule.months
    }

    private var weekdayRows: [(id: Int, name: String)] {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.weekdaySymbols.enumerated().map { (id: $0.offset + 1, name: $0.element) }
    }

    private var monthRows: [(id: Int, name: String)] {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.shortMonthSymbols.enumerated().map { (id: $0.offset + 1, name: $0.element) }
    }

    private func toggleWeekday(_ weekday: Int) {
        var values = Set(selectedWeekdays)
        if values.contains(weekday), values.count > 1 {
            values.remove(weekday)
        } else {
            values.insert(weekday)
        }
        customRule.weekdays = values.sorted()
    }

    private func toggleMonthDay(_ day: Int) {
        var values = Set(selectedMonthDays)
        if values.contains(day), values.count > 1 {
            values.remove(day)
        } else {
            values.insert(day)
        }
        customRule.monthDays = values.sorted()
    }

    private func toggleMonth(_ month: Int) {
        var values = Set(selectedMonths)
        if values.contains(month), values.count > 1 {
            values.remove(month)
        } else {
            values.insert(month)
        }
        customRule.months = values.sorted()
    }
}

private struct LocationSearchView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = LocationSearchModel()

    var body: some View {
        NavigationStack {
            List(search.results) { result in
                Button {
                    onSelect(result.displayText)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .navigationTitle("Location")
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search maps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LocationSearchResult: Identifiable, Hashable {
    let title: String
    let subtitle: String

    var id: String { "\(title)\n\(subtitle)" }
    var displayText: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

@MainActor
private final class LocationSearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            search()
        }
    }
    @Published var results: [LocationSearchResult] = []

    private var searchTask: Task<Void, Never>?

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !term.isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.resultTypes = [.address, .pointOfInterest]

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems.map { item in
                    LocationSearchResult(
                        title: item.name ?? term,
                        subtitle: item.placemark.title ?? ""
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }
        }
    }
}

private struct InviteesEditView: View {
    @Binding var invitees: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("email@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        Button("Add") {
                            addInvitee()
                        }
                        .disabled(normalizedEmail.isEmpty)
                    }
                }

                Section("Invitees") {
                    if invitees.isEmpty {
                        Text("No invitees")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(invitees, id: \.self) { invitee in
                            Text(invitee)
                        }
                        .onDelete { indices in
                            invitees.remove(atOffsets: indices)
                        }
                    }
                }
            }
            .navigationTitle("Invitees")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addInvitee() {
        let value = normalizedEmail
        guard !value.isEmpty, !invitees.contains(value) else { return }
        invitees.append(value)
        email = ""
    }
}

private struct AttachmentEditView: View {
    @Binding var attachmentURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $attachmentURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    Text("Use a web or file URL. Providers may reject attachments they cannot access.")
                }

                if !attachmentURL.isEmpty {
                    Section {
                        Button("Remove Attachment", role: .destructive) {
                            attachmentURL = ""
                        }
                    }
                }
            }
            .navigationTitle("Attachment")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
