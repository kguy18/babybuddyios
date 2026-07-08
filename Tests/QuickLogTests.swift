import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class QuickLogTests: XCTestCase {
    /// Each action fixes a `wet`/`solid` pair with at least one `true` (so it's a real change,
    /// matching Baby Buddy's diaper form), and carries the child + a parseable time.
    func testPayloadFlagsPerAction() {
        let expected: [(action: QuickLogAction, wet: Bool, solid: Bool)] = [
            (.wetDiaper, true, false),
            (.solidDiaper, false, true),
            (.wetAndSolidDiaper, true, true),
        ]
        for (action, wet, solid) in expected {
            let payload = action.payload(childID: 5, now: .now)
            XCTAssertEqual(payload["wet"] as? Bool, wet, "\(action.rawValue) wet")
            XCTAssertEqual(payload["solid"] as? Bool, solid, "\(action.rawValue) solid")
            XCTAssertTrue((payload["wet"] as? Bool ?? false) || (payload["solid"] as? Bool ?? false),
                          "\(action.rawValue) must set at least one of wet/solid")
            XCTAssertEqual(payload["child"] as? Int, 5, "\(action.rawValue) child")
            let time = payload["time"] as? String
            XCTAssertNotNil(time, "\(action.rawValue) time present")
            XCTAssertNotNil(time.flatMap(APIDate.parse), "\(action.rawValue) time parseable")
        }
    }

    /// The Quick Log widget relies on `LocalRepository.create` turning a diaper payload into a
    /// pending-create change with the right child — mirror the payload the intent builds.
    func testQuickLogEnqueuesPendingCreate() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        LocalRepository(context: context).create(
            kind: .change, payload: QuickLogAction.wetDiaper.payload(childID: 3, now: .now))

        let changes = try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "change" }))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.childID, 3)
        XCTAssertEqual(changes.first?.syncState, .pendingCreate)
        XCTAssertNotEqual(changes.first?.timestamp, .distantPast) // time parsed → real timestamp

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.op, .create)
        XCTAssertEqual(mutations.first?.kind, .change)
    }
}
