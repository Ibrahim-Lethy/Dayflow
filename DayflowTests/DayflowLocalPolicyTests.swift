import XCTest

@testable import Dayflow

final class DayflowLocalPolicyTests: XCTestCase {
  func testReleasePreferenceMigrationCopiesOnlySafeValuesAndSelectsGemini() throws {
    let suiteName = "DayflowLocalPolicyTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let migratedCount = UserDefaultsMigrator.migrateReleasePreferencesIfNeeded(
      defaults: defaults,
      currentBundleID: DayflowLocalPolicy.bundleIdentifier,
      legacyDomain: [
        "colorCategories": Data("categories".utf8),
        "geminiSelectedModel_v3": Data("model".utf8),
        "dayflowAccountEmail": "private@example.com",
        "analyticsOptIn": true,
        "SUUpdateGroupIdentifier": 123,
      ]
    )

    XCTAssertEqual(migratedCount, 2)
    XCTAssertNotNil(defaults.data(forKey: "colorCategories"))
    XCTAssertNil(defaults.string(forKey: "dayflowAccountEmail"))
    XCTAssertNil(defaults.object(forKey: "SUUpdateGroupIdentifier"))
    XCTAssertFalse(defaults.bool(forKey: "analyticsOptIn"))
    XCTAssertEqual(defaults.string(forKey: "selectedLLMProvider"), "gemini")
    XCTAssertEqual(defaults.string(forKey: "dailyRecapProvider_v1"), "gemini")

    let routing = try LLMProviderRoutingStore.load(from: defaults)
    XCTAssertEqual(routing, LLMProviderRouting(primary: .gemini))
  }

  func testReleasePreferenceMigrationRunsOnce() throws {
    let suiteName = "DayflowLocalPolicyTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertEqual(
      UserDefaultsMigrator.migrateReleasePreferencesIfNeeded(
        defaults: defaults,
        currentBundleID: DayflowLocalPolicy.bundleIdentifier,
        legacyDomain: ["didOnboard": true]
      ),
      1
    )
    XCTAssertEqual(
      UserDefaultsMigrator.migrateReleasePreferencesIfNeeded(
        defaults: defaults,
        currentBundleID: DayflowLocalPolicy.bundleIdentifier,
        legacyDomain: ["didOnboard": false]
      ),
      0
    )
    XCTAssertTrue(defaults.bool(forKey: "didOnboard"))
  }

  func testLocalBuildHasNoDayflowBackendEndpoint() {
    XCTAssertTrue(DayflowLocalPolicy.isEnabled)
    XCTAssertNil(
      DayflowBackendConfiguration.endpoint(
        legacySavedEndpoint: "https://example.com",
        bundle: .main,
        defaults: .standard
      )
    )
    XCTAssertFalse(AnalyticsService.shared.isOptedIn)
    XCTAssertTrue(DayflowLocalPolicy.enforcesGeminiRouting(in: .standard))
  }
}
