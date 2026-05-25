import SwiftUI

// MARK: - Sub-components

struct EventRow<Content: View>: View {
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

struct EventDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
    }
}

struct CalendarChip: View {
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
