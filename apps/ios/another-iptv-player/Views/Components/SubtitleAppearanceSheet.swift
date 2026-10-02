import SwiftUI

struct SubtitleAppearanceSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Environment(\.dismiss) private var dismiss

    /// The style being edited. Every change goes straight to the playing picture and
    /// is saved; there is no separate apply step.
    @State private var draft: SubtitleAppearanceSettings
    /// The style as it was when the sheet opened: what Cancel goes back to.
    @State private var initial: SubtitleAppearanceSettings
    /// The time offset belongs to the content being played, not to the (global) style:
    /// it is edited here but read from and committed to the player, never to `draft`.
    @State private var delaySeconds: Double
    @State private var initialDelaySeconds: Double
    /// While the offset slider is dragged its value is only previewed on the player;
    /// it is committed for the content when the drag ends.
    @State private var isEditingDelay = false

    private static let delaySecondsRange: ClosedRange<Double> = -10...10

    init(player: VideoPlayerController) {
        self.player = player
        let loaded = SubtitleAppearancePersistence.load()
        _draft = State(initialValue: loaded)
        _initial = State(initialValue: loaded)
        let range = Self.delaySecondsRange
        let delay = min(max(player.subtitleDelaySeconds, range.lowerBound), range.upperBound)
        _delaySeconds = State(initialValue: delay)
        _initialDelaySeconds = State(initialValue: delay)
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
                // Changes are already live, so only Cancel has work to do: it puts back
                // what the sheet opened with. Done and a swipe down keep what is on screen.
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) {
                        restoreInitialSettings()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { dismiss() }
                }
            }
            // The panel leaves the video visible, so the style is judged on the real
            // cue: every change is applied (and saved) as it is made.
            .onChange(of: draft) { _, new in
                player.applySubtitleAppearanceSettings(new)
            }
            .onChange(of: delaySeconds) { _, new in
                if isEditingDelay {
                    player.applySubtitleDelaySeconds(new)
                } else {
                    // Reset, Cancel and VoiceOver adjustments change the value in one step.
                    commitDelay(new)
                }
            }
            // The panel can stay open while the next title starts. That title has an
            // offset of its own, which the slider and Cancel must follow; the echo of
            // this sheet's own commit is equal to `delaySeconds` and changes nothing.
            .onChange(of: player.subtitleDelaySeconds) { _, published in
                guard published != SubtitleDelayStore.clamp(delaySeconds) else { return }
                let range = Self.delaySecondsRange
                delaySeconds = min(max(published, range.lowerBound), range.upperBound)
                initialDelaySeconds = delaySeconds
            }
            // A drag still in flight when the sheet goes away never reports its end;
            // without this the player would keep an offset that was only previewed.
            .onDisappear {
                commitDelay(delaySeconds)
            }
        }
    }

    /// Makes `seconds` the offset of the content being played, unless it already is.
    private func commitDelay(_ seconds: Double) {
        guard SubtitleDelayStore.clamp(seconds) != player.subtitleDelaySeconds else { return }
        player.commitSubtitleDelaySeconds(seconds)
    }

    private func restoreInitialSettings() {
        if draft != initial {
            draft = initial
            player.applySubtitleAppearanceSettings(initial)
        }
        delaySeconds = initialDelaySeconds
        commitDelay(initialDelaySeconds)
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
                delaySeconds = 0
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(L("subtitle.reset_to_default"))
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(draft == .default && abs(delaySeconds) < 0.05)
        }
    }

    private var timingSection: some View {
        Section {
            stepperRow(
                label: L("subtitle.time_offset"),
                value: $delaySeconds,
                range: Self.delaySecondsRange,
                step: 0.1,
                display: { s in
                    if abs(s) < 0.05 { return L("subtitle.no_delay") }
                    let sign = s > 0 ? "+" : ""
                    return "\(sign)\(String(format: "%.1f", s)) s"
                },
                onEditingChanged: { editing in
                    isEditingDelay = editing
                    if !editing { commitDelay(delaySeconds) }
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
        display: @escaping (Double) -> String,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
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
            // The slider carries the same label and value for VoiceOver.
            .accessibilityHidden(true)
            Slider(
                value: value,
                in: range,
                step: step,
                label: { Text(label) },
                onEditingChanged: onEditingChanged
            )
            .accessibilityValue(display(value.wrappedValue))
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

            // Mirrors the player's cue (KSSubtitleCueText): same outline renderer, same
            // padding, and the block (not just its lines) placed by the alignment.
            Text(displayText)
                .font(previewFont)
                .italic(settings.italic)
                .kerning(CGFloat(settings.letterSpacing))
                .lineSpacing(previewLineSpacing)
                .multilineTextAlignment(previewTextAlignment)
                .foregroundStyle(Color(hex6: settings.textColorHex6))
                .textRenderer(settings.outlineRenderer)
                .padding(.horizontal, CGFloat(settings.padding) + 8)
                .padding(.vertical, 4)
                .background(previewBackground)
                .padding(.horizontal, previewEdgeInset)
                .frame(
                    maxWidth: .infinity,
                    alignment: previewFrameAlignment
                )
                .padding(.bottom, previewBottomPadding)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var displayText: String {
        // Same transform the player overlay uses, so the preview matches playback.
        settings.applyingWordSpacing(to: sampleText)
    }

    private var previewFont: Font {
        // Same on-screen scale as the player overlay, so the preview is WYSIWYG.
        let size = CGFloat(settings.renderedFontPointSize)
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
        let base = CGFloat(settings.renderedFontPointSize)
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

    /// Same inset the player gives a side-aligned cue block.
    private var previewEdgeInset: CGFloat {
        switch settings.textAlignment {
        case .left, .right: return 12
        case .center, .justify: return 0
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if settings.backgroundEnabled {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex6: settings.backgroundColorHex6).opacity(settings.backgroundOpacity))
        } else {
            Color.clear
        }
    }

    private var previewBottomPadding: CGFloat {
        // Same formula as the player overlay (KSPlayerSurfaceView), so slider position 0
        // is the shared baseline and both directions move identically in preview and playback.
        max(CGFloat(settings.verticalOffset) + 12, 0)
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
