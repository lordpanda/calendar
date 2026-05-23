import SwiftUI

struct BottomFloatingBar: View {
    let onToday: () -> Void
    let onAdd: () -> Void
    let isAddEnabled: Bool

    var body: some View {
        HStack {
            Button(action: onToday) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
            }
            .glassCapsule()

            Spacer()

            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                    Text("New")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .glassCapsule()
            .disabled(!isAddEnabled)
            .opacity(isAddEnabled ? 1 : 0.45)
            .accessibilityLabel("Add event")
        }
    }
}
