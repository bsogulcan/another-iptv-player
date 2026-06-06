import Foundation
import Combine

final class SubtitleManager: ObservableObject {
    @Published var currentSubtitle: String?
    @Published var subtitles: [SubtitleEntry] = []

    private var lastIndex = 0

    func reset() {
        subtitles = []
        currentSubtitle = nil
        lastIndex = 0
    }

    func load(srtContent: String) {
        subtitles = SRTParser().parse(content: srtContent)
        currentSubtitle = nil
        lastIndex = 0
    }

    func update(currentTime: TimeInterval) {
        guard !subtitles.isEmpty else {
            if currentSubtitle != nil { currentSubtitle = nil }
            return
        }

        // Önce son bilinen index'i kontrol et (sıralı oynatma için O(1)).
        if lastIndex < subtitles.count {
            let entry = subtitles[lastIndex]
            if currentTime >= entry.startTime && currentTime <= entry.endTime {
                if currentSubtitle != entry.text { currentSubtitle = entry.text }
                return
            }
        }

        // Binary search: başlangıç zamanı currentTime'dan küçük veya eşit olan son entry'yi bul.
        var lo = 0
        var hi = subtitles.count - 1
        var candidate = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if subtitles[mid].startTime <= currentTime {
                candidate = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if candidate >= 0 && currentTime <= subtitles[candidate].endTime {
            lastIndex = candidate
            if currentSubtitle != subtitles[candidate].text {
                currentSubtitle = subtitles[candidate].text
            }
        } else {
            lastIndex = max(candidate, 0)
            if currentSubtitle != nil { currentSubtitle = nil }
        }
    }
}
