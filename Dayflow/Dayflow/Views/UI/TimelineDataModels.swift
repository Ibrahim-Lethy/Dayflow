//
//  TimelineDataModels.swift
//  Dayflow
//
//  Data models for the new UI timeline components
//

import Foundation
import SwiftUI

/// Represents an activity in the timeline view
struct TimelineActivity: Identifiable {
  let id: String
  let recordId: Int64?
  let batchId: Int64?  // Tracks source batch for retry functionality
  let startTime: Date
  let endTime: Date
  let title: String
  let summary: String
  let detailedSummary: String
  let category: String
  let subcategory: String
  let distractions: [Distraction]?
  let videoSummaryURL: String?
  let screenshot: NSImage?
  let appSites: AppSites?
  let isBackupGenerated: Bool?
  let isUserModified: Bool

  init(
    id: String, recordId: Int64?, batchId: Int64?, startTime: Date, endTime: Date,
    title: String, summary: String, detailedSummary: String, category: String,
    subcategory: String, distractions: [Distraction]?, videoSummaryURL: String?,
    screenshot: NSImage?, appSites: AppSites?, isBackupGenerated: Bool?,
    isUserModified: Bool = false
  ) {
    self.id = id
    self.recordId = recordId
    self.batchId = batchId
    self.startTime = startTime
    self.endTime = endTime
    self.title = title
    self.summary = summary
    self.detailedSummary = detailedSummary
    self.category = category
    self.subcategory = subcategory
    self.distractions = distractions
    self.videoSummaryURL = videoSummaryURL
    self.screenshot = screenshot
    self.appSites = appSites
    self.isBackupGenerated = isBackupGenerated
    self.isUserModified = isUserModified
  }

  static func stableId(
    recordId: Int64?, batchId: Int64?, startTime: Date, endTime: Date, title: String,
    category: String, subcategory: String
  ) -> String {
    if let recordId {
      return "record:\(recordId)"
    }
    let batchPart = batchId.map { "batch:\($0)" } ?? "batch:unknown"
    let startMs = Int64((startTime.timeIntervalSince1970 * 1000).rounded())
    let endMs = Int64((endTime.timeIntervalSince1970 * 1000).rounded())
    let contentHash = stableHash("\(title)|\(category)|\(subcategory)")
    return "\(batchPart)-\(startMs)-\(endMs)-\(contentHash)"
  }

  private static func stableHash(_ input: String) -> String {
    var hash: UInt64 = 5381
    for byte in input.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }
    return String(hash, radix: 36)
  }

  func withCategory(_ newCategory: String) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: recordId,
      batchId: batchId,
      startTime: startTime,
      endTime: endTime,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
      category: newCategory,
      subcategory: subcategory,
      distractions: distractions,
      videoSummaryURL: videoSummaryURL,
      screenshot: screenshot,
      appSites: appSites,
      isBackupGenerated: isBackupGenerated,
      isUserModified: isUserModified
    )
  }

  func withTitle(_ newTitle: String) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: recordId,
      batchId: batchId,
      startTime: startTime,
      endTime: endTime,
      title: newTitle,
      summary: summary,
      detailedSummary: detailedSummary,
      category: category,
      subcategory: subcategory,
      distractions: distractions,
      videoSummaryURL: videoSummaryURL,
      screenshot: screenshot,
      appSites: appSites,
      isBackupGenerated: isBackupGenerated,
      isUserModified: isUserModified
    )
  }

  func withVideoSummaryURL(_ newVideoSummaryURL: String?) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: recordId,
      batchId: batchId,
      startTime: startTime,
      endTime: endTime,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
      category: category,
      subcategory: subcategory,
      distractions: distractions,
      videoSummaryURL: newVideoSummaryURL,
      screenshot: screenshot,
      appSites: appSites,
      isBackupGenerated: isBackupGenerated,
      isUserModified: isUserModified
    )
  }

  func withUserEdit(title: String, category: String, start: Date, end: Date) -> TimelineActivity {
    TimelineActivity(
      id: id, recordId: recordId, batchId: batchId, startTime: start, endTime: end,
      title: title, summary: summary, detailedSummary: detailedSummary, category: category,
      subcategory: subcategory, distractions: distractions, videoSummaryURL: videoSummaryURL,
      screenshot: screenshot, appSites: appSites, isBackupGenerated: isBackupGenerated,
      isUserModified: true
    )
  }
}

/// Sheet view for selecting a date
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Binding var isPresented: Bool

  var body: some View {
    VStack(spacing: 20) {
      Text("Select Date")
        .font(.title2)
        .fontWeight(.semibold)

      DatePicker(
        "",
        selection: $selectedDate,
        in: ...Date(),  // Only allow past dates and today
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .frame(width: 350)

      HStack(spacing: 12) {
        Button("Cancel") {
          isPresented = false
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)

        Button("Select") {
          isPresented = false
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .cornerRadius(8)
      }
    }
    .padding(30)
    .frame(width: 420)
  }
}
