import SwiftUI
import GRDB

// MARK: - Shared refresh status row

/// Refresh-now button, last-updated timestamp, and error footer — shared by the
/// M3U and Xtream EPG settings sections.
struct EPGRefreshStatusView: View {
    let playlist: Playlist
    var canRefresh: Bool = true
    @ObservedObject private var epgStore = EPGStore.shared
    @State private var refreshSuccessCount = 0
    @State private var refreshFailureCount = 0

    init(playlist: Playlist, canRefresh: Bool = true) {
        self.playlist = playlist
        self.canRefresh = canRefresh
    }

    private var state: EPGRefreshState { epgStore.refreshState[playlist.id] ?? .idle }

    var body: some View {
        Button {
            Task { await refreshNow() }
        } label: {
            HStack {
                Label(L("epg.refresh"), systemImage: "arrow.clockwise")
                Spacer()
                if state.isRefreshing { ProgressView() }
            }
        }
        .disabled(!canRefresh || state.isRefreshing)
        .sensoryFeedback(.success, trigger: refreshSuccessCount)
        .sensoryFeedback(.error, trigger: refreshFailureCount)

        LabeledContent(L("epg.last_updated")) {
            if let last = epgStore.lastSuccess[playlist.id] {
                // Redrawn once a minute. A self-updating relative `Text` counts
                // seconds, and a static one would still say "now" hours later on a
                // tab that stays alive.
                TimelineView(.everyMinute) { _ in
                    Text(Self.lastUpdatedText(last, locale: AppLocale.current))
                }
            } else {
                Text(L("epg.never_updated"))
            }
        }

        if case .failed(let message) = state {
            Text(message)
                .font(.footnote)
                .foregroundColor(.red)
        }
    }

    /// Only a refresh started from this row gives feedback: the store also
    /// refreshes on its own while the user is somewhere else.
    private func refreshNow() async {
        let pid = playlist.id
        let before = epgStore.lastSuccess[pid]
        await epgStore.forceRefresh(playlist: playlist)
        if case .failed = epgStore.refreshState[pid] ?? .idle {
            refreshFailureCount += 1
        } else if epgStore.lastSuccess[pid] != before {
            refreshSuccessCount += 1
        }
    }

    /// "now" during the first minute, then whole units ("5 minutes ago",
    /// "yesterday"), in the app's language rather than the device's.
    nonisolated static func lastUpdatedText(_ date: Date, locale: Locale) -> String {
        let now = Date()
        // Under a minute the style counts seconds, which a text redrawn once a
        // minute cannot keep up with.
        let shown = now.timeIntervalSince(date) < 60 ? now : date
        return shown.formatted(Date.RelativeFormatStyle(presentation: .named, locale: locale))
    }
}

// MARK: - M3U section (editable XMLTV URL)

struct M3UEPGSettingsSection: View {
    /// The settings form's copy of the stored row. Saving here hands the saved row
    /// back to it, and a re-import done by the form (which may bring a new header
    /// URL) reaches this section the same way.
    @Binding var playlist: Playlist
    @State private var epgURLDraft: String
    @State private var saveError: String?
    @FocusState private var isURLFocused: Bool

    init(playlist: Binding<Playlist>) {
        _playlist = playlist
        _epgURLDraft = State(initialValue: Self.storedURL(of: playlist.wrappedValue))
    }

    var body: some View {
        Section {
            // One line: Return submits and closes the keyboard, and a pasted line
            // break cannot end up inside the URL. A long URL scrolls.
            TextField(L("epg.settings.url_placeholder"), text: $epgURLDraft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isURLFocused)
                .onSubmit {
                    // Unchanged text must not start a download on every Return.
                    if isDirty { Task { await saveURL() } }
                }
                // The stored URL changed under an untouched field (a re-import
                // found another header URL): show the new one. An edit in progress
                // is left alone.
                .onChange(of: Self.storedURL(of: playlist)) { old, new in
                    if draftTrimmed == old { epgURLDraft = new }
                }

            Button(L("epg.settings.save_url")) {
                isURLFocused = false
                Task { await saveURL() }
            }
            .disabled(!isDirty)

            // Refresh downloads the stored URL, not the text in the field.
            EPGRefreshStatusView(playlist: playlist, canRefresh: !Self.storedURL(of: playlist).isEmpty)

            if let saveError {
                Text(saveError).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text(L("epg.settings.section_title"))
        } footer: {
            Text(L("epg.settings.url_footer"))
        }
    }

    /// The URL in effect as stored: the user's override, else the playlist's own
    /// header URL. This is what the field shows when it has no unsaved edit.
    nonisolated static func storedURL(of playlist: Playlist) -> String {
        (playlist.effectiveEPGURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What saving `draft` stores as the override: nil for a blank field, which
    /// hands the guide back to the playlist's header URL.
    nonisolated static func override(forDraft draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether saving `draft` would change the URL in effect. Compared with the
    /// effective URL, not with the override alone: a field showing the header URL
    /// of a playlist without an override has nothing to save.
    nonisolated static func isDirty(draft: String, playlist: Playlist) -> Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != storedURL(of: playlist)
    }

    private var draftTrimmed: String {
        epgURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        Self.isDirty(draft: epgURLDraft, playlist: playlist)
    }

    private func saveURL() async {
        let trimmed = draftTrimmed
        do {
            let override = Self.override(forDraft: trimmed)
            let saved = try await AppDatabase.shared.updatePlaylist(id: playlist.id) {
                $0.epgURLOverride = override
            }
            guard let updated = saved else { return }
            saveError = nil
            playlist = updated
            // With the override cleared the header URL is the one in effect again:
            // show it instead of an empty field. Not over text typed meanwhile.
            if draftTrimmed == trimmed {
                epgURLDraft = Self.storedURL(of: updated)
            }
            if !Self.storedURL(of: updated).isEmpty {
                await EPGStore.shared.forceRefresh(playlist: updated)
            } else {
                // No URL left: nothing to download, but the store has to learn
                // that this playlist no longer expects a guide.
                await EPGStore.shared.refreshIfStale(playlist: updated)
            }
            // After the download above, so the store's own staleness check finds
            // the guide current instead of fetching it a second time.
            await EPGStore.shared.setGuideEnabled(updated.epgEnabled, playlist: updated)
        } catch {
            saveError = L("misc.save_setting_error", error.localizedDescription)
        }
    }
}

// MARK: - Xtream section (enable toggle + refresh)

struct XtreamEPGSettingsSection: View {
    /// The settings form's copy of the stored row; a save hands the saved row back.
    @Binding var playlist: Playlist
    /// The switch position while its save is on the way; nil follows the row.
    @State private var pendingEnabled: Bool?
    /// Counts the saves, so only the latest one hands the switch back to the row:
    /// with two quick flips the first answer would otherwise flip it back for a
    /// moment.
    @State private var saveGeneration = 0
    @State private var matchedChannels: Int?
    @ObservedObject private var epgStore = EPGStore.shared

    init(playlist: Binding<Playlist>) {
        _playlist = playlist
    }

    private var epgEnabled: Bool { pendingEnabled ?? playlist.epgEnabled }

    var body: some View {
        Section {
            // Animated, so the rows under the switch slide in and out.
            Toggle(L("epg.settings.enable"), isOn: enabledBinding.animation())

            if epgEnabled {
                EPGRefreshStatusView(playlist: playlist)
                if let matched = matchedChannels {
                    LabeledContent(
                        L("epg.settings.matched_channels"),
                        value: L("epg.settings.matched_channels_format", matched)
                    )
                }
            }
        } header: {
            Text(L("epg.settings.section_title"))
        }
        .task { await loadMatchedChannels() }
        .onChange(of: epgStore.refreshState[playlist.id]) { oldValue, newValue in
            if oldValue?.isRefreshing == true, newValue?.isRefreshing != true {
                Task { await loadMatchedChannels() }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { epgEnabled },
            set: { newValue in
                pendingEnabled = newValue
                saveGeneration += 1
                let generation = saveGeneration
                Task { await saveEnabled(newValue, generation: generation) }
            }
        )
    }

    private func loadMatchedChannels() async {
        let pid = playlist.id
        matchedChannels = try? await AppDatabase.shared.read { db in
            try DBEPGSource.fetchOne(db, key: pid)?.channelCount
        } ?? nil
    }

    private func saveEnabled(_ enabled: Bool, generation: Int) async {
        let saved = try? await AppDatabase.shared.updatePlaylist(id: playlist.id) {
            $0.epgEnabled = enabled
        }
        if let saved { playlist = saved }
        // A failed save leaves the row as it was, and the switch goes back to it.
        if generation == saveGeneration {
            withAnimation { pendingEnabled = nil }
        }
        guard let saved else { return }
        // On brings the stored guide back and refreshes it when stale; off takes
        // the now/next lines and the timer away at once.
        await EPGStore.shared.setGuideEnabled(saved.epgEnabled, playlist: saved)
        // The store re-reads the row to learn that the guide is no longer
        // expected, and starts no download in that case.
        if !saved.epgEnabled {
            await EPGStore.shared.refreshIfStale(playlist: saved)
        }
    }
}
