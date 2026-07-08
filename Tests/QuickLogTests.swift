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

    /// The diaper actions log changes; `quickFeed` logs a feeding — its `kind` routes the intent
    /// to the right collection.
    func testActionKinds() {
        XCTAssertEqual(QuickLogAction.wetDiaper.kind, .change)
        XCTAssertEqual(QuickLogAction.solidDiaper.kind, .change)
        XCTAssertEqual(QuickLogAction.wetAndSolidDiaper.kind, .change)
        XCTAssertEqual(QuickLogAction.quickFeed.kind, .feeding)
    }

    /// `quickFeed` builds a `feedings` body with the fixed one-tap defaults (breast milk / both
    /// breasts, start = end = now) and none of the diaper fields. Baby Buddy requires child +
    /// start + end + type + method on a feeding; amount is optional and omitted here.
    func testQuickFeedPayloadUsesFeedingDefaults() {
        let payload = QuickLogAction.quickFeed.payload(childID: 7, now: .now)
        XCTAssertEqual(payload["child"] as? Int, 7)
        XCTAssertEqual(payload["type"] as? String, FeedingType.breastMilk.rawValue)     // "breast milk"
        XCTAssertEqual(payload["method"] as? String, FeedingMethod.bothBreasts.rawValue) // "both breasts"

        let start = payload["start"] as? String
        let end = payload["end"] as? String
        XCTAssertNotNil(start.flatMap(APIDate.parse), "start parseable")
        XCTAssertNotNil(end.flatMap(APIDate.parse), "end parseable")
        XCTAssertEqual(start, end, "one-tap feed is zero-length: start == end == now")

        // A feeding payload carries none of the diaper-change fields.
        XCTAssertNil(payload["wet"])
        XCTAssertNil(payload["solid"])
        XCTAssertNil(payload["time"])
    }

    /// The feed tile relies on `LocalRepository.create` turning the feeding payload into a
    /// pending-create feeding with the right child — mirror the payload the intent builds.
    func testQuickFeedEnqueuesPendingCreateFeeding() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        LocalRepository(context: context).create(
            kind: .feeding, payload: QuickLogAction.quickFeed.payload(childID: 4, now: .now))

        let feedings = try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "feeding" }))
        XCTAssertEqual(feedings.count, 1)
        XCTAssertEqual(feedings.first?.childID, 4)
        XCTAssertEqual(feedings.first?.syncState, .pendingCreate)
        XCTAssertNotEqual(feedings.first?.timestamp, .distantPast) // start parsed → real timestamp

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.op, .create)
        XCTAssertEqual(mutations.first?.kind, .feeding)
    }
}
