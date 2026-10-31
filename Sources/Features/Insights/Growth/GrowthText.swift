import Foundation

/// A feature-owned table keeps this contribution independent of the German localization PR.
func growthText(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "Growth")
}

extension GrowthMetric {
    var title: String {
        switch self {
        case .weight: return growthText("Weight")
        case .height: return growthText("Length / height")
        case .headCircumference: return growthText("Head circumference")
        }
    }
}

extension GrowthPeriod {
    var title: String {
        switch self {
        case .month: return growthText("30 days")
        case .threeMonths: return growthText("90 days")
        case .year: return growthText("1 year")
        case .all: return growthText("All")
        }
    }
}
