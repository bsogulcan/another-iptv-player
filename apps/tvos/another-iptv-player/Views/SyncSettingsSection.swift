import SwiftUI

/// Self-hosted sync (watch progress across devices today; favorites and
/// hidden categories once this platform has UI for them — see
/// `Models/SyncEngine.swift`) — see `services/sync-server` in the repo
/// root. Fully optional: everything else in the app works the same
/// whether or not the user ever opens this section.
struct SyncSettingsSection: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    @State private var connected: Bool
    @State private var serverURL: String
    @State private var username = ""
    @State private var password = ""
    @State private var deviceName = "Apple TV"
    @State private var busy = false
    @State private var formError: String?

    @State private var pending = 0
    @State private var autoSync: Bool
    @State private var interval: Int
    @State private var devices: [SyncDeviceInfo] = []

    init() {
        _connected = State(initialValue: SyncEngine.shared.isConfigured)
        _serverURL = State(initialValue: SyncEngine.shared.serverURL ?? "")
        _autoSync = State(initialValue: SyncEngine.shared.autoSyncEnabled)
        _interval = State(initialValue: SyncEngine.shared.intervalMinutes)
    }

    var body: some View {
        Section(L("settings.sync.title")) {
            if !connected {
                signInForm
            } else {
                connectedContent
            }
        }
        .task { await refreshPending() }
        .onChange(of: syncEngine.status) { _, _ in
            Task { await refreshPending() }
        }
    }

    // MARK: - Not connected

    private var signInForm: some View {
        Group {
            Text(L("settings.sync.intro"))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(L("settings.sync.server_url"), text: $serverURL)
            TextField(L("settings.sync.username"), text: $username)
            SecureField(L("settings.sync.password"), text: $password)
            TextField(L("settings.sync.device_name"), text: $deviceName)

            Button {
                Task { await submit(alsoRegister: false) }
            } label: {
                HStack {
                    Text(L("settings.sync.sign_in"))
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)

            Button {
                Task { await submit(alsoRegister: true) }
            } label: {
                Text(L("settings.sync.create_account"))
            }
            .disabled(busy)

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit(alsoRegister: Bool) async {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedUsername.isEmpty, !password.isEmpty else {
            formError = L("settings.sync.missing_fields")
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
                deviceName: name.isEmpty ? "Apple TV" : name
            )
            password = ""
            connected = true
            await loadDevices()
        } catch {
            formError = error.localizedDescription
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        Group {
            HStack {
                Text(L("settings.sync.server_url"))
                Spacer()
                Text(syncEngine.serverURL ?? "").foregroundStyle(.secondary)
            }
            HStack {
                Text(L("settings.sync.account"))
                Spacer()
                Text(syncEngine.accountUsername ?? "").foregroundStyle(.secondary)
            }
            HStack {
                Text(L("settings.sync.status"))
                Spacer()
                Text(statusText).foregroundStyle(.secondary)
            }
            if pending > 0 {
                Text(L("settings.sync.pending_items", pending))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $autoSync) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("settings.sync.auto_sync"))
                    Text(L("settings.sync.auto_sync_subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: autoSync) { _, newValue in
                syncEngine.autoSyncEnabled = newValue
                syncEngine.startPeriodicSync()
            }

            Picker(L("settings.sync.interval_title"), selection: $interval) {
                Text(L("settings.sync.interval_manual")).tag(0)
                Text(L("settings.sync.interval_minutes_format", 15)).tag(15)
                Text(L("settings.sync.interval_minutes_format", 30)).tag(30)
                Text(L("settings.sync.interval_minutes_format", 60)).tag(60)
            }
            .onChange(of: interval) { _, newValue in
                syncEngine.intervalMinutes = newValue
                syncEngine.startPeriodicSync()
            }

            ForEach(devices) { device in
                HStack {
                    Text(device.deviceName + (device.current ? " (\(L("settings.sync.this_device")))" : ""))
                    Spacer()
                    if !device.current {
                        Button {
                            Task { await revoke(device) }
                        } label: {
                            Text(L("settings.sync.remove"))
                        }
                    }
                }
            }

            Button {
                syncEngine.runSync()
            } label: {
                HStack {
                    Text(L("settings.sync.sync_now"))
                    Spacer()
                    if syncEngine.status == .syncing { ProgressView() }
                }
            }
            .disabled(syncEngine.status == .syncing)

            Button {
                Task {
                    await syncEngine.signOut()
                    connected = false
                    devices = []
                }
            } label: {
                Text(L("settings.sync.sign_out"))
            }
        }
    }

    private var statusText: String {
        switch syncEngine.status {
        case .syncing:
            return L("settings.sync.status_syncing")
        case .error(let message):
            return L("settings.sync.status_error", message)
        case .idle:
            if let lastSyncedAt = syncEngine.lastSyncedAt {
                return L("settings.sync.status_last_synced", lastSyncedAt.formatted(date: .abbreviated, time: .shortened))
            }
            return L("settings.sync.status_never")
        }
    }

    private func refreshPending() async {
        guard connected else { return }
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
