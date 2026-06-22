import SwiftUI
import SwiftData

/// Server/account management, sync status, and (from Phase 6) Face ID + conflict inbox.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(AppLockManager.self) private var lock

    @Query private var pendingMutations: [PendingMutation]
    @Query private var conflicts: [ConflictRecord]
    @State private var debugConflict: ConflictRecord?
    @State private var debugIcons = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    if case .authenticated(let config) = session.state {
                        LabeledContent("Address", value: config.baseURL.host() ?? config.baseURL.absoluteString)
                    }
                }

                Section("Sync") {
                    LabeledContent("Status") { syncStatusLabel }
                    if let last = sync.lastSyncDate {
                        LabeledContent("Last synced", value: last.formatted(.relative(presentation: .named)))
                    }
                    LabeledContent("Pending changes", value: "\(pendingMutations.count)")
                    Button("Sync Now") { Task { await sync.sync() } }
                        .disabled(sync.status == .syncing)
                }

                if !conflicts.isEmpty {
                    Section {
                        NavigationLink {
                            ConflictInboxView()
                        } label: {
                            Label("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") to resolve",
                                  systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Toggle("Require Face ID / Passcode", isOn: Binding(
                        get: { lock.isEnabled },
                        set: { lock.isEnabled = $0 }))
                    .disabled(!lock.biometryAvailable)
                } header: {
                    Text("Security")
                } footer: {
                    if !lock.biometryAvailable {
                        Text("Set up Face ID, Touch ID, or a device passcode to enable app lock.")
                    } else {
                        Text("Locks the app when reopened after being in the background.")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { session.signOut() }
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $debugConflict) { c in
                NavigationStack { ConflictResolutionView(conflict: c) }
            }
            .sheet(isPresented: $debugIcons) {
                #if DEBUG
                NavigationStack { IconGalleryView() }
                #endif
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["BB_OPEN_CONFLICT"] == "1" {
                    debugConflict = conflicts.first
                }
                if ProcessInfo.processInfo.environment["BB_ICONS"] == "1" {
                    debugIcons = true
                }
                #endif
            }
        }
    }

    @ViewBuilder private var syncStatusLabel: some View {
        switch sync.status {
        case .idle: Text("Up to date").foregroundStyle(.secondary)
        case .syncing: HStack { ProgressView(); Text("Syncing…") }
        case .failed(let message): Text(message).foregroundStyle(.red).font(.caption)
        }
    }
}
