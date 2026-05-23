import SwiftUI

struct BottomFloatingBar: View {
    let onToday: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Button(action: onToday) {
                Text("Today")
                    .font(.headline)
            }
            .glassCapsule()

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .glassCapsule()
            .accessibilityLabel("Add event")
        }
    }
}
