import GRDB
import XCTest

@testable import Dayflow

final class ManualTimelineEventTests: XCTestCase {
  func testSharedTestStoreIsRedirectedAwayFromLiveApplicationSupport() {
    XCTAssertTrue(StorageManager.shared.dbURL.path.contains("DayflowTests-"))
  }

  func testValidationRejectsInvalidEvents() throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    XCTAssertThrowsError(
      try TimelineEventRules.validated(
        title: " ", category: "Personal", start: now.addingTimeInterval(-60), end: now,
        now: now)
    ) { XCTAssertEqual($0 as? TimelineEventError, .emptyTitle) }
    XCTAssertThrowsError(
      try TimelineEventRules.validated(
        title: "Sleep", category: "Personal", start: now, end: now, now: now)
    ) { XCTAssertEqual($0 as? TimelineEventError, .invalidRange) }
    XCTAssertThrowsError(
      try TimelineEventRules.validated(
        title: "Sleep", category: "Personal", start: now, end: now.addingTimeInterval(60),
        now: now)
    ) { XCTAssertEqual($0 as? TimelineEventError, .futureEnd) }
    XCTAssertThrowsError(
      try TimelineEventRules.validated(
        title: "Sleep", category: "Personal",
        start: now.addingTimeInterval(-(24 * 60 * 60 + 1)), end: now, now: now)
    ) { XCTAssertEqual($0 as? TimelineEventError, .tooLong) }
  }

  func testManualCreateEditAndReprocessingProtection() throws {
    let (storage, directory) = try makeStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(30 * 60)

    let id = try storage.createUserTimelineCard(
      title: " Sleep ", category: " Personal ", start: start, end: end)
    let day = start.getDayInfoFor4AMBoundary().dayString
    var card = try XCTUnwrap(storage.fetchTimelineCards(forDay: day).first)
    XCTAssertEqual(card.recordId, id)
    XCTAssertNil(card.batchId)
    XCTAssertEqual(card.title, "Sleep")
    XCTAssertEqual(card.summary, "")
    XCTAssertEqual(card.detailedSummary, "")
    XCTAssertEqual(card.startTs, Int(start.timeIntervalSince1970))
    XCTAssertTrue(card.isUserModified)

    let editedStart = start.addingTimeInterval(15 * 60)
    let editedEnd = end.addingTimeInterval(30 * 60)
    try storage.updateUserTimelineCard(
      id: id, title: "Nap", category: "Break", start: editedStart, end: editedEnd)
    card = try XCTUnwrap(storage.fetchTimelineCards(forDay: day).first)
    XCTAssertEqual(card.title, "Nap")
    XCTAssertEqual(card.category, "Break")
    XCTAssertEqual(card.startTs, Int(editedStart.timeIntervalSince1970))

    _ = storage.replaceTimelineCardsInRange(
      from: start.addingTimeInterval(-60), to: end.addingTimeInterval(3600),
      with: [], batchId: 999)
    XCTAssertEqual(storage.fetchTimelineCards(forDay: day).count, 1)
    _ = storage.deleteTimelineCards(forDay: day)
    XCTAssertEqual(storage.fetchTimelineCards(forDay: day).count, 1)

    _ = storage.deleteTimelineCard(recordId: id)
    XCTAssertTrue(storage.fetchTimelineCards(forDay: day).isEmpty)
  }

  func testExistingDatabaseMigrationKeepsCards() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DayflowMigrationTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("chunks.sqlite")
    let queue = try DatabaseQueue(path: databaseURL.path)
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE timeline_cards (
          id INTEGER PRIMARY KEY AUTOINCREMENT, batch_id INTEGER, start TEXT NOT NULL,
          end TEXT NOT NULL, start_ts INTEGER, end_ts INTEGER, day DATE NOT NULL,
          title TEXT NOT NULL, summary TEXT, category TEXT NOT NULL, subcategory TEXT,
          detailed_summary TEXT, metadata TEXT, video_summary_url TEXT,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, is_deleted INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO timeline_cards(start, end, start_ts, end_ts, day, title, category)
        VALUES ('9:00 AM', '9:30 AM', 1700000000, 1700001800, '2023-11-14', 'Existing', 'Work');
        """)
    }

    let storage = StorageManager(baseDirectory: directory, startSchedulers: false)
    let card = try XCTUnwrap(storage.fetchTimelineCardsByTimeRange(
      from: Date(timeIntervalSince1970: 1_699_999_000),
      to: Date(timeIntervalSince1970: 1_700_002_000)).first)
    XCTAssertEqual(card.title, "Existing")
    XCTAssertFalse(card.isUserModified)
  }

  func testEditingAutomaticCardMarksAndProtectsItFromBatchReprocessing() throws {
    let (storage, directory) = try makeStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = 1_700_000_000
    let end = start + 1800
    var cardID: Int64 = 0
    var batchID: Int64 = 0
    try storage.db.write { db in
      try db.execute(sql: """
        INSERT INTO analysis_batches(batch_start_ts, batch_end_ts, status)
        VALUES (?, ?, 'completed')
        """, arguments: [start, end])
      batchID = db.lastInsertedRowID
      try db.execute(sql: """
        INSERT INTO timeline_cards(
          batch_id, start, end, start_ts, end_ts, day, title, category, is_user_modified
        ) VALUES (?, '9:00 AM', '9:30 AM', ?, ?, '2023-11-14', 'Automatic', 'Work', 0)
        """, arguments: [batchID, start, end])
      cardID = db.lastInsertedRowID
    }

    storage.updateTimelineCardTitle(cardId: cardID, title: "Corrected")
    let edited = try XCTUnwrap(storage.fetchTimelineCardsByTimeRange(
      from: Date(timeIntervalSince1970: TimeInterval(start - 60)),
      to: Date(timeIntervalSince1970: TimeInterval(end + 60))).first)
    XCTAssertTrue(edited.isUserModified)

    _ = storage.deleteTimelineCards(forBatchIds: [batchID])
    XCTAssertEqual(storage.fetchTimelineCardsByTimeRange(
      from: Date(timeIntervalSince1970: TimeInterval(start - 60)),
      to: Date(timeIntervalSince1970: TimeInterval(end + 60))).first?.title, "Corrected")
  }

  func testFourAMClippingKeepsOriginalActivityAndColumnsAreStable() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
      .getDayInfoFor4AMBoundary()
    let first = activity(
      id: "a", start: day.startOfDay.addingTimeInterval(-30 * 60),
      end: day.startOfDay.addingTimeInterval(60 * 60))
    let second = activity(
      id: "b", start: day.startOfDay.addingTimeInterval(15 * 60),
      end: day.startOfDay.addingTimeInterval(45 * 60))
    let third = activity(
      id: "c", start: day.startOfDay.addingTimeInterval(60 * 60),
      end: day.startOfDay.addingTimeInterval(90 * 60))

    let segments = TimelineActivityLoader.resolveDisplaySegments(
      from: [third, second, first],
      clippedTo: DateInterval(start: day.startOfDay, end: day.endOfDay))
    XCTAssertEqual(segments.first?.start, day.startOfDay)
    XCTAssertEqual(segments.first?.activity.startTime, first.startTime)

    let columns = TimelineActivityLoader.assignOverlapColumns(segments)
    XCTAssertEqual(columns.map(\.segment.activity.id), ["a", "b", "c"])
    XCTAssertEqual(columns.map(\.column), [0, 1, 0])
    XCTAssertEqual(columns.map(\.columnCount), [2, 2, 1])
  }

  private func makeStorage() throws -> (StorageManager, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DayflowManualEventTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (StorageManager(baseDirectory: directory, startSchedulers: false), directory)
  }

  private func activity(id: String, start: Date, end: Date) -> TimelineActivity {
    TimelineActivity(
      id: id, recordId: nil, batchId: nil, startTime: start, endTime: end,
      title: id, summary: "", detailedSummary: "", category: "Personal",
      subcategory: "", distractions: nil, videoSummaryURL: nil, screenshot: nil,
      appSites: nil, isBackupGenerated: nil)
  }
}
