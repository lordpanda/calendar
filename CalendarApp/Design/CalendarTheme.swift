import SwiftUI

enum CalendarTheme {
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let separator = Color(.separator).opacity(0.2)
    static let mutedDay = Color(.systemGray6)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let accent = Color(hex: "00C8B3") ?? .mint
    static let monthGridLine = Color(.separator).opacity(0.85)
    static let monthRowLine = Color(.separator)
}

extension View {
    func glassCapsule(horizontal: CGFloat = 16, vertical: CGFloat = 10) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .glassEffect(in: Capsule())
    }

    func glassCircle(size: CGFloat = 44) -> some View {
        self
            .frame(width: size, height: size)
            .glassEffect(in: Circle())
    }
}

extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
