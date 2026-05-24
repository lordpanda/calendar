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
        var videoCallURL = ""
        var alertOption: EventAlertOption = .none
        var visibility: EventVisibilityOption = .default
        var availability: EventAvailabilityOption = .busy
        var isCompleted = false
        var kind: CalendarItemKind = .event

        private static let videoCallPrefix = "Video call: "

        var notesForStorage: String {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedVideoCallURL = videoCallURL.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedVideoCallURL.isEmpty else {
                return trimmedNotes
            }

            guard !trimmedNotes.isEmpty else {
                return Self.videoCallPrefix + trimmedVideoCallURL
            }

            return trimmedNotes + "\n" + Self.videoCallPrefix + trimmedVideoCallURL
        }

        static func userNotes(from storedNotes: String?) -> String {
            (storedNotes ?? "")
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(videoCallPrefix) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func videoCallURL(from storedNotes: String?) -> String {
            (storedNotes ?? "")
                .components(separatedBy: .newlines)
                .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(videoCallPrefix) }
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(videoCallPrefix.count)) } ?? ""
        }
    }

    enum Mode {
        case create
        case edit(eventID: String)
    }

    private enum PendingRecurringAction {
        case save
        case delete
    }

    private enum PickerFocus: Equatable {
        case startDate, startTime, endDate, endTime
    }

    private enum FocusField: Hashable {
        case title
    }

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
        .background(Color(.systemBackground))
    }
}

private struct EventDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
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
    @Environment(\.appLanguage) private var language
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
            .navigationTitle(L.tr("Custom Repeat", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.tr("Cancel", language: language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        selection = .custom(customRule)
                        dismiss()
                    }
                }
            }
        }
    }

    private var frequencyRow: some View {
        HStack {
            Text(L.tr("Frequency", language: language))
            Spacer()
            Picker(L.tr("Frequency", language: language), selection: $customRule.frequency) {
                ForEach(EventRepeatFrequency.allCases) { frequency in
                    Text(frequency.title(language: language)).tag(frequency)
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
                Text(L.tr("Every", language: language))
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
                    Text(option.intervalUnitTitle(interval: customRule.interval, language: language)).tag(option)
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
                monthlyModeRow(title: L.tr("Each", language: language), mode: .eachDate)
                Divider().padding(.leading, 20)
                monthlyModeRow(title: L.tr("On the...", language: language), mode: .nthWeekday)
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
                        Text(L.tr("Days of Week", language: language))
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
                    Text(option.title(language: language)).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Picker("", selection: $customRule.nthDaySelector) {
                ForEach(CustomRepeatNthDaySelector.allCases, id: \.self) { option in
                    Text(option.title(language: language)).tag(option)
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
            return customRule.frequency.intervalUnitTitle(interval: interval, language: language)
        }
        return L.tr("%d %@", language: language, interval, customRule.frequency.pluralTitle(language: language))
    }

    private var summaryText: String {
        customRule.frequency.summarySentence(interval: customRule.interval, language: language)
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
    @Environment(\.appLanguage) private var language
    @StateObject private var search = LocationSearchModel()
    @State private var isSearchPresented = false

    var body: some View {
        NavigationStack {
            List(search.results) { result in
                Button {
                    onSelect(result.title)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .tint(.primary)
            .navigationTitle(L.tr("Location", language: language))
            .searchable(
                text: $search.query,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L.tr("Search maps", language: language)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.tr("Cancel", language: language)) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    isSearchPresented = true
                }
            }
        }
    }
}

private struct LocationSearchResult: Identifiable, Hashable {
    let title: String
    let subtitle: String

    var id: String { "\(title)\n\(subtitle)" }
}

@MainActor
private final class LocationSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            search()
        }
    }
    @Published var results: [LocationSearchResult] = []

    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
        completer.region = Self.seoulSearchRegion
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        fallbackTask?.cancel()
        guard !term.isEmpty else {
            results = []
            completer.queryFragment = ""
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            completer.queryFragment = term
            runFallbackSearch(for: term)
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map { completion in
            LocationSearchResult(title: completion.title, subtitle: completion.subtitle)
        }

        guard mapped.isEmpty == false else { return }
        results = Self.deduplicated(mapped)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        runFallbackSearch(for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func runFallbackSearch(for term: String) {
        fallbackTask?.cancel()
        guard !term.isEmpty else { return }

        fallbackTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.resultTypes = [.address, .pointOfInterest]
            request.region = Self.seoulSearchRegion

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                let mapped = response.mapItems.map { item in
                    LocationSearchResult(
                        title: item.name ?? term,
                        subtitle: item.placemark.title ?? ""
                    )
                }
                results = Self.deduplicated(results + mapped)
            } catch {
                guard !Task.isCancelled else { return }
                if results.isEmpty {
                    results = []
                }
            }
        }
    }

    private static let seoulSearchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    private static func deduplicated(_ values: [LocationSearchResult]) -> [LocationSearchResult] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
}

private struct InviteesEditView: View {
    @Binding var invitees: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var email = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("email@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        Button(L.tr("Add", language: language)) {
                            addInvitee()
                        }
                        .disabled(normalizedEmail.isEmpty)
                    }
                }

                Section(L.tr("Invitees", language: language)) {
                    if invitees.isEmpty {
                        Text(L.tr("No invitees", language: language))
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
            .navigationTitle(L.tr("Invitees", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
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
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $attachmentURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    Text(L.tr("Use a web or file URL. Providers may reject attachments they cannot access.", language: language))
                }

                if !attachmentURL.isEmpty {
                    Section {
                        Button(L.tr("Remove Attachment", language: language), role: .destructive) {
                            attachmentURL = ""
                        }
                    }
                }
            }
            .navigationTitle(L.tr("Attachment", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct VideoCallEditView: View {
    @Binding var videoCallURL: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $videoCallURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    Text(L.tr("Use a video meeting URL.", language: language))
                }

                if !videoCallURL.isEmpty {
                    Section {
                        Button(L.tr("Remove Video Call", language: language), role: .destructive) {
                            videoCallURL = ""
                        }
                    }
                }
            }
            .navigationTitle(L.tr("Video Call", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
    }
}
