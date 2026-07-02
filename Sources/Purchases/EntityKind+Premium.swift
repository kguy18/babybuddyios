import Foundation

extension EntityKind {
    /// The premium feature that gates **creating** a record of this kind, or `nil` when the kind is
    /// not gated (free to create, or not a user-created activity).
    ///
    /// This is the one place the record types map onto the ``PremiumFeature`` catalog, so gating
    /// stays consistent everywhere the shared editor is used. Editing an *existing* record is gated
    /// separately by ``PremiumFeature/timelineEditing``, regardless of the record's kind.
    var premiumFeature: PremiumFeature? {
        switch self {
        case .feeding:                                          return .feeding      // free
        case .change:                                           return .diapers      // free
        case .sleep:                                            return .sleep
        case .tummyTime:                                        return .tummyTime
        case .pumping:                                          return .pumping
        case .note:                                             return .notes
        case .timer:                                            return .timers
        case .weight, .height, .headCircumference, .bmi, .temperature:
                                                                return .measurements
        case .medication:                                       return nil           // not in the catalog — always available
        case .child:                                            return nil           // not a gated activity
        }
    }
}
