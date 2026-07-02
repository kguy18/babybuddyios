import XCTest
@testable import BabyBuddy

/// Covers the centralized feature-gating rules: premium/trial unlock everything, free users get only
/// feeding + diapers, the free/premium catalog split, and the `EntityKind → PremiumFeature` map that
/// drives the editor gate.
final class FeatureAccessTests: XCTestCase {

    // MARK: Tiering truth table

    func testPremiumUnlocksEveryFeature() {
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(FeatureAccess.isUnlocked(feature: feature, hasPremium: true, isTrial: false),
                          "\(feature) should be unlocked for premium")
        }
    }

    func testTrialUnlocksEveryFeature() {
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(FeatureAccess.isUnlocked(feature: feature, hasPremium: false, isTrial: true),
                          "\(feature) should be unlocked during trial")
        }
    }

    func testPremiumAndTrialTogetherUnlockEverything() {
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(FeatureAccess.isUnlocked(feature: feature, hasPremium: true, isTrial: true))
        }
    }

    func testFreeUnlocksOnlyFeedingAndDiapers() {
        for feature in PremiumFeature.allCases {
            let expected = (feature == .feeding || feature == .diapers)
            XCTAssertEqual(
                FeatureAccess.isUnlocked(feature: feature, hasPremium: false, isTrial: false),
                expected,
                "\(feature) free-tier access should be \(expected)")
        }
    }

    func testHasProReflectsPremiumOrTrial() {
        XCTAssertTrue(FeatureAccess.hasPro(hasPremium: true, isTrial: false))
        XCTAssertTrue(FeatureAccess.hasPro(hasPremium: false, isTrial: true))
        XCTAssertTrue(FeatureAccess.hasPro(hasPremium: true, isTrial: true))
        XCTAssertFalse(FeatureAccess.hasPro(hasPremium: false, isTrial: false))
    }

    // MARK: Catalog split

    func testFreeFeaturesAreExactlyFeedingAndDiapers() {
        XCTAssertEqual(FeatureAccess.freeFeatures, [.feeding, .diapers])
    }

    func testPremiumFeaturesAreTheComplementOfFree() {
        XCTAssertFalse(FeatureAccess.premiumFeatures.contains(.feeding))
        XCTAssertFalse(FeatureAccess.premiumFeatures.contains(.diapers))
        // Every case is accounted for exactly once across the two sets.
        XCTAssertEqual(
            Set(FeatureAccess.premiumFeatures).union(FeatureAccess.freeFeatures),
            Set(PremiumFeature.allCases))
        XCTAssertEqual(
            FeatureAccess.premiumFeatures.count + FeatureAccess.freeFeatures.count,
            PremiumFeature.allCases.count)
    }

    func testEveryFeatureHasDisplayMetadata() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.summary.isEmpty)
            XCTAssertFalse(feature.systemImage.isEmpty)
        }
    }

    // MARK: EntityKind → PremiumFeature mapping

    func testEntityKindPremiumMapping() {
        XCTAssertEqual(EntityKind.feeding.premiumFeature, .feeding)
        XCTAssertEqual(EntityKind.change.premiumFeature, .diapers)
        XCTAssertEqual(EntityKind.sleep.premiumFeature, .sleep)
        XCTAssertEqual(EntityKind.tummyTime.premiumFeature, .tummyTime)
        XCTAssertEqual(EntityKind.pumping.premiumFeature, .pumping)
        XCTAssertEqual(EntityKind.note.premiumFeature, .notes)
        XCTAssertEqual(EntityKind.timer.premiumFeature, .timers)
        XCTAssertEqual(EntityKind.weight.premiumFeature, .measurements)
        XCTAssertEqual(EntityKind.height.premiumFeature, .measurements)
        XCTAssertEqual(EntityKind.headCircumference.premiumFeature, .measurements)
        XCTAssertEqual(EntityKind.bmi.premiumFeature, .measurements)
        XCTAssertEqual(EntityKind.temperature.premiumFeature, .measurements)
        XCTAssertNil(EntityKind.medication.premiumFeature) // not in the catalog → ungated
        XCTAssertNil(EntityKind.child.premiumFeature)      // not a gated activity
    }

    /// End-to-end gate as the editor computes it: kind → feature → free-tier access.
    func testFreeTierGatingThroughEntityKind() {
        func unlockedForFree(_ kind: EntityKind) -> Bool {
            guard let feature = kind.premiumFeature else { return true } // ungated kinds are free
            return FeatureAccess.isUnlocked(feature: feature, hasPremium: false, isTrial: false)
        }
        // Free / ungated:
        XCTAssertTrue(unlockedForFree(.feeding))
        XCTAssertTrue(unlockedForFree(.change))
        XCTAssertTrue(unlockedForFree(.medication))
        // Premium:
        XCTAssertFalse(unlockedForFree(.sleep))
        XCTAssertFalse(unlockedForFree(.pumping))
        XCTAssertFalse(unlockedForFree(.tummyTime))
        XCTAssertFalse(unlockedForFree(.note))
        XCTAssertFalse(unlockedForFree(.timer))
        XCTAssertFalse(unlockedForFree(.weight))
    }
}
