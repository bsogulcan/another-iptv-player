import SwiftUI

struct LoadingProcessView: View {
    let message: String
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)
            }
            
            VStack(spacing: 10) {
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text(L("loading.takes_time_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingProcessView(message: "Preparing categories...")
}
