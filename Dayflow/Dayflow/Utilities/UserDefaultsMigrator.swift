import Foundation

enum UserDefaultsMigrator {
  private static let sentinelKey = "didMigrateFromSandboxDefaults"
  private static let releaseSentinelKey = "didMigrateFromReleaseDefaults"
  private static let releaseBundleID = "teleportlabs.com.Dayflow"
  private static let skippedKeyPrefixes = ["NS", "Apple", "AV", "SU"]
  private static let safeReleaseKeys: Set<String> = [
    "activitySlideshowPlaybackSpeedX",
    "colorCategories",
    "didOnboard",
    "geminiSelectedModel_v3",
    "geminiSetupComplete",
    "hasCompletedJournalOnboarding",
    "hasUsedApp",
    "isRecording",
    "llmOutputLanguageOverride",
    "onboardingAppliedCategoryPreset",
    "onboardingCategoriesCustomized",
    "onboardingHasPaidAI",
    "onboardingSelectedRole",
    "onboardingStarted",
    "onboardingStep",
    "onboardingStepSchemaVersion",
    "recordingPrivacyBlockedApplicationIdentifiers",
    "recordingPrivacyDidSeedDefaultSecretApps",
    "saveAllTimelapsesToDisk",
    "showDailyGoalPopups",
    "showDockIcon",
    "showTimelineAppIcons",
    "storageLimitRecordingsBytes",
    "storageLimitTimelapsesBytes",
  ]

  static func migrateIfNeeded(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    migrateReleasePreferencesIfNeeded(defaults: defaults)

    if defaults.bool(forKey: sentinelKey) {
      return
    }

    guard let bundleId = Bundle.main.bundleIdentifier else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    let containerPlistURL = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")

    guard fileManager.fileExists(atPath: containerPlistURL.path) else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    guard let legacyDomain = NSDictionary(contentsOf: containerPlistURL) as? [String: Any],
      legacyDomain.isEmpty == false
    else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    let filteredLegacy = legacyDomain.filter { key, _ in
      guard key != sentinelKey else { return false }
      return skippedKeyPrefixes.contains { prefix in key.hasPrefix(prefix) } == false
    }

    if filteredLegacy.isEmpty {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    var mergedDomain = defaults.persistentDomain(forName: bundleId) ?? [:]
    for (key, value) in filteredLegacy {
      mergedDomain[key] = value
    }

    defaults.setPersistentDomain(mergedDomain, forName: bundleId)
    defaults.set(true, forKey: sentinelKey)

    print("UserDefaultsMigrator: migrated \(filteredLegacy.count) keys from sandbox defaults")
  }

  @discardableResult
  static func migrateReleasePreferencesIfNeeded(
    defaults: UserDefaults,
    currentBundleID: String? = Bundle.main.bundleIdentifier,
    legacyDomain: [String: Any]? = UserDefaults.standard.persistentDomain(
      forName: releaseBundleID)
  ) -> Int {
    guard currentBundleID == DayflowLocalPolicy.bundleIdentifier,
      !defaults.bool(forKey: releaseSentinelKey)
    else { return 0 }

    let safeValues = (legacyDomain ?? [:]).filter { safeReleaseKeys.contains($0.key) }
    for (key, value) in safeValues {
      defaults.set(value, forKey: key)
    }

    let routing = LLMProviderRouting(primary: .gemini)
    if let data = try? JSONEncoder().encode(routing) {
      defaults.set(data, forKey: LLMProviderRoutingStore.storageKey)
    }
    defaults.set(true, forKey: "geminiSetupComplete")
    defaults.set("gemini", forKey: "selectedLLMProvider")
    defaults.set("gemini", forKey: "dailyRecapProvider_v1")
    defaults.set("gemini", forKey: "dashboardChatProvider")
    defaults.set(false, forKey: "analyticsOptIn")
    defaults.removeObject(forKey: "llmBackupProviderId")
    defaults.removeObject(forKey: "llmProviderType")
    defaults.set(true, forKey: releaseSentinelKey)

    print("UserDefaultsMigrator: migrated \(safeValues.count) safe keys from Dayflow")
    return safeValues.count
  }
}
