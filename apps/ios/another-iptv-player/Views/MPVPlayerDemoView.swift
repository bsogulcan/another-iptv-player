//
//  MPVPlayerDemoView.swift
//  another-iptv-player — mpv-player demo ile bire bir (MPVPlayer adlandırması).
//

import SwiftUI

struct MPVPlayerDemoView: View {
  private static func formatClock(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else { return "0:00" }
    let s = Int(seconds.rounded(.down))
    let h = s / 3600
    let m = (s % 3600) / 60
    let r = s % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, r)
    }
    return String(format: "%d:%02d", m, r)
  }

  /// Örnek HTTP akışı (mpv-player demo ile aynı URL).
  private let demoURL = URL(
    string: "http://ss.54778553.xyz:8080/movie/FSR96/9G4E55/228315.mp4"
  )!

  @StateObject private var player = MPVPlayer()

  var body: some View {
    VStack(spacing: 12) {
      MPVPlayerVideoSurface(player: player)
        .background(Color.black)
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      if player.isReady, player.duration > 0 {
        MPVPlayerMaterialSeekBar(player: player)
      }

      HStack(spacing: 16) {
        Button("Oynat") { player.play() }
          .disabled(!player.isReady)
        Button("Duraklat") { player.pause() }
          .disabled(!player.isReady)
      }
      .buttonStyle(.borderedProminent)

      if player.isReady {
        VStack(alignment: .leading, spacing: 6) {
          Text(player.mediaTitle.isEmpty ? "—" : player.mediaTitle)
            .font(.subheadline)
            .lineLimit(2)
          HStack {
            if player.duration <= 0 {
              Text(Self.formatClock(player.position))
                .font(.caption.monospacedDigit())
            }
            if player.isBuffering {
              Text(L("player.buffering"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if player.isCompleted {
              Text(L("player.ended"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Text(
            "\(player.videoDisplayWidth)×\(player.videoDisplayHeight) · ses \(Int(player.volume))% · \(String(format: "%.2f", player.playbackRate))×"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if !player.isReady {
        ProgressView(L("player.preparing"))
      }
    }
    .padding()
    .onChange(of: player.isReady) { _, ready in
      if ready {
        player.load(demoURL, play: true)
      }
    }
    .onDisappear {
      player.dispose()
    }
  }
}

#Preview {
  MPVPlayerDemoView()
}
