import Foundation

enum TimelineEventError: LocalizedError, Equatable {
  case emptyTitle
  case emptyCategory
  case invalidRange
  case futureEnd
  case tooLong
  case cardNotFound

  var errorDescription: String? {
    switch self {
    case .emptyTitle: return "Enter an event title."
    case .emptyCategory: return "Choose a category."
    case .invalidRange: return "End time must be after start time."
    case .futureEnd: return "Events cannot end in the future."
    case .tooLong: return "Events can be at most 24 hours long."
    case .cardNotFound: return "That event no longer exists."
    }
  }
}

enum TimelineEventRules {
  static let maximumDuration: TimeInterval = 24 * 60 * 60

  static func validated(
    title: String,
    category: String,
    start: Date,
    end: Date,
    now: Date = Date()
  ) throws -> (title: String, category: String, start: Date, end: Date) {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else { throw TimelineEventError.emptyTitle }
    guard !cleanCategory.isEmpty else { throw TimelineEventError.emptyCategory }
    guard end > start else { throw TimelineEventError.invalidRange }
    guard end <= now else { throw TimelineEventError.futureEnd }
    guard end.timeIntervalSince(start) <= maximumDuration else {
      throw TimelineEventError.tooLong
    }
    return (cleanTitle, cleanCategory, start, end)
  }

  static func snappedThirtyMinuteRange(
    on day: Date,
    near preferredStart: Date? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> DateInterval {
    let logicalDay = timelineDisplayDate(from: day, now: now)
    let isToday = logicalDay.getDayInfoFor4AMBoundary().dayString
      == now.getDayInfoFor4AMBoundary().dayString

    let rawStart: Date
    if let preferredStart {
      rawStart = preferredStart
    } else if isToday {
      rawStart = now.addingTimeInterval(-30 * 60)
    } else {
      rawStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: logicalDay)
        ?? logicalDay
    }

    let minute = calendar.component(.minute, from: rawStart)
    let snappedMinute = (minute / 15) * 15
    let snapped = calendar.date(bySettingHour: calendar.component(.hour, from: rawStart),
      minute: snappedMinute, second: 0, of: rawStart) ?? rawStart
    let end = min(snapped.addingTimeInterval(30 * 60), now)
    let start = end.timeIntervalSince(snapped) > 0 ? snapped : end.addingTimeInterval(-30 * 60)
    return DateInterval(start: start, end: end)
  }
}
