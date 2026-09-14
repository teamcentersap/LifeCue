import XCTest
@testable import LifeCue

final class FeatureAccessPolicyTests: XCTestCase {
    func testProFeaturesStayLockedUntilUnlocked() {
        for feature in LifeCueProFeature.allCases {
            XCTAssertTrue(FeatureAccessPolicy.isLocked(feature, isPro: false), feature.rawValue)
            XCTAssertFalse(FeatureAccessPolicy.isLocked(feature, isPro: true), feature.rawValue)
            XCTAssertTrue(FeatureAccessPolicy.allows(feature, isPro: true), feature.rawValue)
        }
    }

    func testFreeAndProCapabilityListsAreNonEmptyAndDistinct() {
        XCTAssertFalse(FeatureAccessPolicy.freeCapabilities.isEmpty)
        XCTAssertFalse(FeatureAccessPolicy.proCapabilities.isEmpty)
        XCTAssertTrue(
            Set(FeatureAccessPolicy.freeCapabilities)
                .isDisjoint(with: Set(FeatureAccessPolicy.proCapabilities))
        )
    }

    func testProProductIDMatchesStoreKitConfig() throws {
        XCTAssertEqual(AppConfig.proProductID, "com.lifecue.app.pro.lifetime")
        XCTAssertEqual(AppConfig.bundleID, "com.lifecue.app")
        XCTAssertTrue(AppConfig.monetizationEnabled)

        let root = try LifeCueRepositoryRoot.resolve()
        let bundled = Bundle(for: PurchaseManager.self)
            .url(forResource: "Configuration", withExtension: "storekit")
        let snapshot = root.appendingPathComponent("LifeCue/Resources/Configuration.storekit")
        let storeKitURL = bundled ?? snapshot
        let data = try Data(contentsOf: storeKitURL)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        XCTAssertEqual(products.first?["productID"] as? String, AppConfig.proProductID)
        XCTAssertEqual(products.first?["type"] as? String, "NonConsumable")
        XCTAssertEqual(products.first?["referenceName"] as? String, "LifeCue Pro Lifetime")
    }
}
