import XCTest
@testable import MyAIssistant

final class SubscriptionTierTests: XCTestCase {

    // MARK: - All Cases

    func testAllCases() {
        let allCases = SubscriptionTier.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.free))
        XCTAssertTrue(allCases.contains(.pro))
        XCTAssertTrue(allCases.contains(.student))
        XCTAssertTrue(allCases.contains(.powerUser))
    }

    // MARK: - Display Names

    func testDisplayNames() {
        XCTAssertEqual(SubscriptionTier.free.displayName, "Free")
        XCTAssertEqual(SubscriptionTier.pro.displayName, "Pro")
        XCTAssertEqual(SubscriptionTier.student.displayName, "Student")
        XCTAssertEqual(SubscriptionTier.powerUser.displayName, "Power User")
    }

    // MARK: - Pricing

    func testMonthlyPrices() {
        XCTAssertEqual(SubscriptionTier.free.monthlyPrice, "Free")
        XCTAssertFalse(SubscriptionTier.pro.monthlyPrice.isEmpty)
        XCTAssertFalse(SubscriptionTier.student.monthlyPrice.isEmpty)
        XCTAssertFalse(SubscriptionTier.powerUser.monthlyPrice.isEmpty)
    }

    func testAnnualPrices() {
        XCTAssertEqual(SubscriptionTier.free.annualPrice, "Free")
        XCTAssertFalse(SubscriptionTier.pro.annualPrice.isEmpty)
        XCTAssertFalse(SubscriptionTier.student.annualPrice.isEmpty)
        XCTAssertFalse(SubscriptionTier.powerUser.annualPrice.isEmpty)
    }

    // MARK: - Features

    func testFeaturesNotEmpty() {
        for tier in SubscriptionTier.allCases {
            XCTAssertFalse(tier.features.isEmpty, "\(tier.displayName) should have features")
        }
    }

    func testFreeTierHasLimitedFeatures() {
        let features = SubscriptionTier.free.features
        let hasLimitedChat = features.contains { $0.contains("10 chat messages") }
        let hasLimitedCheckIns = features.contains { $0.contains("5 AI check-ins") }
        XCTAssertTrue(hasLimitedChat)
        XCTAssertTrue(hasLimitedCheckIns)
    }

    func testProTierHasUnlimited() {
        let features = SubscriptionTier.pro.features
        let hasUnlimited = features.contains { $0.contains("Unlimited") }
        XCTAssertTrue(hasUnlimited)
    }

    func testPowerUserHasBYOK() {
        let features = SubscriptionTier.powerUser.features
        let hasBYOK = features.contains { $0.contains("Bring your own") || $0.contains("API key") }
        XCTAssertTrue(hasBYOK)
    }

    // MARK: - Product IDs

    func testFreeHasNoProductIDs() {
        XCTAssertNil(SubscriptionTier.free.monthlyProductID)
        XCTAssertNil(SubscriptionTier.free.annualProductID)
    }

    func testProHasProductIDs() {
        XCTAssertEqual(SubscriptionTier.pro.monthlyProductID, AppConstants.ProductID.proMonthly)
        XCTAssertEqual(SubscriptionTier.pro.annualProductID, AppConstants.ProductID.proAnnual)
    }

    func testStudentHasProductIDs() {
        XCTAssertEqual(SubscriptionTier.student.monthlyProductID, AppConstants.ProductID.studentMonthly)
        XCTAssertEqual(SubscriptionTier.student.annualProductID, AppConstants.ProductID.studentAnnual)
    }

    func testPowerUserHasProductIDs() {
        XCTAssertEqual(SubscriptionTier.powerUser.monthlyProductID, AppConstants.ProductID.powerUserMonthly)
        XCTAssertEqual(SubscriptionTier.powerUser.annualProductID, AppConstants.ProductID.powerUserAnnual)
    }

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(SubscriptionTier.free.rawValue, "free")
        XCTAssertEqual(SubscriptionTier.pro.rawValue, "pro")
        XCTAssertEqual(SubscriptionTier.student.rawValue, "student")
        XCTAssertEqual(SubscriptionTier.powerUser.rawValue, "powerUser")
    }

    // MARK: - Identifiable

    func testIdentifiable() {
        for tier in SubscriptionTier.allCases {
            XCTAssertEqual(tier.id, tier.rawValue)
        }
    }
}

// MARK: - StoreError Tests

final class StoreErrorTests: XCTestCase {

    func testVerificationFailedDescription() {
        let error = StoreError.verificationFailed
        XCTAssertEqual(error.errorDescription, "Transaction verification failed.")
    }
}
