import SwiftUI

struct TimelineEventEditorState: Identifiable {
  let id = UUID()
  let recordId: Int64?
  let activity: TimelineActivity?
  let title: String
  let category: String
  let start: Date
  let end: Date
}

struct TimelineEventEditor: View {
  let state: TimelineEventEditorState
  let categories: [TimelineCategory]
  let onSave: (String, String, Date, Date) async throws -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var category: String
  @State private var start: Date
  @State private var end: Date
  @State private var errorMessage: String?
  @State private var isSaving = false
  @FocusState private var titleFocused: Bool

  init(
    state: TimelineEventEditorState,
    categories: [TimelineCategory],
    onSave: @escaping (String, String, Date, Date) async throws -> Void
  ) {
    self.state = state
    self.categories = categories
    self.onSave = onSave
    _title = State(initialValue: state.title)
    _category = State(initialValue: state.category)
    _start = State(initialValue: state.start)
    _end = State(initialValue: state.end)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(state.recordId == nil ? "Add event" : "Edit event")
        .font(.title2.weight(.semibold))

      TextField("Event title", text: $title)
        .textFieldStyle(.roundedBorder)
        .focused($titleFocused)

      Picker("Category", selection: $category) {
        ForEach(categories.filter { !$0.isIdle }, id: \.id) { item in
          Text(item.name).tag(item.name)
        }
      }

      DatePicker("Start", selection: $start, in: ...Date())
      DatePicker("End", selection: $end, in: ...Date())

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(state.recordId == nil ? "Add" : "Save") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(isSaving)
      }
    }
    .padding(24)
    .frame(width: 420)
    .onAppear { titleFocused = true }
  }

  private func save() {
    do {
      _ = try TimelineEventRules.validated(
        title: title, category: category, start: start, end: end)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    isSaving = true
    Task {
      do {
        try await onSave(title, category, start, end)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}
