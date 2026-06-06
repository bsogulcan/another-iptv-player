import SwiftUI

struct SubtitleOverlayView: View {
    let text: String?
    
    var body: some View {
        VStack {
            Spacer()
            if let text = text {
                Text(text)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.6))
                    )
                    .padding(.bottom, 60) // Extra padding for controls
                    .shadow(radius: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding()
        .animation(.easeOut(duration: 0.2), value: text)
    }
}
