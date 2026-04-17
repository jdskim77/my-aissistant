import Foundation
import SwiftData

// MARK: - Widget Data (duplicated from TaskManager — extension can't import full TaskManager)

/// Minimal task snapshot for widget display.
private struct ExtWidgetTaskData: Codable {
    let title: String
    let priority: String
    let time: String?
}

/// Shared widget data written to the App Group container.
private struct ExtWidgetSharedData: Codable {
    let tasksCompleted: Int
    let tasksTotal: Int
    let topPending: [ExtWidgetTaskData]
    let streakDays: Int
    let streakActive: Bool
    let quoteText: String?
    let quoteAuthor: String?
    let updatedAt: Date

    static let appGroupID = "group.com.myaissistant.shared"
    static let fileName = "widget-data.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(self) else { return }
        try? encoded.write(to: url, options: .atomic)
    }
}

/// ViewModel for the Share Extension. Handles LLM-based task extraction and
/// persistence to the shared App Group SwiftData store.
@MainActor @Observable
final class ShareExtensionViewModel {

    // MARK: - State

    var proposedTitle: String = ""
    var suggestedCategory: TaskCategory = .personal
    var suggestedDate: Date = Date()
    var isExtracting = false
    var isSaving = false
    var didExtractWithAI = false
    var errorMessage: String?

    private(set) var sharedText: String?
    private(set) var sharedURL: URL?

    // MARK: - Dependencies

    private var modelContainer: ModelContainer?

    // MARK: - Init

    init(sharedText: String?, sharedURL: URL?) {
        self.sharedText = sharedText
        self.sharedURL = sharedURL

        // Set a sensible default title from the raw content
        proposedTitle = Self.defaultTitle(text: sharedText, url: sharedURL)

        // Initialize the shared ModelContainer
        modelContainer = Self.createSharedContainer()
    }

    // MARK: - AI Extraction

    /// Attempt to extract a structured task from the shared content using the LLM.
    /// Falls back to the raw default title if no API key or on any failure.
    func extractTask() async {
        let content = buildContentString()
        guard !content.isEmpty else { return }

        let keychainService = KeychainService()

        // Try BYOK Anthropic key first, then Thrivn backend access token
        let apiKey = keychainService.anthropicAPIKey()
        guard let apiKey, !apiKey.isEmpty else {
            // No API key — use raw content as title (already set in init)
            return
        }

        isExtracting = true
        defer { isExtracting = false }

        do {
            let result = try await callExtractionLLM(content: content, apiKey: apiKey)
            proposedTitle = result.title
            if let cat = result.category {
                suggestedCategory = cat
            }
            if let date = result.suggestedDate {
                suggestedDate = date
            }
            didExtractWithAI = true
        } catch {
            // Extraction failed — keep the raw default title, no error shown
        }
    }

    // MARK: - Save

    func saveTask() {
        guard !proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Task title can't be empty."
            return
        }
        guard !isSaving else { return }
        isSaving = true

        guard let container = modelContainer else {
            errorMessage = "Couldn't access app data."
            isSaving = false
            return
        }

        let context = ModelContext(container)

        // Build notes from the shared content
        var notes = ""
        if let url = sharedURL {
            notes = url.absoluteString
            if let text = sharedText, !text.isEmpty, text != url.absoluteString {
                notes += "\n\n\(text)"
            }
        } else if let text = sharedText, text != proposedTitle {
            notes = text
        }

        let task = TaskItem(
            title: proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            category: suggestedCategory,
            priority: .medium,
            date: suggestedDate,
            icon: iconForCategory(suggestedCategory),
            notes: notes
        )

        context.insert(task)

        do {
            try context.save()
        } catch {
            errorMessage = "Couldn't save the task. Try again."
            isSaving = false
            return
        }

        // Update widget data so the task appears in widgets immediately
        updateWidgetData(context: context)

        isSaving = false
    }

    // MARK: - Private Helpers

    private func buildContentString() -> String {
        var parts: [String] = []
        if let text = sharedText, !text.isEmpty {
            parts.append(text)
        }
        if let url = sharedURL {
            parts.append(url.absoluteString)
        }
        return parts.joined(separator: "\n")
    }

    private static func defaultTitle(text: String?, url: URL?) -> String {
        if let text, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 60 { return trimmed }
            let truncated = String(trimmed.prefix(57))
            return truncated + "..."
        }
        if let url {
            return url.host() ?? url.absoluteString.prefix(60).description
        }
        return "Shared task"
    }

    private func iconForCategory(_ category: TaskCategory) -> String {
        switch category {
        case .work: return "briefcase"
        case .health: return "heart.fill"
        case .personal: return "person.fill"
        case .errand: return "cart"
        case .travel: return "airplane"
        }
    }

    // MARK: - LLM Extraction

    private struct ExtractionResult {
        let title: String
        let category: TaskCategory?
        let suggestedDate: Date?
    }

    private func callExtractionLLM(content: String, apiKey: String) async throws -> ExtractionResult {
        let systemPrompt = """
        Extract a single actionable task from this content. Return ONLY valid JSON with these fields:
        - "title": a concise task title (max 60 chars)
        - "category": one of "Work", "Health", "Personal", "Errand", "Travel"
        - "suggestedDate": ISO 8601 date string if a date/time is mentioned, otherwise null

        Example: {"title":"Buy groceries from Costco","category":"Errand","suggestedDate":null}
        """

        let url = URL(string: AppConstants.anthropicEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3 // Tight timeout for extension
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConstants.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")

        struct RequestBody: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let body = RequestBody(
            model: AppConstants.haikuModel,
            max_tokens: 150,
            system: systemPrompt,
            messages: [.init(role: "user", content: content)]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractionError.apiError
        }

        return try parseExtractionResponse(data)
    }

    private func parseExtractionResponse(_ data: Data) throws -> ExtractionResult {
        // Anthropic response format: { content: [{ type: "text", text: "..." }] }
        struct AnthropicResponse: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = apiResponse.content.first(where: { $0.type == "text" })?.text else {
            throw ExtractionError.noContent
        }

        // Parse the JSON from the AI response
        struct TaskJSON: Decodable {
            let title: String
            let category: String?
            let suggestedDate: String?
        }

        // The AI might wrap JSON in markdown code fences — strip them
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ExtractionError.parseError
        }

        let taskJSON = try JSONDecoder().decode(TaskJSON.self, from: jsonData)

        let category = taskJSON.category.flatMap { TaskCategory(rawValue: $0) }

        var suggestedDate: Date?
        if let dateStr = taskJSON.suggestedDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            suggestedDate = formatter.date(from: dateStr)
            if suggestedDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                suggestedDate = formatter.date(from: dateStr)
            }
            if suggestedDate == nil {
                // Try date-only format (2026-04-17)
                formatter.formatOptions = [.withFullDate]
                suggestedDate = formatter.date(from: dateStr)
            }
        }

        return ExtractionResult(
            title: String(taskJSON.title.prefix(60)),
            category: category,
            suggestedDate: suggestedDate
        )
    }

    private enum ExtractionError: Error {
        case apiError
        case noContent
        case parseError
    }

    // MARK: - Shared ModelContainer

    private static func createSharedContainer() -> ModelContainer? {
        let schema = Schema(AppSchema.allModels)

        // Use the same App Group store URL as the main app
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        ) else { return nil }

        let appSupport = containerURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("MyAIssistant.store")

        // Extensions cannot use CloudKit — use local-only access to the shared store.
        // The main app's CloudKit sync will pick up the new record on next launch.
        let config = ModelConfiguration(
            "MyAIssistant",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try? ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    // MARK: - Widget Data

    private func updateWidgetData(context: ModelContext) {
        // Write minimal widget data to the App Group so widgets refresh
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { !$0.done },
            sortBy: [SortDescriptor(\.date)]
        )
        let pendingTasks = (try? context.fetch(descriptor)) ?? []
        let allDescriptor = FetchDescriptor<TaskItem>()
        let allCount = (try? context.fetchCount(allDescriptor)) ?? 0
        let doneCount = allCount - pendingTasks.count

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let widgetData = ExtWidgetSharedData(
            tasksCompleted: max(0, doneCount),
            tasksTotal: allCount,
            topPending: pendingTasks.prefix(5).map {
                ExtWidgetTaskData(
                    title: $0.title,
                    priority: $0.priorityRaw,
                    time: formatter.string(from: $0.date)
                )
            },
            streakDays: 0, // Extension doesn't compute streaks — main app will refresh
            streakActive: false,
            quoteText: nil,
            quoteAuthor: nil,
            updatedAt: Date()
        )
        widgetData.save()
    }
}
