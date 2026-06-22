import SwiftUI
import SwiftData

/// Lists unresolved sync conflicts. Tapping one opens the resolution screen.
struct ConflictInboxView: View {
    @Query(sort: \ConflictRecord.detectedAt, order: .reverse) private var conflicts: [ConflictRecord]

    var body: some View {
        List {
            ForEach(conflicts) { conflict in
                NavigationLink {
                    ConflictResolutionView(conflict: conflict)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(conflict.kind.displayName, systemImage: conflict.kind.systemImage)
                            .font(.headline)
                        Text(conflict.serverDeleted
                             ? "Deleted on the server while you edited it"
                             : "Changed on the server and on this device")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Conflicts")
        .overlay {
            if conflicts.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle",
                    description: Text("Everything is in sync."))
            }
        }
    }
}
