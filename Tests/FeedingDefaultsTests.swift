import XCTest
import SwiftData
@testable import BabyBuddy

final class FeedingDefaultsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var domain: String!

    override func setUp() {
        domain = "FeedingDefaultsTests.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: domain) }

    func testExistingDefaultIsPreservedUntilOptIn() {
        defaults.set("formula", forKey: FeedingDefaults.typeKey)
        defaults.set("bottle", forKey: FeedingDefaults.methodKey)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).type, .breastMilk)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).method, .leftBreast)
    }

    func testFixedChoicesAreReadAndNotReplacedBySave() {
        defaults.set("fixed", forKey: FeedingDefaults.modeKey)
        defaults.set("formula", forKey: FeedingDefaults.typeKey)
        defaults.set("bottle", forKey: FeedingDefaults.methodKey)
        FeedingDefaults.remember(type: .breastMilk, method: .leftBreast, in: defaults)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).type, .formula)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).method, .bottle)
    }

    func testRememberModeUpdatesOnlyTypeAndMethod() {
        defaults.set("remember", forKey: FeedingDefaults.modeKey)
        FeedingDefaults.remember(type: .formula, method: .bottle, in: defaults)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).type, .formula)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).method, .bottle)
        XCTAssertEqual(Set(defaults.persistentDomain(forName: domain)!.keys),
                       [FeedingDefaults.modeKey, FeedingDefaults.typeKey, FeedingDefaults.methodKey])
    }

    func testInvalidStoredValuesFallBack() {
        defaults.set("fixed", forKey: FeedingDefaults.modeKey)
        defaults.set("unknown", forKey: FeedingDefaults.typeKey)
        defaults.set("unknown", forKey: FeedingDefaults.methodKey)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).type, .breastMilk)
        XCTAssertEqual(FeedingDefaults.choices(in: defaults).method, .leftBreast)
        defaults.set("unknown", forKey: FeedingDefaults.modeKey)
        FeedingDefaults.remember(type: .formula, method: .bottle, in: defaults)
        XCTAssertEqual(defaults.string(forKey: FeedingDefaults.typeKey), "unknown")
    }

    @MainActor
    func testLeavingServerClearsPreferences() {
        let keys = [FeedingDefaults.modeKey, FeedingDefaults.typeKey, FeedingDefaults.methodKey]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        let child = SharedDefaults.selectedChildID
        defer {
            for (key, value) in zip(keys, previous) { UserDefaults.standard.set(value, forKey: key) }
            SharedDefaults.selectedChildID = child
        }
        UserDefaults.standard.set("remember", forKey: FeedingDefaults.modeKey)
        FeedingDefaults.remember(type: .formula, method: .bottle)
        let container = LocalStore.makeContainer(inMemory: true)
        LocalStore.wipe(in: container.mainContext)
        for key in keys { XCTAssertNil(UserDefaults.standard.object(forKey: key)) }
    }
}
