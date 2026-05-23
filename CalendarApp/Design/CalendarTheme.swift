import SwiftUI

enum CalendarTheme {
    static let background = Color(.systemGroupedBackground)
    static let cellBackground = Color(.secondarySystemGroupedBackground)
    static let glassStroke = Color.white.opacity(0.35)
}

extension View {
    func glassCapsule() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(CalendarTheme.glassStroke, lineWidth: 0.8)
            }
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
