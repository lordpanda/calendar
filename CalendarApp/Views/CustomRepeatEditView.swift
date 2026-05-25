import SwiftUI

struct CustomRepeatEditView: View {
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
