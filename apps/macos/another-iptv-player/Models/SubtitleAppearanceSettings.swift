import Foundation

enum SubtitleFontWeight: String, CaseIterable, Codable, Identifiable {
    case thin
    case normal
    case medium
    case bold
    case extraBold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thin: return L("style.weight.thin")
        case .normal: return L("style.weight.normal")
        case .medium: return L("style.weight.medium")
        case .bold: return L("style.weight.bold")
        case .extraBold: return L("style.weight.extra_bold")
        }
    }

    var shortLabel: String {
        switch self {
        case .thin: return L("style.weight.thin")
        case .normal: return L("style.weight.normal")
        case .medium: return L("style.weight.medium")
        case .bold: return L("style.weight.bold")
        case .extraBold: return L("style.weight.extra_bold")
        }
    }

    /// libass / CoreText için iOS sistem yazı tipi postscript adı. Cihazda aranır; bulunamazsa fallback olur.
    var iosPostscriptName: String {
        switch self {
        case .thin: return "SFProDisplay-Thin"
        case .normal: return "SFProDisplay-Regular"
        case .medium: return "SFProDisplay-Medium"
        case .bold: return "SFProDisplay-Bold"
        case .extraBold: return "SFProDisplay-Heavy"
        }
    }
}

enum SubtitleTextAlignment: String, CaseIterable, Codable, Identifiable {
    case left
    case center
    case right
    case justify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return L("style.align.left")
        case .center: return L("style.align.center")
        case .right: return L("style.align.right")
        case .justify: return L("style.align.justify")
        }
    }

    var iconName: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justify: return "text.justify"
        }
    }
}

struct SubtitleAppearanceSettings: Equatable {
    var fontSize: Int
    var lineHeight: Double
    var letterSpacing: Double
    var wordSpacing: Double
    var padding: Int

    var textColorHex6: UInt32
    var backgroundEnabled: Bool
    var backgroundColorHex6: UInt32
    var backgroundOpacity: Double

    var fontWeight: SubtitleFontWeight
    var textAlignment: SubtitleTextAlignment
    var italic: Bool

    var outlineSize: Double
    var outlineColorHex6: UInt32
    var verticalOffset: Int

    var delaySeconds: Double

    static let `default` = SubtitleAppearanceSettings(
        fontSize: 40,
        lineHeight: 1.2,
        letterSpacing: 0,
        wordSpacing: 0,
        padding: 16,
        textColorHex6: 0xFFFFFF,
        backgroundEnabled: false,
        backgroundColorHex6: 0x000000,
        backgroundOpacity: 0.75,
        fontWeight: .normal,
        textAlignment: .center,
        italic: false,
        outlineSize: 2,
        outlineColorHex6: 0x000000,
        verticalOffset: 0,
        delaySeconds: 0
    )

    static let fontSizeRange: ClosedRange<Int> = 24...96
    static let lineHeightRange: ClosedRange<Double> = 1.0...2.5
    static let letterSpacingRange: ClosedRange<Double> = -2...5
    static let wordSpacingRange: ClosedRange<Double> = -2...10
    static let paddingRange: ClosedRange<Int> = 8...48
    static let backgroundOpacityRange: ClosedRange<Double> = 0...1
    static let outlineSizeRange: ClosedRange<Double> = 0...6
    static let verticalOffsetRange: ClosedRange<Int> = -120...120
    static let delaySecondsRange: ClosedRange<Double> = -10...10

    mutating func clamp() {
        fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        lineHeight = min(max(lineHeight, Self.lineHeightRange.lowerBound), Self.lineHeightRange.upperBound)
        letterSpacing = min(max(letterSpacing, Self.letterSpacingRange.lowerBound), Self.letterSpacingRange.upperBound)
        wordSpacing = min(max(wordSpacing, Self.wordSpacingRange.lowerBound), Self.wordSpacingRange.upperBound)
        padding = min(max(padding, Self.paddingRange.lowerBound), Self.paddingRange.upperBound)
        backgroundOpacity = min(max(backgroundOpacity, Self.backgroundOpacityRange.lowerBound), Self.backgroundOpacityRange.upperBound)
        outlineSize = min(max(outlineSize, Self.outlineSizeRange.lowerBound), Self.outlineSizeRange.upperBound)
        verticalOffset = min(max(verticalOffset, Self.verticalOffsetRange.lowerBound), Self.verticalOffsetRange.upperBound)
        delaySeconds = min(max(delaySeconds, Self.delaySecondsRange.lowerBound), Self.delaySecondsRange.upperBound)
    }
}

extension SubtitleAppearanceSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case fontSize, lineHeight, letterSpacing, wordSpacing, padding
        case textColorHex6, backgroundEnabled, backgroundColorHex6, backgroundOpacity
        case fontWeight, textAlignment, italic
        case outlineSize, outlineColorHex6, verticalOffset
        case delaySeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? d.fontSize
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? d.lineHeight
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? d.letterSpacing
        wordSpacing = try c.decodeIfPresent(Double.self, forKey: .wordSpacing) ?? d.wordSpacing
        padding = try c.decodeIfPresent(Int.self, forKey: .padding) ?? d.padding
        textColorHex6 = try c.decodeIfPresent(UInt32.self, forKey: .textColorHex6) ?? d.textColorHex6
        backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? d.backgroundEnabled
        backgroundColorHex6 = try c.decodeIfPresent(UInt32.self, forKey: .backgroundColorHex6) ?? d.backgroundColorHex6
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        fontWeight = try c.decodeIfPresent(SubtitleFontWeight.self, forKey: .fontWeight) ?? d.fontWeight
        textAlignment = try c.decodeIfPresent(SubtitleTextAlignment.self, forKey: .textAlignment) ?? d.textAlignment
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? d.italic
        outlineSize = try c.decodeIfPresent(Double.self, forKey: .outlineSize) ?? d.outlineSize
        outlineColorHex6 = try c.decodeIfPresent(UInt32.self, forKey: .outlineColorHex6) ?? d.outlineColorHex6
        verticalOffset = try c.decodeIfPresent(Int.self, forKey: .verticalOffset) ?? d.verticalOffset
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? d.delaySeconds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(lineHeight, forKey: .lineHeight)
        try c.encode(letterSpacing, forKey: .letterSpacing)
        try c.encode(wordSpacing, forKey: .wordSpacing)
        try c.encode(padding, forKey: .padding)
        try c.encode(textColorHex6, forKey: .textColorHex6)
        try c.encode(backgroundEnabled, forKey: .backgroundEnabled)
        try c.encode(backgroundColorHex6, forKey: .backgroundColorHex6)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try c.encode(fontWeight, forKey: .fontWeight)
        try c.encode(textAlignment, forKey: .textAlignment)
        try c.encode(italic, forKey: .italic)
        try c.encode(outlineSize, forKey: .outlineSize)
        try c.encode(outlineColorHex6, forKey: .outlineColorHex6)
        try c.encode(verticalOffset, forKey: .verticalOffset)
        try c.encode(delaySeconds, forKey: .delaySeconds)
    }
}

enum SubtitleAppearancePersistence {
    private static let key = "playback.subtitleAppearance.v2"

    static func load() -> SubtitleAppearanceSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SubtitleAppearanceSettings.self, from: data)
        else {
            return .default
        }
        var s = decoded
        s.clamp()
        return s
    }

    static func save(_ settings: SubtitleAppearanceSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
