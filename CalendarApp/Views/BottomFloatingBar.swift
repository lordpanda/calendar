import SwiftUI

struct BottomFloatingBar: View {
    let onToday: () -> Void
    let onAdd: () -> Void
    let isAddEnabled: Bool

    var body: some View {
        HStack {
            Button(action: onToday) {
                Text("Today")
                    .font(.system(size: 17, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassCapsule(horizontal: 16, vertical: 10)

            Spacer()

            Button {
                guard isAddEnabled else { return }
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassCircle(size: 48)
            .opacity(isAddEnabled ? 1 : 0.45)
            .accessibilityLabel("Add event")
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
        }
    }
}
