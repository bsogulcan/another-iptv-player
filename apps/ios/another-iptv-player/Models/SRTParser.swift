import Foundation

struct SubtitleEntry: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

final class SRTParser {
    func parse(content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let scanner = Scanner(string: content)
        
        while !scanner.isAtEnd {
            // Index
            _ = scanner.scanInt()
            
            // Timestamps: 00:00:01,000 --> 00:00:04,000
            guard let timeString = scanner.scanUpToCharacters(from: .newlines) else { break }
            let times = timeString.components(separatedBy: " --> ")
            guard times.count == 2,
                  let start = parseTime(times[0]),
                  let end = parseTime(times[1]) else { continue }
            
            // Text
            var textLines: [String] = []
            while let line = scanner.scanUpToCharacters(from: .newlines), !line.isEmpty {
                textLines.append(line)
            }
            
            entries.append(SubtitleEntry(startTime: start, endTime: end, text: textLines.joined(separator: "\n")))
        }
        
        return entries
    }
    
    private func parseTime(_ timeString: String) -> TimeInterval? {
        let components = timeString.replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else { return nil }
        
        return (hours * 3600) + (minutes * 60) + seconds
    }
}
