import SwiftUI
import MapKit

struct EventEditView: View {

    let mode: Mode
    let calendars: [CalendarSource]
    let onSave: (Draft, RecurringEventEditScope) async -> Bool
    let onDelete: ((RecurringEventDeleteScope) async -> Bool)?
    let onToggleTaskCompletion: (() async -> Bool)?
    private let editsRecurringEvent: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var draft: Draft
    @State private var itemKind: CalendarItemKind
    @State private var isSaving = false
    @State private var pendingRecurringAction: PendingRecurringAction?
    @State private var expandedPicker: PickerFocus?
    @State private var isMapSearchPresented = false
    @State private var isVideoCallPresented = false
    @State private var isInviteesPresented = false
    @State private var isAttachmentPresented = false
    @State private var isCustomRepeatPresented = false
    @State private var isDetailsExpanded = false
    @FocusState private var focusedField: FocusField?

    init(
        mode: Mode,
        calendars: [CalendarSource],
        preferredCalendarID: String? = nil,
        seedDate: Date? = nil,
        existingEvent: CalendarEvent? = nil,
        onSave: @escaping (Draft, RecurringEventEditScope) async -> Bool,
        onDelete: ((RecurringEventDeleteScope) async -> Bool)? = nil,
        onToggleTaskCompletion: (() async -> Bool)? = nil
    ) {
        self.mode = mode
        self.calendars = calendars
        self.onSave = onSave
        self.onDelete = onDelete
        self.onToggleTaskCompletion = onToggleTaskCompletion
        self.editsRecurringEvent = existingEvent?.isRecurring == true
        _itemKind = State(initialValue: existingEvent?.kind ?? .event)

        if let existingEvent {
            _draft = State(initialValue: Draft(
                title: existingEvent.title,
                location: existingEvent.location ?? "",
                notes: Draft.userNotes(from: existingEvent.notes),
                startDate: existingEvent.startDate,
                endDate: existingEvent.endDate,
                isAllDay: existingEvent.isAllDay,
                calendarID: existingEvent.calendarID,
                repeatOption: existingEvent.repeatOption,
                invitees: existingEvent.invitees,
                attachmentURL: existingEvent.attachmentURL ?? "",
                videoCallURL: Draft.videoCallURL(from: existingEvent.notes),
                alertOption: existingEvent.alertOption,
                visibility: existingEvent.visibility,
                availability: existingEvent.availability,
                isCompleted: existingEvent.isCompleted,
                kind: existingEvent.kind
            ))
        } else {
            let start = Self.defaultStartDate(seedDate: seedDate)
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
            let defaultID = calendars.first(where: { $0.id == preferredCalendarID })?.id
                ?? calendars.first(where: { $0.kind == .event })?.id
                ?? calendars.first?.id
                ?? ""
            _draft = State(initialValue: Draft(startDate: start, endDate: end, calendarID: defaultID))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    titleCard
                    scheduleCard
                    if !isTask {
                        calendarSection
                        detailsCard
                    } else {
                        taskNotesCard
                    }
                    if onDelete != nil {
                        deleteCard
                    }
                    if isTask, onToggleTaskCompletion != nil {
                        taskCompletionCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                if case .create = mode {
                    Button {
                        setItemKind(.event)
                    } label: {
                        Label(L.tr("Event", language: language), systemImage: itemKind == .event ? "checkmark" : "calendar")
                    }

                    Button {
                        setItemKind(.reminder)
                    } label: {
                        Label(L.tr("Task", language: language), systemImage: itemKind == .reminder ? "checkmark" : "checkmark.circle")
                    }
                }
            }
            .onAppear {
                focusTitleIfNeeded()
            }
            .sheet(isPresented: $isMapSearchPresented) {
                LocationSearchView { location in
                    draft.location = location
                    isMapSearchPresented = false
                }
            }
            .sheet(isPresented: $isVideoCallPresented) {
                VideoCallEditView(videoCallURL: $draft.videoCallURL)
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
            .confirmationDialog(
                recurringDialogTitle,
                isPresented: Binding(
                    get: { pendingRecurringAction != nil },
                    set: { if !$0 { pendingRecurringAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                recurringDialogActions
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        requestSave()
                    }
                    .disabled(isSaving || draft.calendarID.isEmpty || (!isTask && !selectedCalendarIsWritable))
                    .foregroundStyle(.primary)
                    .tint(.primary)
                }
            }
        }
    }

    // MARK: - Section Views

    private var titleCard: some View {
        TextField(L.tr("Title", language: language), text: $draft.title, axis: .vertical)
            .font(.system(size: 28, weight: .bold))
            .lineLimit(1...4)
            .focused($focusedField, equals: .title)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var scheduleCard: some View {
        VStack(spacing: 0) {
            EventRow {
                Toggle(L.tr("All-day", language: language), isOn: $draft.isAllDay)
                    .onChange(of: draft.isAllDay) { _, _ in
                        expandedPicker = nil
                    }
            }
            .zIndex(3)

            EventDivider()
                .zIndex(3)

            VStack(spacing: 0) {
                dateTimeRow(date: $draft.startDate, dateFocus: .startDate, timeFocus: .startTime)
                    .zIndex(2)

                expandedDatePicker(for: $draft.startDate, dateFocus: .startDate, timeFocus: .startTime)
                    .zIndex(0)
            }
            .zIndex(2)

            if !isTask {
                EventDivider()
                    .zIndex(2)

                VStack(spacing: 0) {
                    dateTimeRow(date: $draft.endDate, dateFocus: .endDate, timeFocus: .endTime)
                        .zIndex(1)

                    expandedDatePicker(for: $draft.endDate, dateFocus: .endDate, timeFocus: .endTime)
                        .zIndex(0)
                }
                .zIndex(1)

                EventDivider()
                    .zIndex(1)

                repeatRow
                    .zIndex(1)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var calendarSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if selectableCalendars.isEmpty {
                        Text(L.tr("No writable calendars", language: language))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(selectableCalendars) { cal in
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
                TextField(L.tr("Location", language: language), text: $draft.location, axis: .vertical)
                    .lineLimit(1...3)

                Button(L.tr("Map", language: language)) {
                    isMapSearchPresented = true
                }
                    .foregroundStyle(.blue)
            }

            EventDivider()

            Button {
                withAnimation(.spring(duration: 0.25)) {
                    isDetailsExpanded.toggle()
                }
            } label: {
                EventRow {
                    Text(L.tr("Details", language: language))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isDetailsExpanded {
                Group {
                    EventDivider()

                    Button {
                        isVideoCallPresented = true
                    } label: {
                        EventRow {
                            Text(L.tr("Video Call", language: language))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(videoCallSummary)
                                .foregroundStyle(draft.videoCallURL.isEmpty ? .blue : .secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    EventDivider()

                    Button {
                        isInviteesPresented = true
                    } label: {
                        EventRow {
                            Text(L.tr("Invitees", language: language))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(draft.invitees.isEmpty ? L.tr("None", language: language) : "\(draft.invitees.count)")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
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
                            Text(L.tr("Attachment", language: language))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(draft.attachmentURL.isEmpty ? L.tr("None", language: language) : "1")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    EventDivider()

                    pickerRow(L.tr("Alert", language: language), selection: $draft.alertOption, values: EventAlertOption.allCases)

                    EventDivider()

                    pickerRow(L.tr("Visibility", language: language), selection: $draft.visibility, values: EventVisibilityOption.allCases)

                    EventDivider()

                    pickerRow(L.tr("Show As", language: language), selection: $draft.availability, values: EventAvailabilityOption.allCases)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var taskNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.tr("Notes", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft.notes)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var repeatRow: some View {
        EventRow {
            Text(L.tr("Repeat", language: language))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Menu {
                ForEach(EventRepeatOption.presetOptions) { option in
                    Button(option.title(language: language)) {
                        draft.repeatOption = option
                    }
                }

                Divider()

                Button(L.tr("Custom...", language: language)) {
                    isCustomRepeatPresented = true
                }
            } label: {
                menuValueLabel(draft.repeatOption.title(language: language))
            }
            .tint(.secondary)
        }
    }

    private var alertCard: some View {
        VStack(spacing: 0) {
            pickerRow(L.tr("Alert", language: language), selection: $draft.alertOption, values: EventAlertOption.allCases)

            EventDivider()

            pickerRow(L.tr("Visibility", language: language), selection: $draft.visibility, values: EventVisibilityOption.allCases)

            EventDivider()

            pickerRow(L.tr("Show As", language: language), selection: $draft.availability, values: EventAvailabilityOption.allCases)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            requestDelete()
        } label: {
            Text(isTask ? L.tr("Delete Task", language: language) : L.tr("Delete Event", language: language))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .disabled(isSaving)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    private var taskCompletionCard: some View {
        Button {
            Task {
                guard let onToggleTaskCompletion else { return }
                isSaving = true
                let updated = await onToggleTaskCompletion()
                isSaving = false
                if updated { dismiss() }
            }
        } label: {
            Text(draft.isCompleted ? L.tr("Mark Uncompleted", language: language) : L.tr("Mark Completed", language: language))
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
                    .fixedSize(horizontal: false, vertical: true)
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
                        .lineLimit(1)
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
                .background(Color(.systemBackground))
                .clipped()
                .transition(.move(edge: .top))
        } else if expandedPicker == timeFocus {
            DatePicker("", selection: timeSelectionBinding(for: timeFocus), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .background(Color(.systemBackground))
                .clipped()
                .transition(.move(edge: .top))
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
                .fixedSize(horizontal: false, vertical: true)

            Menu {
                ForEach(values) { option in
                    Button(optionTitle(option)) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                menuValueLabel(optionTitle(selection.wrappedValue))
            }
            .tint(.secondary)
        }
    }

    private func menuValueLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }

    private func optionTitle<Option>(_ option: Option) -> String {
        switch option {
        case let option as EventAlertOption:
            return option.title(language: language)
        case let option as EventVisibilityOption:
            return option.title(language: language)
        case let option as EventAvailabilityOption:
            return option.title(language: language)
        default:
            return String(describing: option)
        }
    }

    private func requestSave() {
        if case .edit = mode, editsRecurringEvent, !isTask {
            pendingRecurringAction = .save
        } else {
            performSave(scope: .thisEvent)
        }
    }

    private func requestDelete() {
        guard onDelete != nil else { return }
        if editsRecurringEvent, !isTask {
            pendingRecurringAction = .delete
        } else {
            performDelete(scope: .thisEvent)
        }
    }

    private func performSave(scope: RecurringEventEditScope) {
        Task {
            isSaving = true
            let saved = await onSave(draft, scope)
            isSaving = false
            pendingRecurringAction = nil
            if saved { dismiss() }
        }
    }

    private func performDelete(scope: RecurringEventDeleteScope) {
        Task {
            guard let onDelete else { return }
            isSaving = true
            let deleted = await onDelete(scope)
            isSaving = false
            pendingRecurringAction = nil
            if deleted { dismiss() }
        }
    }

    private var recurringDialogTitle: String {
        switch pendingRecurringAction {
        case .save:
            return L.tr("Edit recurring event?", language: language)
        case .delete:
            return L.tr("Delete recurring event?", language: language)
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var recurringDialogActions: some View {
        switch pendingRecurringAction {
        case .save:
            Button(L.tr("Only This Event", language: language)) {
                performSave(scope: .thisEvent)
            }
            Button(L.tr("This and Future Events", language: language)) {
                performSave(scope: .futureEvents)
            }
        case .delete:
            Button(L.tr("Only This Event", language: language), role: .destructive) {
                performDelete(scope: .thisEvent)
            }
            Button(L.tr("All Events", language: language), role: .destructive) {
                performDelete(scope: .allEvents)
            }
        case nil:
            EmptyView()
        }

        Button(L.tr("Cancel", language: language), role: .cancel) {
            pendingRecurringAction = nil
        }
    }

    // MARK: - Computed Properties

    private var navigationTitle: String {
        switch mode {
        case .create: return itemKind == .reminder ? L.tr("New Task", language: language) : L.tr("New Event", language: language)
        case .edit: return isTask ? L.tr("Edit Task", language: language) : L.tr("Edit Event", language: language)
        }
    }

    private var confirmButtonTitle: String {
        switch mode {
        case .create: return L.tr("Add", language: language)
        case .edit: return L.tr("Save", language: language)
        }
    }

    private var videoCallSummary: String {
        let trimmed = draft.videoCallURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return L.tr("Add", language: language)
        }

        guard let url = URL(string: trimmed), let host = url.host(), !host.isEmpty else {
            return trimmed
        }

        return host
    }

    private var selectedCalendarIsWritable: Bool {
        calendars.first(where: { $0.id == draft.calendarID })?.isWritable == true
    }

    private var isTask: Bool {
        itemKind == .reminder
    }

    private var selectableCalendars: [CalendarSource] {
        calendars.filter { $0.kind.rawValue == itemKind.rawValue }
    }

    private func setItemKind(_ kind: CalendarItemKind) {
        guard case .create = mode, itemKind != kind else { return }
        itemKind = kind
        draft.kind = kind
        if let calendar = selectableCalendars.first(where: { $0.isVisible })
            ?? selectableCalendars.first {
            draft.calendarID = calendar.id
        } else {
            draft.calendarID = ""
        }
        expandedPicker = nil
    }

    private func scrollToSelectedCalendar(with proxy: ScrollViewProxy, animated: Bool) {
        guard selectableCalendars.contains(where: { $0.id == draft.calendarID }) else { return }

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

        let seedTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: seedDate)
        if (seedTime.hour ?? 0) != 0
            || (seedTime.minute ?? 0) != 0
            || (seedTime.second ?? 0) != 0
            || (seedTime.nanosecond ?? 0) != 0 {
            return seedDate
        }

        let time = calendar.dateComponents([.hour, .minute], from: roundedHour)
        var day = calendar.dateComponents([.year, .month, .day], from: seedDate)
        day.hour = time.hour
        day.minute = time.minute
        return calendar.date(from: day) ?? seedDate
    }
}
