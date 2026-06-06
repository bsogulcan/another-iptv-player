import SwiftUI

struct GlassSystemIconButton: View {
    var systemName: String
    var pointSize: CGFloat
    var weight: Font.Weight = .semibold
    var buttonSize: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)

                Image(systemName: systemName)
                    .font(.system(size: pointSize, weight: weight))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
            }
            .frame(width: buttonSize, height: buttonSize)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
