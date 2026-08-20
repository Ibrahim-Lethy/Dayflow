import Foundation

enum DayflowLocalPolicy {
  static let bundleIdentifier = "com.ibrahimlethy.DayflowLocal"

  static var isEnabled: Bool {
    Bundle.main.bundleIdentifier == bundleIdentifier
  }

  static var allowsTelemetry: Bool { !isEnabled }
  static var allowsDayflowServices: Bool { !isEnabled }
  static var allowsRemoteFavicons: Bool { !isEnabled }
  static var allowsRemoteFlow: Bool { !isEnabled }

  static func enforcesGeminiRouting(in defaults: UserDefaults) -> Bool {
    isEnabled && defaults === UserDefaults.standard
  }
}
