import Foundation

/// Which compiled set of strings the supporter sheet speaks in.
///
/// The remote config names a variant; it never carries display text. Copy ships in the binary so it
/// can be reviewed, localized, and proof-read like the rest of the app — a dashboard field that
/// could put arbitrary words in front of a customer, mid-purchase, is not something worth having.
enum SupporterCopyVariant: String, CaseIterable {
    /// The shipped copy: "The whole app is free, and stays that way."
    case standard
    /// A warmer, more personal phrasing of the same offer. Same length, same promise.
    case warm
}

/// Remote tuning for the supporter sheet and the support nudges, parsed from the serving RevenueCat
/// offering's metadata.
///
/// **This is a dial, not a dependency.** Every field is optional and every absent one falls back to
/// the compiled ``defaults`` — which are exactly the constants ``SupportNudgeManager`` shipped with.
/// A build with no RevenueCat key, an unreachable backend, an offering with no metadata, an
/// open-source clone, and `BB_DEMO` all behave identically to having no remote config at all. No
/// dashboard change is ever *required*; this only exists so cadence and copy can be tuned — and
/// later A/B tested through RevenueCat Experiments serving variant offerings — without shipping a
/// build.
///
/// Metadata lives under a single top-level key so the offering's metadata stays available for
/// anything else later. The schema, all keys optional:
///
/// ```json
/// {
///   "supporterConfig": {
///     "nudgesEnabled":    true,                  // false is the kill switch — quiets everything
///     "firstAskDay":      7,                     // days after first launch before any ask
///     "minLoggedEntries": 10,                    // records logged on this device before any ask
///     "milestones":       [50, 100, 250, 500, 1000],  // strictly ascending
///     "capDays":          21,                    // minimum days between any two nudges
///     "snoozeDays":       21,                    // minimum days between asks once one was refused
///     "maxDismissals":    3,                     // refusals after which the popups retire for good
///     "bannerCapDays":    30,                    // the retired-state banner's own window
///     "defaultTier":      "medium",              // "small" | "medium" | "large" — preselected amount
///     "copyVariant":      "standard"             // a NAMED variant; never display text
///   }
/// }
/// ```
///
/// Parsing is defensive in both directions. Anything malformed — a wrong type, a missing key, a
/// milestone list that isn't ascending — silently keeps the compiled default rather than failing or
/// disabling anything. And the day windows are clamped to the absolute floors in ``Floor``, so a
/// typo in the dashboard (`"capDays": 2`) can shorten the respectful spacing but can never abolish
/// it. The one field that isn't clamped upward is ``nudgesEnabled``: `false` silences everything,
/// which is only ever safer.
struct SupporterRemoteConfig: Equatable {
    /// Master switch for the support nudges. `false` silences every surface, permanently, until it
    /// goes back. The compiled default is `true` — the nudges ship on.
    var nudgesEnabled: Bool
    /// Days after this device's first launch before any nudge may appear.
    var firstAskDay: Int
    /// Records logged on this device before any nudge may appear.
    var minLoggedEntries: Int
    /// Entry counts that earn a celebratory milestone ask, strictly ascending. Empty means no
    /// milestone asks at all — quieter, and therefore allowed.
    var milestones: [Int]
    /// The global cap: no two nudges of any variant closer together than this many days.
    var capDays: Int
    /// The longer quiet window that applies once someone has actually turned a nudge down. Only ever
    /// lengthens the gap — see ``SupportNudgeManager``.
    var snoozeDays: Int
    /// Refusals after which the popups retire permanently, leaving only the quiet banner.
    var maxDismissals: Int
    /// The retired-state banner's own, longer window, in days.
    var bannerCapDays: Int
    /// The amount the supporter sheet preselects.
    var defaultTier: TipTier
    /// Which compiled copy the supporter sheet uses.
    var copyVariant: SupporterCopyVariant

    /// The top-level metadata key everything above hangs off.
    static let metadataKey = "supporterConfig"

    /// Absolute bounds no dashboard value may cross. These are the promise the nudge design makes to
    /// a new parent — that the app waits before it asks, and waits again after — expressed as
    /// numbers the client enforces rather than trusts. Tuning *within* them is the point of the
    /// dial; the floors are what stop a typo from turning it into nagging.
    enum Floor {
        /// A week is the intent; three days is the earliest a build will ever ask, whatever the
        /// dashboard says.
        static let firstAskDay = 3
        /// Never more than one interruption a week.
        static let capDays = 7
        /// A refusal buys at least a week of quiet.
        static let snoozeDays = 7
        /// The banner is the quietest surface, so it gets the longest floor.
        static let bannerCapDays = 14
    }

    /// The compiled defaults — what the app does with no metadata at all.
    ///
    /// Deliberately derived from ``SupportNudgeManager``'s own constants rather than restating them,
    /// so "no remote config behaves exactly like the nudge policy as shipped" is true by
    /// construction and can't drift when one side is edited.
    static let defaults = SupporterRemoteConfig(
        nudgesEnabled: true,
        firstAskDay: SupportNudgeManager.firstAskDays,
        minLoggedEntries: SupportNudgeManager.firstAskEntries,
        milestones: SupportNudgeManager.milestones,
        capDays: SupportNudgeManager.minimumIntervalDays,
        // The shipped policy has one interval doing both jobs, so the compiled snooze *is* the cap.
        // Splitting them here is what lets a refusal buy more quiet than the routine gap without
        // also slowing the routine gap down.
        snoozeDays: SupportNudgeManager.minimumIntervalDays,
        maxDismissals: SupportNudgeManager.retirementDismissals,
        bannerCapDays: SupportNudgeManager.bannerIntervalDays,
        defaultTier: .medium,
        copyVariant: .standard)
}

// MARK: - Parsing
//
// In an extension so the memberwise initializer survives — ``defaults`` is built with it, and it is
// what keeps the compiled values a plain list of numbers rather than a second parser.
extension SupporterRemoteConfig {
    /// Parse the config out of an offering's metadata, falling back to ``defaults`` for anything
    /// absent, malformed, or out of bounds. `nil` metadata — no offering, no key, purchases not
    /// configured — yields the defaults exactly.
    init(metadata: [String: Any]?) {
        self = .defaults
        guard let root = metadata?[Self.metadataKey] as? [String: Any] else { return }

        if let value = Self.bool(root["nudgesEnabled"]) { nudgesEnabled = value }

        // Day windows: clamped up to their floor, so a too-small value lands on the floor rather
        // than being thrown away. A non-numeric value keeps the compiled default.
        if let value = Self.int(root["firstAskDay"]) { firstAskDay = max(value, Floor.firstAskDay) }
        if let value = Self.int(root["capDays"]) { capDays = max(value, Floor.capDays) }
        if let value = Self.int(root["snoozeDays"]) { snoozeDays = max(value, Floor.snoozeDays) }
        if let value = Self.int(root["bannerCapDays"]) { bannerCapDays = max(value, Floor.bannerCapDays) }

        // Counts have no floor to defend — a larger value only delays or retires sooner — but a zero
        // or negative one is nonsense rather than a policy, so it keeps the default.
        if let value = Self.int(root["minLoggedEntries"]), value > 0 { minLoggedEntries = value }
        if let value = Self.int(root["maxDismissals"]), value > 0 { maxDismissals = value }

        if let value = Self.milestones(root["milestones"]) { milestones = value }
        if let raw = root["defaultTier"] as? String, let tier = TipTier(rawValue: raw) {
            defaultTier = tier
        }
        if let raw = root["copyVariant"] as? String, let variant = SupporterCopyVariant(rawValue: raw) {
            copyVariant = variant
        }
    }

    /// A milestone list, or `nil` if it isn't a usable one.
    ///
    /// Rejected wholesale rather than repaired: the thresholds are read as a set of moments worth
    /// celebrating, and a list that isn't strictly ascending means whoever typed it meant something
    /// we can't infer. An **empty** list is honoured, though — it means "no milestone asks", which
    /// is quieter than the default and so always safe.
    private static func milestones(_ value: Any?) -> [Int]? {
        guard let raw = value as? [Any] else { return nil }
        let values = raw.compactMap { int($0) }
        guard values.count == raw.count else { return nil }        // a non-numeric entry voids it
        guard values.allSatisfy({ $0 > 0 }) else { return nil }
        guard zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil } // ascending
        return values
    }

    /// An integer from JSON, however the dashboard typed it.
    ///
    /// Goes through `NSNumber` rather than `as? Int`, because JSON numbers arrive bridged and
    /// `as? Int` on a bridged `true` quietly succeeds with `1`. Being explicit keeps the type
    /// confusion where it can be seen (and clamped) instead of where it can't.
    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// A boolean from JSON, accepting the bridged number and the string spelling alike.
    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return Bool(string) }
        return nil
    }
}
