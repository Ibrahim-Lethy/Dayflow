import Foundation

struct TimelineDisplaySegment {
  let activity: TimelineActivity
  private(set) var activities: [TimelineActivity]
  var start: Date
  var end: Date

  init(activity: TimelineActivity, start: Date, end: Date) {
    self.activity = activity
    self.activities = [activity]
    self.start = start
    self.end = end
  }

  var failureCount: Int {
    guard activity.title == "Processing failed" else { return 0 }
    return activities.count
  }

  var batchIds: [Int64] {
    var seen = Set<Int64>()
    return activities.compactMap(\.batchId).filter { seen.insert($0).inserted }
  }

  mutating func appendFailure(_ activity: TimelineActivity, start: Date, end: Date) {
    activities.append(activity)
    self.start = min(self.start, start)
    self.end = max(self.end, end)
  }
}

struct TimelineRecordingProjectionWindow {
  let start: Date
  let end: Date
}

struct TimelineColumnedSegment {
  let segment: TimelineDisplaySegment
  let column: Int
  let columnCount: Int
}

enum TimelineActivityLoader {
  private static let failedTitle = "Processing failed"
  private static let failureGroupingGapTolerance: TimeInterval = 60

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  static func dayPayload(
    for selectedDate: Date,
    storageManager: StorageManaging = StorageManager.shared,
    now: Date = Date()
  ) -> (dayString: String, timelineDate: Date, activities: [TimelineActivity]) {
    let timelineDate = timelineDisplayDate(from: selectedDate, now: now)
    let dayString = DateFormatter.yyyyMMdd.string(from: timelineDate)
    let cards = storageManager.fetchTimelineCards(forDay: dayString)
    let visibleCards = displayableCards(cards, storageManager: storageManager)
    return (dayString, timelineDate, buildActivities(from: visibleCards))
  }

  static func activities(
    in weekRange: TimelineWeekRange,
    storageManager: StorageManaging = StorageManager.shared
  ) -> [TimelineActivity] {
    let cards = storageManager.fetchTimelineCardsByTimeRange(
      from: weekRange.weekStart, to: weekRange.weekEnd)
    return buildActivities(from: displayableCards(cards, storageManager: storageManager))
  }

  static func shouldDisplay(_ card: TimelineCard, storageManager: StorageManaging) -> Bool {
    guard card.title == "Processing failed" else { return true }
    return isRetryableFailedCard(card, storageManager: storageManager)
  }

  static func isRetryableFailedCard(_ card: TimelineCard, storageManager: StorageManaging) -> Bool {
    guard card.title == "Processing failed", let batchId = card.batchId else { return false }
    return hasRetrySourceScreenshots(for: batchId, storageManager: storageManager)
  }

  private static func displayableCards(
    _ cards: [TimelineCard],
    storageManager: StorageManaging
  ) -> [TimelineCard] {
    cards.filter { shouldDisplay($0, storageManager: storageManager) }
  }

  private static func hasRetrySourceScreenshots(
    for batchId: Int64,
    storageManager: StorageManaging
  ) -> Bool {
    storageManager.screenshotsForBatch(batchId).contains { screenshot in
      FileManager.default.fileExists(atPath: screenshot.filePath)
    }
  }

  static func buildActivities(from cards: [TimelineCard]) -> [TimelineActivity] {
    let calendar = Calendar.current
    var results: [TimelineActivity] = []
    var idCounts: [String: Int] = [:]
    results.reserveCapacity(cards.count)

    for card in cards {
      let timestampStart = card.startTs.map { Date(timeIntervalSince1970: TimeInterval($0)) }
      let timestampEnd = card.endTs.map { Date(timeIntervalSince1970: TimeInterval($0)) }

      let adjustedStartDate: Date
      let adjustedEndDate: Date

      if let timestampStart, let timestampEnd, timestampEnd > timestampStart {
        adjustedStartDate = timestampStart
        adjustedEndDate = timestampEnd
      } else {
        guard
          let baseDay = DateFormatter.yyyyMMdd.date(from: card.day),
          let parsedStart = timeFormatter.date(from: card.startTimestamp),
          let parsedEnd = timeFormatter.date(from: card.endTimestamp)
        else { continue }

        let baseDate = calendar.startOfDay(for: baseDay)
        let startComponents = calendar.dateComponents([.hour, .minute], from: parsedStart)
        let endComponents = calendar.dateComponents([.hour, .minute], from: parsedEnd)

        guard
          let startDate = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: 0,
            of: baseDate
          ),
          let endDate = calendar.date(
            bySettingHour: endComponents.hour ?? 0,
            minute: endComponents.minute ?? 0,
            second: 0,
            of: baseDate
          )
        else {
          continue
        }

        var resolvedStart = startDate
        var resolvedEnd = endDate

        if calendar.component(.hour, from: startDate) < 4 {
          resolvedStart = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }

        if calendar.component(.hour, from: endDate) < 4 {
          resolvedEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        if resolvedEnd < resolvedStart {
          resolvedEnd = calendar.date(byAdding: .day, value: 1, to: resolvedEnd) ?? resolvedEnd
        }
        adjustedStartDate = resolvedStart
        adjustedEndDate = resolvedEnd
      }

      let baseId = TimelineActivity.stableId(
        recordId: card.recordId,
        batchId: card.batchId,
        startTime: adjustedStartDate,
        endTime: adjustedEndDate,
        title: card.title,
        category: card.category,
        subcategory: card.subcategory
      )

      let seenCount = idCounts[baseId, default: 0]
      idCounts[baseId] = seenCount + 1
      let finalId = seenCount == 0 ? baseId : "\(baseId)-\(seenCount)"

      results.append(
        TimelineActivity(
          id: finalId,
          recordId: card.recordId,
          batchId: card.batchId,
          startTime: adjustedStartDate,
          endTime: adjustedEndDate,
          title: card.title,
          summary: card.summary,
          detailedSummary: card.detailedSummary,
          category: card.category,
          subcategory: card.subcategory,
          distractions: card.distractions,
          videoSummaryURL: card.videoSummaryURL,
          screenshot: nil,
          appSites: card.appSites,
          isBackupGenerated: card.isBackupGenerated,
          isUserModified: card.isUserModified
        )
      )
    }

    return results
  }

  static func resolveDisplaySegments(
    from activities: [TimelineActivity], clippedTo interval: DateInterval? = nil
  )
    -> [TimelineDisplaySegment]
  {
    let sortedActivities = activities.sorted { lhs, rhs in
      if lhs.startTime == rhs.startTime {
        return lhs.endTime < rhs.endTime
      }
      return lhs.startTime < rhs.startTime
    }

    var segments: [TimelineDisplaySegment] = []
    segments.reserveCapacity(sortedActivities.count)

    for activity in sortedActivities {
      let clippedStart = max(activity.startTime, interval?.start ?? activity.startTime)
      let clippedEnd = min(activity.endTime, interval?.end ?? activity.endTime)
      guard clippedEnd > clippedStart else { continue }
      if activity.title == failedTitle,
        let lastIndex = segments.indices.last,
        segments[lastIndex].activity.title == failedTitle,
        clippedStart.timeIntervalSince(segments[lastIndex].end)
          <= failureGroupingGapTolerance
      {
        segments[lastIndex].appendFailure(activity, start: clippedStart, end: clippedEnd)
      } else {
        segments.append(
          TimelineDisplaySegment(
            activity: activity,
            start: clippedStart,
            end: clippedEnd
          ))
      }
    }

    return segments
  }

  static func assignOverlapColumns(_ segments: [TimelineDisplaySegment])
    -> [TimelineColumnedSegment]
  {
    let sorted = segments.sorted {
      if $0.start != $1.start { return $0.start < $1.start }
      if $0.end != $1.end { return $0.end < $1.end }
      return $0.activity.id < $1.activity.id
    }
    var result: [TimelineColumnedSegment] = []
    var cluster: [TimelineDisplaySegment] = []
    var clusterEnd = Date.distantPast

    func appendCluster(_ items: [TimelineDisplaySegment]) {
      guard !items.isEmpty else { return }
      var columnEnds: [Date] = []
      var assignments: [(TimelineDisplaySegment, Int)] = []
      for item in items {
        let column = columnEnds.firstIndex(where: { $0 <= item.start }) ?? columnEnds.count
        if column == columnEnds.count { columnEnds.append(item.end) } else {
          columnEnds[column] = item.end
        }
        assignments.append((item, column))
      }
      let count = max(1, columnEnds.count)
      result.append(contentsOf: assignments.map {
        TimelineColumnedSegment(segment: $0.0, column: $0.1, columnCount: count)
      })
    }

    for item in sorted {
      if !cluster.isEmpty, item.start >= clusterEnd {
        appendCluster(cluster)
        cluster.removeAll(keepingCapacity: true)
        clusterEnd = .distantPast
      }
      cluster.append(item)
      clusterEnd = max(clusterEnd, item.end)
    }
    appendCluster(cluster)
    return result
  }

  static func recordingProjectionWindow(
    for timelineDate: Date,
    displaySegments: [TimelineDisplaySegment],
    now: Date = Date()
  ) -> TimelineRecordingProjectionWindow? {
    guard timelineIsToday(timelineDate, now: now) else { return nil }

    let dayInfo = timelineDate.getDayInfoFor4AMBoundary()
    let dayStart = dayInfo.startOfDay
    let dayEnd = dayInfo.endOfDay
    let cycleDuration: TimeInterval = 15 * 60
    let hardCap: TimeInterval = 40 * 60

    let centeredStart = now.addingTimeInterval(-(cycleDuration / 2))
    var windowStart = max(dayStart, centeredStart)
    var windowEnd = windowStart.addingTimeInterval(cycleDuration)

    if windowEnd > dayEnd {
      windowEnd = dayEnd
      windowStart = max(dayStart, windowEnd.addingTimeInterval(-cycleDuration))
    }

    windowEnd = min(windowEnd, windowStart.addingTimeInterval(hardCap))

    if windowEnd <= windowStart {
      return nil
    }

    let sortedSegments = displaySegments.sorted { $0.start < $1.start }
    var moved = true
    var iterations = 0
    let maxIterations = max(1, sortedSegments.count + 2)

    while moved {
      moved = false
      let previousStart = windowStart
      let previousEnd = windowEnd

      for segment in sortedSegments {
        let intersects = segment.end > windowStart && segment.start < windowEnd
        if intersects {
          windowStart = segment.end
          windowEnd = windowStart.addingTimeInterval(cycleDuration)

          if windowEnd > dayEnd {
            windowEnd = dayEnd
            windowStart = max(dayStart, windowEnd.addingTimeInterval(-cycleDuration))
          }

          windowEnd = min(windowEnd, windowStart.addingTimeInterval(hardCap))
          moved = true
          break
        }
      }

      if windowStart >= dayEnd {
        return nil
      }

      if moved {
        iterations += 1
        if windowStart == previousStart && windowEnd == previousEnd {
          return nil
        }
        if iterations >= maxIterations {
          return nil
        }
      }
    }

    guard windowEnd > windowStart else { return nil }
    return TimelineRecordingProjectionWindow(start: windowStart, end: windowEnd)
  }
}
