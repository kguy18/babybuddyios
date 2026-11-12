import Foundation
import SwiftData

/// A short-lived receipt for a successful local write, not a claim of server synchronization.
/// It contains IDs only and is cleared when leaving the server.
struct QuickLogReceipt: Codable, Equatable {
    let action: QuickLogAction
    let entityID: UUID
    let childID: Int
    let savedAt: Date
    var expiresAt: Date { savedAt.addingTimeInterval(120) }
}

enum QuickLogFeedback {
    static let receiptKey = "quickLog.savedReceipt"
    static let enabledKey = "quickLog.showConfirmation"

    static func record(action: QuickLogAction, entityID: UUID, childID: Int, now: Date,
                       in defaults: UserDefaults = SharedDefaults.suite) {
        let receipt = QuickLogReceipt(action: action, entityID: entityID, childID: childID, savedAt: now)
        defaults.set(try? JSONEncoder().encode(receipt), forKey: receiptKey)
    }

    static func visible(in context: ModelContext, childID: Int?, now: Date,
                        defaults: UserDefaults = SharedDefaults.suite) -> QuickLogReceipt? {
        guard defaults.object(forKey: enabledKey) as? Bool ?? true,
              let data = defaults.data(forKey: receiptKey),
              let receipt = try? JSONDecoder().decode(QuickLogReceipt.self, from: data),
              receipt.childID == childID, now >= receipt.savedAt, now < receipt.expiresAt else { return nil }
        let id = receipt.entityID
        guard let entity = try? context.fetch(FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.localID == id })).first,
              entity.childID == childID, entity.kind == receipt.action.kind,
              entity.syncState != .pendingDelete else { return nil }
        return receipt
    }

    static func clear(in defaults: UserDefaults = SharedDefaults.suite) {
        defaults.removeObject(forKey: receiptKey)
    }
}
