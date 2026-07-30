import XCTest
@testable import BabyBuddy

/// Covers ``SupporterRemoteConfig`` — the parsing of RevenueCat offering metadata into the supporter
/// sheet's and the support nudges' knobs.
///
/// Two things are being defended here, and they pull in opposite directions:
///
/// 1. **Nothing is required.** A build with no key, no offering, no metadata, or a malformed blob has
///    to behave *exactly* as the app did before any of this existed. That is the whole premise —
///    this is a tuning dial, not a dependency — so "absent → compiled defaults" is asserted field by
///    field rather than in aggregate.
/// 2. **Nothing typed in a dashboard can make the app nag.** The floors are the respectful-ask
///    promise expressed as numbers the client enforces instead of trusts, so every one of them is
///    tested from below.
final class SupporterRemoteConfigTests: XCTestCase {

    /// Wrap a config body in the top-level key the parser looks under.
    private func metadata(_ body: [String: Any]) -> [String: Any] {
        [SupporterRemoteConfig.metadataKey: body]
    }

    // MARK: - Absent → compiled defaults

    /// The premise of the whole feature: no metadata reachable, in any of the ways that can happen,
    /// and the app runs the policy it shipped with.
    func testAbsentMetadataYieldsTheCompiledDefaults() {
        XCTAssertEqual(SupporterRemoteConfig(metadata: nil), .defaults, "no offering at all")
        XCTAssertEqual(SupporterRemoteConfig(metadata: [:]), .defaults, "an offering with no metadata")
        XCTAssertEqual(SupporterRemoteConfig(metadata: ["somethingElse": 1]), .defaults,
                       "metadata that is about something else entirely")
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata([:])), .defaults,
                       "our key present but empty")
    }

    /// A wrong-typed top-level key must not take the parser down a half-applied path.
    func testMalformedTopLevelKeyYieldsTheDefaults() {
        XCTAssertEqual(SupporterRemoteConfig(metadata: [SupporterRemoteConfig.metadataKey: "nope"]),
                       .defaults)
        XCTAssertEqual(SupporterRemoteConfig(metadata: [SupporterRemoteConfig.metadataKey: [1, 2, 3]]),
                       .defaults)
    }

    /// The compiled defaults **are** the nudge policy's own constants. Asserted explicitly because
    /// this is the acceptance criterion for the whole change: with no metadata set, behaviour is
    /// identical to what the support-nudge work shipped. If someone edits one side, this fails.
    func testCompiledDefaultsMatchTheShippedNudgePolicy() {
        let defaults = SupporterRemoteConfig.defaults
        XCTAssertTrue(defaults.nudgesEnabled)
        XCTAssertEqual(defaults.firstAskDay, SupportNudgeManager.firstAskDays)
        XCTAssertEqual(defaults.minLoggedEntries, SupportNudgeManager.firstAskEntries)
        XCTAssertEqual(defaults.milestones, SupportNudgeManager.milestones)
        XCTAssertEqual(defaults.capDays, SupportNudgeManager.minimumIntervalDays)
        XCTAssertEqual(defaults.snoozeDays, SupportNudgeManager.minimumIntervalDays,
                       "the shipped policy has one interval doing both jobs")
        XCTAssertEqual(defaults.maxDismissals, SupportNudgeManager.retirementDismissals)
        XCTAssertEqual(defaults.bannerCapDays, SupportNudgeManager.bannerIntervalDays)
        XCTAssertEqual(defaults.defaultTier, .medium)
        XCTAssertEqual(defaults.copyVariant, .standard)
    }

    // MARK: - Partial → merge

    /// The common case in practice: one key set in the dashboard, everything else left alone.
    func testPartialMetadataMergesOverTheDefaults() {
        let config = SupporterRemoteConfig(metadata: metadata(["firstAskDay": 14]))
        XCTAssertEqual(config.firstAskDay, 14)

        var expected = SupporterRemoteConfig.defaults
        expected.firstAskDay = 14
        XCTAssertEqual(config, expected, "one key set must not disturb any other field")
    }

    func testEveryFieldCanBeSet() {
        let config = SupporterRemoteConfig(metadata: metadata([
            "nudgesEnabled": false,
            "firstAskDay": 10,
            "minLoggedEntries": 25,
            "milestones": [100, 500],
            "capDays": 30,
            "snoozeDays": 60,
            "maxDismissals": 2,
            "bannerCapDays": 45,
            "defaultTier": "large",
            "copyVariant": "warm",
        ]))
        XCTAssertEqual(config, SupporterRemoteConfig(
            nudgesEnabled: false, firstAskDay: 10, minLoggedEntries: 25,
            milestones: [100, 500], capDays: 30, snoozeDays: 60, maxDismissals: 2,
            bannerCapDays: 45, defaultTier: .large, copyVariant: .warm))
    }

    /// JSON from a dashboard field arrives however whoever typed it left it. Numbers bridged as
    /// `NSNumber` and numbers typed as strings must both work, or a config silently half-applies.
    func testNumbersParseWhetherBridgedOrTyped() {
        let bridged = SupporterRemoteConfig(metadata: metadata(["firstAskDay": NSNumber(value: 12)]))
        XCTAssertEqual(bridged.firstAskDay, 12)

        let stringly = SupporterRemoteConfig(metadata: metadata(["firstAskDay": "12",
                                                                "nudgesEnabled": "false"]))
        XCTAssertEqual(stringly.firstAskDay, 12)
        XCTAssertFalse(stringly.nudgesEnabled)
    }

    // MARK: - Invalid → default

    /// A wrong type keeps the compiled value rather than zeroing the field, which is the failure
    /// mode that would actually hurt: `firstAskDay = 0` is an app that asks on day one.
    func testWrongTypesKeepTheDefaults() {
        let config = SupporterRemoteConfig(metadata: metadata([
            "firstAskDay": "not a number",
            "milestones": "50,100",
            "defaultTier": "enormous",
            "copyVariant": "shakespearean",
            "minLoggedEntries": [1, 2],
        ]))
        XCTAssertEqual(config, .defaults)
    }

    /// Counts that are zero or negative are nonsense rather than policy, so they keep the default.
    /// `maxDismissals: 0` would retire the popups before a single ask; `minLoggedEntries: 0` would
    /// drop the "has this app done anything for you yet?" gate entirely.
    func testNonPositiveCountsKeepTheDefaults() {
        for value in [0, -5] {
            let config = SupporterRemoteConfig(metadata: metadata([
                "minLoggedEntries": value, "maxDismissals": value,
            ]))
            XCTAssertEqual(config.minLoggedEntries, SupporterRemoteConfig.defaults.minLoggedEntries)
            XCTAssertEqual(config.maxDismissals, SupporterRemoteConfig.defaults.maxDismissals)
        }
    }

    // MARK: - Out of bounds → clamped to the floors

    /// The heart of it: every day-window floor, approached from below and from absurdity.
    func testDayWindowsAreClampedToTheirFloors() {
        for value in [1, 0, -100] {
            let config = SupporterRemoteConfig(metadata: metadata([
                "firstAskDay": value,
                "capDays": value,
                "snoozeDays": value,
                "bannerCapDays": value,
            ]))
            XCTAssertEqual(config.firstAskDay, SupporterRemoteConfig.Floor.firstAskDay)
            XCTAssertEqual(config.capDays, SupporterRemoteConfig.Floor.capDays)
            XCTAssertEqual(config.snoozeDays, SupporterRemoteConfig.Floor.snoozeDays)
            XCTAssertEqual(config.bannerCapDays, SupporterRemoteConfig.Floor.bannerCapDays)
        }
    }

    /// A value on the floor is honoured, not bumped — the floor is a bound, not a default.
    func testValuesAtTheFloorAreKept() {
        let config = SupporterRemoteConfig(metadata: metadata([
            "firstAskDay": SupporterRemoteConfig.Floor.firstAskDay,
            "capDays": SupporterRemoteConfig.Floor.capDays,
            "snoozeDays": SupporterRemoteConfig.Floor.snoozeDays,
            "bannerCapDays": SupporterRemoteConfig.Floor.bannerCapDays,
        ]))
        XCTAssertEqual(config.firstAskDay, SupporterRemoteConfig.Floor.firstAskDay)
        XCTAssertEqual(config.capDays, SupporterRemoteConfig.Floor.capDays)
        XCTAssertEqual(config.snoozeDays, SupporterRemoteConfig.Floor.snoozeDays)
        XCTAssertEqual(config.bannerCapDays, SupporterRemoteConfig.Floor.bannerCapDays)
    }

    /// Lengthening a window is always allowed — quieter is never something to defend against.
    func testWindowsCanBeLengthenedFreely() {
        let config = SupporterRemoteConfig(metadata: metadata([
            "firstAskDay": 90, "capDays": 365, "snoozeDays": 365, "bannerCapDays": 365,
        ]))
        XCTAssertEqual(config.firstAskDay, 90)
        XCTAssertEqual(config.capDays, 365)
        XCTAssertEqual(config.snoozeDays, 365)
        XCTAssertEqual(config.bannerCapDays, 365)
    }

    // MARK: - Milestones

    func testMilestonesMustBeStrictlyAscending() {
        for bad in [[100, 50], [50, 50, 100], [50, 100, 90]] {
            XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["milestones": bad])).milestones,
                           SupporterRemoteConfig.defaults.milestones,
                           "\(bad) is not strictly ascending and must be rejected wholesale")
        }
    }

    func testMilestonesRejectNonPositiveAndNonNumericEntries() {
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["milestones": [0, 50]])).milestones,
                       SupporterRemoteConfig.defaults.milestones)
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["milestones": [-10, 50]])).milestones,
                       SupporterRemoteConfig.defaults.milestones)
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["milestones": [50, "x", 100]])).milestones,
                       SupporterRemoteConfig.defaults.milestones)
    }

    /// An empty list is a legitimate instruction — "no milestone asks" — and is quieter than the
    /// default, so unlike every other malformed case it is honoured rather than replaced.
    func testEmptyMilestoneListIsHonoured() {
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["milestones": [Int]()])).milestones, [])
    }

    // MARK: - The kill switch

    /// `nudgesEnabled: false` is the one field that overrides the others outright, and it can only
    /// ever quiet the app. Everything else stays parsed, so flipping it back restores the tuning.
    func testKillSwitchDisablesNudgesWithoutDiscardingTheRestOfTheConfig() {
        let config = SupporterRemoteConfig(metadata: metadata([
            "nudgesEnabled": false, "firstAskDay": 14, "defaultTier": "small",
        ]))
        XCTAssertFalse(config.nudgesEnabled)
        XCTAssertEqual(config.firstAskDay, 14)
        XCTAssertEqual(config.defaultTier, .small)
    }

    /// There is no "force the nudges on" — absent means the compiled default, which is already on.
    func testNudgesAreOnByDefault() {
        XCTAssertTrue(SupporterRemoteConfig(metadata: nil).nudgesEnabled)
        XCTAssertTrue(SupporterRemoteConfig(metadata: metadata(["nudgesEnabled": true])).nudgesEnabled)
    }

    // MARK: - Copy variants

    /// The metadata names a variant; the strings are compiled. An unknown name has to fall back
    /// rather than leave the sheet with nothing to say.
    func testCopyVariantsResolveByNameAndFallBack() {
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["copyVariant": "warm"])).copyVariant,
                       .warm)
        XCTAssertEqual(SupporterRemoteConfig(metadata: metadata(["copyVariant": "v3-final"])).copyVariant,
                       .standard)
    }

    /// Every compiled variant must actually have copy, and the ask must differ between them — a
    /// variant that renders identically is an experiment that can't produce a result.
    func testEveryCopyVariantHasDistinctNonEmptyAskCopy() {
        let titles = SupporterCopyVariant.allCases.map { SupporterCopy(variant: $0).askTitle }
        let bodies = SupporterCopyVariant.allCases.map { SupporterCopy(variant: $0).askBody }
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(bodies.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(titles).count, SupporterCopyVariant.allCases.count)
        XCTAssertEqual(Set(bodies).count, SupporterCopyVariant.allCases.count)
    }
}
