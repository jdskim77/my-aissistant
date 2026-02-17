import Foundation

/// Subscription tier with associated limits and model configuration.
/// The SubscriptionTier enum in AIProviderFactory.swift is the canonical definition.
/// This file extends it with tier-specific metadata.
extension SubscriptionTier: Identifiable, CaseIterable {
    var id: String { rawValue }

    static var allCases: [SubscriptionTier] {
        [.free, .pro, .student, .powerUser]
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .student: return "Student"
        case .powerUser: return "Power User"
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .pro: return "$9.99/mo"
        case .student: return "$4.99/mo"
        case .powerUser: return "$4.99/mo"
        }
    }

    var annualPrice: String {
        switch self {
        case .free: return "Free"
        case .pro: return "$74.99/yr"
        case .student: return "$39.99/yr"
        case .powerUser: return "$39.99/yr"
        }
    }

    var features: [String] {
        switch self {
        case .free:
            return [
                "5 AI check-ins per week",
                "10 chat messages per month",
                "Full schedule management",
                "Pattern tracking"
            ]
        case .pro:
            return [
                "Unlimited AI check-ins & chat",
                "Smarter AI model for chat",
                "Weekly AI insight reviews",
                "Calendar sync",
                "Priority support"
            ]
        case .student:
            return [
                "All Pro features",
                "Student-verified pricing",
                "Unlimited AI check-ins & chat",
                "Smarter AI model for chat"
            ]
        case .powerUser:
            return [
                "Bring your own API key",
                "Choose your AI model",
                "Unlimited usage",
                "Full app features"
            ]
        }
    }

    var monthlyProductID: String? {
        switch self {
        case .free: return nil
        case .pro: return AppConstants.ProductID.proMonthly
        case .student: return AppConstants.ProductID.studentMonthly
        case .powerUser: return AppConstants.ProductID.powerUserMonthly
        }
    }

    var annualProductID: String? {
        switch self {
        case .free: return nil
        case .pro: return AppConstants.ProductID.proAnnual
        case .student: return AppConstants.ProductID.studentAnnual
        case .powerUser: return AppConstants.ProductID.powerUserAnnual
        }
    }
}
