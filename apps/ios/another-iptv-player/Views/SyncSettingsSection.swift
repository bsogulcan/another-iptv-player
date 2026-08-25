import SwiftUI
import UIKit

/// Self-hosted sync (favorites / watch progress / hidden categories across
/// devices) — see `services/sync-server` in the repo root. Fully optional:
/// everything else in the app works the same whether or not the user ever
/// opens this section.
struct SyncSettingsSection: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    @State private var selectedBackend: SyncBackend
    @State private var connected: Bool
    @State private var serverURL: String
    @State private var username = ""
    @State private var password = ""
    @State private var deviceName = UIDevice.current.name
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
        Section(header: Text(L("settings.sync.title"))) {
            Picker(L("settings.sync.backend_title"), selection: $selectedBackend) {
                Text(L("settings.sync.backend_none")).tag(SyncBackend.none)
                Text(L("settings.sync.backend_server")).tag(SyncBackend.server)
                Text(L("settings.sync.backend_icloud")).tag(SyncBackend.icloud)
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

            backendContent
        }
        .task { await refreshPending() }
        .onChange(of: syncEngine.status) { _, _ in
            Task { await refreshPending() }
        }
    }

    @ViewBuilder
    private var backendContent: some View {
        switch selectedBackend {
        case .none:
            EmptyView()
        case .server:
            if !connected {
                signInForm
            } else {
                connectedContent
            }
        case .icloud:
            cloudContent
        }
    }

    // MARK: - Not connected

    private var signInForm: some View {
        Group {
            Text(L("settings.sync.intro"))
                .font(.footnote)
                .foregroundColor(.secondary)

            TextField(L("settings.sync.server_url"), text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField(L("settings.sync.username"), text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(L("settings.sync.password"), text: $password)

            TextField(L("settings.sync.device_name"), text: $deviceName)
                .textInputAutocapitalization(.words)

            HStack {
                Button(L("settings.sync.sign_in")) {
                    Task { await submit(alsoRegister: false) }
                }
                .disabled(busy)

                Button(L("settings.sync.create_account")) {
                    Task { await submit(alsoRegister: true) }
                }
                .disabled(busy)
            }

            if busy {
                ProgressView()
            }

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundColor(.red)
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
                deviceName: name.isEmpty ? "iOS" : name
            )
            password = ""
            connected = true
            selectedBackend = .server
            await loadDevices()
        } catch {
            formError = error.localizedDescription
        }
    }

    // MARK: - iCloud

    @ViewBuilder
    private var cloudContent: some View {
        if !syncEngine.cloudSyncEnabled {
            Group {
                Text(L("settings.sync.icloud_intro"))
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button {
                    Task { await enableCloud() }
                } label: {
                    HStack {
                        Text(L("settings.sync.icloud_enable"))
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy)

                if let formError {
                    Text(formError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        } else {
            Group {
                HStack {
                    Text(L("settings.sync.status"))
                    Spacer()
                    Text(statusText).foregroundColor(.secondary)
                }
                if pending > 0 {
                    Text(L("settings.sync.pending_items", pending))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(isOn: $autoSync) {
                    VStack(alignment: .leading, spacing: 2) {
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

                Button(role: .destructive) {
                    syncEngine.disableCloudSync()
                    selectedBackend = .none
                } label: {
                    Text(L("settings.sync.icloud_disable"))
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

    // MARK: - Connected

    private var connectedContent: some View {
        Group {
            HStack {
                Text(L("settings.sync.server_url"))
                Spacer()
                Text(syncEngine.serverURL ?? "").foregroundColor(.secondary)
            }
            HStack {
                Text(L("settings.sync.account"))
                Spacer()
                Text(syncEngine.accountUsername ?? "").foregroundColor(.secondary)
            }
            HStack {
                Text(L("settings.sync.status"))
                Spacer()
                Text(statusText).foregroundColor(.secondary)
            }
            if pending > 0 {
                Text(L("settings.sync.pending_items", pending))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $autoSync) {
                VStack(alignment: .leading, spacing: 2) {
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
                        Button(role: .destructive) {
                            Task { await revoke(device) }
                        } label: {
                            Text(L("settings.sync.remove"))
                        }
                    }
                }
                .font(.subheadline)
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

            Button(role: .destructive) {
                Task {
                    await syncEngine.signOut()
                    connected = false
                    devices = []
                    selectedBackend = .none
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
