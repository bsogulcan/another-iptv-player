import SwiftUI

/// macOS native Settings penceresi (Cmd+, ile açılır).
/// Genel uygulama düzeyinde tercihler — playlist-bağımsız.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            PlaybackSettingsTab()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }

            SyncSettingsTab()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @AppStorage("dashboard.selectedSection.v2") private var savedSection: String = "live"

    var body: some View {
        Form {
            Section("Language") {
                Picker("Application language", selection: $localization.selectedLanguage) {
                    Text(L("settings.language.system")).tag("system")
                    ForEach(LocalizationManager.supportedLanguages) { lang in
                        if lang.code != "system" {
                            Text(lang.nativeName).tag(lang.code)
                        }
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Startup") {
                LabeledContent("Default section") {
                    Text(savedSection.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlaybackSettingsTab: View {
    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continueInBackground = true
    @AppStorage("player.videoAspectMode") private var aspectRaw = VideoAspectMode.bestFit.rawValue
    @AppStorage("player.volume") private var savedVolume: Double = 100

    var body: some View {
        Form {
            Section("Player") {
                Toggle("Continue playback when window is hidden", isOn: $continueInBackground)
                Toggle("Picture-in-Picture (coming soon)", isOn: $pipEnabled)
                    .disabled(true)
            }

            Section("Default video aspect") {
                Picker("Aspect", selection: $aspectRaw) {
                    ForEach(VideoAspectMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $savedVolume, in: 0...100)
                    Image(systemName: "speaker.wave.3.fill")
                    Text("\(Int(savedVolume))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Self-hosted sync (favorites / watch progress / hidden categories across
/// devices) — see `services/sync-server` in the repo root. Fully optional:
/// everything else in the app works the same whether or not the user ever
/// opens this tab. Plain English strings, matching the other tabs in this
/// file (unlike the rest of the app, this Settings window isn't localized).
private struct SyncSettingsTab: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    @State private var selectedBackend: SyncBackend
    @State private var connected: Bool
    @State private var serverURL: String
    @State private var username = ""
    @State private var password = ""
    @State private var deviceName = ProcessInfo.processInfo.hostName
    @State private var busy = false
    @State private var formError: String?

    @State private var pending = 0
    @State private var autoSync: Bool
    @State private var interval: Int
    @State private var devices: [SyncDeviceInfo] = []

    init() {
        _selectedBackend = State(initialValue: SyncEngine.shared.syncBackend)
        _connected = State(initialValue: SyncEngine.shared.serverURL != nil && SyncEngine.shared.deviceToken != nil)
        _serverURL = State(initialValue: SyncEngine.shared.serverURL ?? "")
        _autoSync = State(initialValue: SyncEngine.shared.autoSyncEnabled)
        _interval = State(initialValue: SyncEngine.shared.intervalMinutes)
    }

    var body: some View {
        Form {
            Section("Sync Backend") {
                Picker("Sync via", selection: $selectedBackend) {
                    Text("Off").tag(SyncBackend.none)
                    Text("Self-Hosted Server").tag(SyncBackend.server)
                    Text("iCloud").tag(SyncBackend.icloud)
                }
                .onChange(of: selectedBackend) { _, newValue in
                    formError = nil
                    switch newValue {
                    case .none:
                        syncEngine.syncBackend = .none
                        syncEngine.stopPeriodicSync()
                    case .server:
                        if connected {
                            syncEngine.syncBackend = .server
                            syncEngine.startPeriodicSync()
                            syncEngine.runSync()
                        }
                    case .icloud:
                        if syncEngine.cloudSyncEnabled {
                            syncEngine.syncBackend = .icloud
                            syncEngine.startPeriodicSync()
                            syncEngine.runSync()
                        }
                    }
                }
            }

            backendSections
        }
        .formStyle(.grouped)
        .task { await refreshPending() }
        .onChange(of: syncEngine.status) { _, _ in
            Task { await refreshPending() }
        }
    }

    @ViewBuilder
    private var backendSections: some View {
        switch selectedBackend {
        case .none:
            EmptyView()
        case .server:
            if !connected {
                Section("Sync Across Devices") {
                    Text("Connect to your self-hosted sync server to keep favorites and watch progress in sync across devices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Server URL", text: $serverURL)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("Device Name", text: $deviceName)
                    HStack {
                        Button("Sign In") {
                            Task { await submit(alsoRegister: false) }
                        }
                        .disabled(busy)
                        Button("Create Account") {
                            Task { await submit(alsoRegister: true) }
                        }
                        .disabled(busy)
                    }
                    if busy { ProgressView() }
                    if let formError {
                        Text(formError).font(.caption).foregroundStyle(.red)
                    }
                }
            } else {
                Section("Sync Across Devices") {
                    LabeledContent("Server URL") {
                        Text(syncEngine.serverURL ?? "").foregroundStyle(.secondary)
                    }
                    LabeledContent("Account") {
                        Text(syncEngine.accountUsername ?? "").foregroundStyle(.secondary)
                    }
                    LabeledContent("Status") {
                        Text(statusText).foregroundStyle(.secondary)
                    }
                    if pending > 0 {
                        Text("\(pending) change(s) waiting to sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Sync Automatically", isOn: $autoSync)
                        .onChange(of: autoSync) { _, newValue in
                            syncEngine.autoSyncEnabled = newValue
                            syncEngine.startPeriodicSync()
                        }
                    Picker("Sync Frequency", selection: $interval) {
                        Text("Manual Only").tag(0)
                        Text("Every 15 min").tag(15)
                        Text("Every 30 min").tag(30)
                        Text("Every 60 min").tag(60)
                    }
                    .onChange(of: interval) { _, newValue in
                        syncEngine.intervalMinutes = newValue
                        syncEngine.startPeriodicSync()
                    }
                }

                if !devices.isEmpty {
                    Section("Connected Devices") {
                        ForEach(devices) { device in
                            HStack {
                                Text(device.deviceName + (device.current ? " (this device)" : ""))
                                Spacer()
                                if !device.current {
                                    Button("Remove", role: .destructive) {
                                        Task { await revoke(device) }
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Button("Sync Now") { syncEngine.runSync() }
                            .disabled(syncEngine.status == .syncing)
                        if syncEngine.status == .syncing { ProgressView() }
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await syncEngine.signOut()
                            connected = false
                            devices = []
                            selectedBackend = .none
                        }
                    }
                }
            }
        case .icloud:
            if !syncEngine.cloudSyncEnabled {
                Section("Sync Across Devices") {
                    Text("Sync favorites and watch progress via your iCloud account — no server required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Enable iCloud Sync") {
                        Task { await enableCloud() }
                    }
                    .disabled(busy)
                    if busy { ProgressView() }
                    if let formError {
                        Text(formError).font(.caption).foregroundStyle(.red)
                    }
                }
            } else {
                Section("Sync Across Devices") {
                    LabeledContent("Status") {
                        Text(statusText).foregroundStyle(.secondary)
                    }
                    if pending > 0 {
                        Text("\(pending) change(s) waiting to sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Sync Automatically", isOn: $autoSync)
                        .onChange(of: autoSync) { _, newValue in
                            syncEngine.autoSyncEnabled = newValue
                            syncEngine.startPeriodicSync()
                        }
                    Picker("Sync Frequency", selection: $interval) {
                        Text("Manual Only").tag(0)
                        Text("Every 15 min").tag(15)
                        Text("Every 30 min").tag(30)
                        Text("Every 60 min").tag(60)
                    }
                    .onChange(of: interval) { _, newValue in
                        syncEngine.intervalMinutes = newValue
                        syncEngine.startPeriodicSync()
                    }
                }

                Section {
                    HStack {
                        Button("Sync Now") { syncEngine.runSync() }
                            .disabled(syncEngine.status == .syncing)
                        if syncEngine.status == .syncing { ProgressView() }
                    }
                    Button("Turn Off iCloud Sync", role: .destructive) {
                        syncEngine.disableCloudSync()
                        selectedBackend = .none
                    }
                }
            }
        }
    }

    private func enableCloud() async {
        formError = nil
        busy = true
        defer { busy = false }
        do {
            try await syncEngine.enableCloudSync()
        } catch {
            formError = error.localizedDescription
        }
    }

    private var statusText: String {
        switch syncEngine.status {
        case .syncing:
            return "Syncing…"
        case .error(let message):
            return "Error: \(message)"
        case .idle:
            if let lastSyncedAt = syncEngine.lastSyncedAt {
                return "Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Never synced yet"
        }
    }

    private func submit(alsoRegister: Bool) async {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedUsername.isEmpty, !password.isEmpty else {
            formError = "Enter a server URL, username, and password."
            return
        }
        formError = nil
        busy = true
        defer { busy = false }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if alsoRegister {
                try await syncEngine.register(serverURL: trimmedURL, username: trimmedUsername, password: password)
            }
            try await syncEngine.signIn(
                serverURL: trimmedURL,
                username: trimmedUsername,
                password: password,
                deviceName: name.isEmpty ? "Mac" : name
            )
            password = ""
            connected = true
            selectedBackend = .server
            await loadDevices()
        } catch {
            formError = error.localizedDescription
        }
    }

    private func refreshPending() async {
        guard syncEngine.isConfigured else { return }
        pending = await syncEngine.outboxCount()
    }

    private func loadDevices() async {
        guard connected else { return }
        devices = (try? await syncEngine.listDevices()) ?? devices
    }

    private func revoke(_ device: SyncDeviceInfo) async {
        try? await syncEngine.revokeDevice(device.id)
        await loadDevices()
    }
}

private struct AboutSettingsTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("another-iptv-player")
                .font(.title2.weight(.semibold))
            Text("Version \(version) (build \(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Native macOS port of another-iptv-player.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
