import SwiftUI

struct SubtitleAppearanceSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SubtitleAppearanceSettings
    @State private var initial: SubtitleAppearanceSettings

    init(player: VideoPlayerController) {
        self.player = player
        let loaded = SubtitleAppearancePersistence.load()
        _draft = State(initialValue: loaded)
        _initial = State(initialValue: loaded)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SubtitlePreviewCard(settings: draft)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(L("subtitle.preview"))
                }

                fontSection
                colorSection
                styleSection
                extraSection
                timingSection
                resetSection
            }
            .navigationTitle(L("subtitle.settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("subtitle.apply")) {
                        player.applySubtitleAppearanceSettings(draft)
                        dismiss()
                    }
                    .disabled(draft == initial)
                }
            }
            .onChange(of: draft.delaySeconds) { _, new in
                player.applySubtitleDelaySeconds(new)
            }
        }
    }

    // MARK: - Sections

    private var fontSection: some View {
        Section {
            stepperRow(
                label: L("subtitle.font_size"),
                value: Binding(
                    get: { Double(draft.fontSize) },
                    set: { draft.fontSize = Int($0.rounded()) }
                ),
                range: Double(SubtitleAppearanceSettings.fontSizeRange.lowerBound)...Double(SubtitleAppearanceSettings.fontSizeRange.upperBound),
                step: 1,
                display: { "\(Int($0)) px" }
            )
            stepperRow(
                label: L("subtitle.font_height"),
                value: $draft.lineHeight,
                range: SubtitleAppearanceSettings.lineHeightRange,
                step: 0.05,
                display: { String(format: "%.2f×", $0) }
            )
            stepperRow(
                label: L("subtitle.letter_spacing"),
                value: $draft.letterSpacing,
                range: SubtitleAppearanceSettings.letterSpacingRange,
                step: 0.1,
                display: { String(format: "%.1f", $0) }
            )
            stepperRow(
                label: L("subtitle.word_spacing"),
                value: $draft.wordSpacing,
                range: SubtitleAppearanceSettings.wordSpacingRange,
                step: 0.1,
                display: { String(format: "%.1f", $0) }
            )
            stepperRow(
                label: L("subtitle.padding"),
                value: Binding(
                    get: { Double(draft.padding) },
                    set: { draft.padding = Int($0.rounded()) }
                ),
                range: Double(SubtitleAppearanceSettings.paddingRange.lowerBound)...Double(SubtitleAppearanceSettings.paddingRange.upperBound),
                step: 1,
                display: { "\(Int($0)) px" }
            )
        } header: {
            Text(L("subtitle.section.font"))
        }
    }

    private var colorSection: some View {
        Section {
            ColorPicker(
                L("subtitle.text_color"),
                selection: Binding(
                    get: { Color(hex6: draft.textColorHex6) },
                    set: { draft.textColorHex6 = $0.toHex6() }
                ),
                supportsOpacity: false
            )

            Toggle(L("subtitle.background_enabled"), isOn: $draft.backgroundEnabled)

            if draft.backgroundEnabled {
                ColorPicker(
                    L("subtitle.background_color"),
                    selection: Binding(
                        get: { Color(hex6: draft.backgroundColorHex6) },
                        set: { draft.backgroundColorHex6 = $0.toHex6() }
                    ),
                    supportsOpacity: false
                )
                stepperRow(
                    label: L("subtitle.background_opacity"),
                    value: $draft.backgroundOpacity,
                    range: SubtitleAppearanceSettings.backgroundOpacityRange,
                    step: 0.05,
                    display: { "\(Int(($0 * 100).rounded()))%" }
                )
            }
        } header: {
            Text(L("subtitle.section.color"))
        }
    }

    private var styleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("subtitle.font_weight"))
                    .font(.subheadline.weight(.medium))
                Picker(L("subtitle.font_weight"), selection: $draft.fontWeight) {
                    ForEach(SubtitleFontWeight.allCases) { w in
                        Text(w.shortLabel).tag(w)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("subtitle.alignment"))
                    .font(.subheadline.weight(.medium))
                Picker(L("subtitle.alignment"), selection: $draft.textAlignment) {
                    ForEach(SubtitleTextAlignment.allCases) { a in
                        Image(systemName: a.iconName).tag(a)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            Toggle(L("subtitle.italic"), isOn: $draft.italic)
        } header: {
            Text(L("subtitle.style"))
        } footer: {
            Text(L("subtitle.style.footer"))
        }
    }

    private var extraSection: some View {
        Section {
            stepperRow(
                label: L("subtitle.outline_size"),
                value: $draft.outlineSize,
                range: SubtitleAppearanceSettings.outlineSizeRange,
                step: 0.5,
                display: { String(format: "%.1f", $0) }
            )
            ColorPicker(
                L("subtitle.outline_color"),
                selection: Binding(
                    get: { Color(hex6: draft.outlineColorHex6) },
                    set: { draft.outlineColorHex6 = $0.toHex6() }
                ),
                supportsOpacity: false
            )
            stepperRow(
                label: L("subtitle.vertical_offset"),
                value: Binding(
                    get: { Double(draft.verticalOffset) },
                    set: { draft.verticalOffset = Int($0.rounded()) }
                ),
                range: Double(SubtitleAppearanceSettings.verticalOffsetRange.lowerBound)...Double(SubtitleAppearanceSettings.verticalOffsetRange.upperBound),
                step: 4,
                display: { val in
                    let v = Int(val)
                    if v == 0 { return L("subtitle.default_value") }
                    return v > 0 ? "+\(v) px" : "\(v) px"
                }
            )
        } header: {
            Text(L("subtitle.outline_position"))
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                draft = .default
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(L("subtitle.reset_to_default"))
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(draft == .default)
        }
    }

    private var timingSection: some View {
        Section {
            stepperRow(
                label: L("subtitle.time_offset"),
                value: $draft.delaySeconds,
                range: SubtitleAppearanceSettings.delaySecondsRange,
                step: 0.1,
                display: { s in
                    if abs(s) < 0.05 { return L("subtitle.no_delay") }
                    let sign = s > 0 ? "+" : ""
                    return "\(sign)\(String(format: "%.1f", s)) s"
                }
            )
        } header: {
            Text(L("subtitle.timing"))
        } footer: {
            Text(L("subtitle.timing_footer"))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

private struct SubtitlePreviewCard: View {
    let settings: SubtitleAppearanceSettings

    private var sampleText: String { L("subtitle.sample_preview") }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.19, blue: 0.28),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(displayText)
                .font(previewFont)
                .italic(settings.italic)
                .kerning(CGFloat(settings.letterSpacing))
                .lineSpacing(previewLineSpacing)
                .multilineTextAlignment(previewTextAlignment)
                .frame(
                    maxWidth: .infinity,
                    alignment: previewFrameAlignment
                )
                .foregroundStyle(Color(hex6: settings.textColorHex6))
                .shadow(
                    color: Color(hex6: settings.outlineColorHex6).opacity(settings.outlineSize > 0 ? 0.9 : 0),
                    radius: CGFloat(settings.outlineSize * 0.6),
                    x: 0,
                    y: 0
                )
                .padding(.horizontal, CGFloat(settings.padding))
                .padding(.vertical, CGFloat(settings.padding * 2 / 3))
                .background(previewBackground)
                .padding(.horizontal, 20)
                .padding(.bottom, previewBottomPadding)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var displayText: String {
        guard settings.wordSpacing > 0.01 else { return sampleText }
        let extraSpaces = Int((settings.wordSpacing).rounded())
        guard extraSpaces > 0 else { return sampleText }
        let sep = String(repeating: " ", count: extraSpaces + 1)
        return sampleText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(separator: " ").joined(separator: sep)
            }
            .joined(separator: "\n")
    }

    private var previewFont: Font {
        let size = CGFloat(settings.fontSize) * 0.5
        return Font.system(size: size, weight: previewWeight)
    }

    private var previewWeight: Font.Weight {
        switch settings.fontWeight {
        case .thin: return .thin
        case .normal: return .regular
        case .medium: return .medium
        case .bold: return .bold
        case .extraBold: return .heavy
        }
    }

    private var previewLineSpacing: CGFloat {
        let base = CGFloat(settings.fontSize) * 0.5
        return max(0, base * CGFloat(settings.lineHeight - 1.0))
    }

    private var previewTextAlignment: TextAlignment {
        switch settings.textAlignment {
        case .left: return .leading
        case .right: return .trailing
        case .center, .justify: return .center
        }
    }

    private var previewFrameAlignment: Alignment {
        switch settings.textAlignment {
        case .left: return .leading
        case .right: return .trailing
        case .center, .justify: return .center
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if settings.backgroundEnabled {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex6: settings.backgroundColorHex6).opacity(settings.backgroundOpacity))
        } else {
            Color.clear
        }
    }

    private var previewBottomPadding: CGFloat {
        let base: CGFloat = 12
        return max(4, base - CGFloat(settings.verticalOffset) * 0.4)
    }
}

// MARK: - Color <-> hex

private extension Color {
    init(hex6: UInt32) {
        let r = Double((hex6 >> 16) & 0xFF) / 255.0
        let g = Double((hex6 >> 8) & 0xFF) / 255.0
        let b = Double(hex6 & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func toHex6() -> UInt32 {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(1, r)) * 255)
        let gi = UInt32(max(0, min(1, g)) * 255)
        let bi = UInt32(max(0, min(1, b)) * 255)
        return (ri << 16) | (gi << 8) | bi
        #else
        return 0xFFFFFF
        #endif
    }
}
