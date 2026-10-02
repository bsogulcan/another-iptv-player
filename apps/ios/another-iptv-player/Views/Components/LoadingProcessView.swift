import SwiftUI

/// Status line of a running import: what is happening right now and, for work that
/// depends on the connection, a note that it can take a while. Sits at the bottom of
/// the add-playlist forms; the spinner itself takes the place of the Save button.
struct LoadingProcessView: View {
    let message: String
    var showsDurationHint = true

    var body: some View {
        VStack(spacing: 2) {
            Text(message)
                .font(.footnote.weight(.semibold))

            if showsDurationHint {
                Text(L("loading.takes_time_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        // One element, re-read as the phase changes, instead of two loose texts.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    Color.clear
        .safeAreaInset(edge: .bottom) {
            LoadingProcessView(message: "Downloading movies...")
        }
}
