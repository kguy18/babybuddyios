import SwiftUI
import SwiftData

/// Starts a new Baby Buddy timer (open-ended: start = now, no end). The timer is created
/// through ``LocalRepository`` like any other record, so it works offline and syncs when a
/// connection returns. A running timer can later be converted into an activity or stopped
/// from the dashboard's Active Timers card.
struct StartTimerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let childID: Int
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                } footer: {
                    Text("e.g. \u{201C}Tummy time\u{201D} or \u{201C}Feeding\u{201D}. The timer starts now and counts up until you convert or stop it.")
                }
                Section {
                    LabeledContent("Starts", value: Date.now.formatted(date: .omitted, time: .shortened))
                }
            }
            .navigationTitle("Start Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                }
            }
        }
    }

    private func start() {
        var payload: [String: Any] = [
            "child": childID,
            "start": APIDate.isoDateTime.string(from: .now),
        ]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["name"] = trimmed }
        LocalRepository(context: context).create(kind: .timer, payload: payload)
        Task { await sync.sync() }
        dismiss()
    }
}
