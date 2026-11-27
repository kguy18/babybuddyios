import Foundation
import SwiftData

extension ChildStatus {
    /// What ``compute(from:childID:now:)`` and the forecast read for one child: that child's own
    /// rows and its child record. The status widget fetched every row of every child before,
    /// which grows with the whole history and an extension has little memory to spare.
    static func fetchDescriptor(childID: Int) -> FetchDescriptor<LocalEntity> {
        let childKind = EntityKind.child.rawValue
        return FetchDescriptor(predicate: #Predicate<LocalEntity> {
            $0.childID == childID || ($0.kindRaw == childKind && $0.serverID == childID)
        })
    }
}
