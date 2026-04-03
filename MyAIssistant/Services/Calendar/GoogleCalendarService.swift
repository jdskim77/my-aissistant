import AuthenticationServices
import Foundation

/// Google Calendar REST API client using OAuth2 via ASWebAuthenticationSession.
actor GoogleCalendarService {
    private var clientID: String
    private var redirectURI: String
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    private let keychain = KeychainService()
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    init(clientID: String = "", redirectURI: String = "com.myaissistant:/oauth2callback") {
        self.clientID = clientID
        self.redirectURI = redirectURI
        // Load persisted tokens from Keychain
        self.accessToken = keychain.read(key: AppConstants.googleAccessTokenKey)
        self.refreshToken = keychain.read(key: AppConstants.googleRefreshTokenKey)
        if let expiryString = keychain.read(key: AppConstants.googleTokenExpiryKey),
           let expiryInterval = Double(expiryString) {
            self.tokenExpiry = Date(timeIntervalSince1970: expiryInterval)
        }
    }

    func updateClientID(_ newID: String) {
        self.clientID = newID
    }

    // MARK: - Auth

    var isAuthenticated: Bool {
        accessToken != nil
    }

    /// Build the OAuth2 authorization URL for use with ASWebAuthenticationSession.
    func authorizationURL() -> URL? {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[GoogleCalendarService] ERROR: client_id is empty")
            return nil
        }
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let url = components?.url
        print("[GoogleCalendarService] Auth URL: \(url?.absoluteString ?? "nil")")
        print("[GoogleCalendarService] client_id: \(clientID.prefix(20))...")
        return url
    }

    /// Exchange authorization code for access and refresh tokens.
    func exchangeCodeForTokens(_ code: String) async throws {
        let body: [String: String] = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]

        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        var request = URLRequest(url: try makeTokenURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.authFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        if let newRefresh = tokenResponse.refreshToken {
            self.refreshToken = newRefresh
        }
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        persistTokens()
    }

    func setAccessToken(_ token: String) {
        self.accessToken = token
        keychain.save(key: AppConstants.googleAccessTokenKey, value: token)
    }

    func signOut() {
        self.accessToken = nil
        self.refreshToken = nil
        self.tokenExpiry = nil
        clearPersistedTokens()
    }

    // MARK: - Token Persistence

    private func persistTokens() {
        if let accessToken {
            keychain.save(key: AppConstants.googleAccessTokenKey, value: accessToken)
        }
        if let refreshToken {
            keychain.save(key: AppConstants.googleRefreshTokenKey, value: refreshToken)
        }
        if let tokenExpiry {
            keychain.save(key: AppConstants.googleTokenExpiryKey, value: String(tokenExpiry.timeIntervalSince1970))
        }
    }

    private func clearPersistedTokens() {
        keychain.delete(key: AppConstants.googleAccessTokenKey)
        keychain.delete(key: AppConstants.googleRefreshTokenKey)
        keychain.delete(key: AppConstants.googleTokenExpiryKey)
    }

    // MARK: - Token Refresh

    private var isTokenExpired: Bool {
        guard let tokenExpiry else { return false }
        // Refresh 60 seconds before actual expiry to avoid edge cases
        return Date() >= tokenExpiry.addingTimeInterval(-60)
    }

    /// Refresh the access token using the stored refresh token.
    private func refreshAccessToken() async throws {
        guard let refreshToken else {
            throw GoogleCalendarError.notAuthenticated
        }

        let body: [String: String] = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ]

        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        var request = URLRequest(url: try makeTokenURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Refresh failed — clear tokens and require re-auth
            signOut()
            throw GoogleCalendarError.notAuthenticated
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        if let newRefresh = tokenResponse.refreshToken {
            self.refreshToken = newRefresh
        }
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        persistTokens()
    }

    /// Ensure we have a valid access token, refreshing if needed.
    private func ensureValidToken() async throws {
        guard accessToken != nil else { throw GoogleCalendarError.notAuthenticated }
        if isTokenExpired {
            try await refreshAccessToken()
        }
    }

    /// Execute an authenticated request with automatic 401 retry via token refresh.
    private func authenticatedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await ensureValidToken()

        var authedRequest = request
        authedRequest.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authedRequest)

        // If 401, attempt one token refresh and retry
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            var retryRequest = request
            retryRequest.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            return try await URLSession.shared.data(for: retryRequest)
        }

        return (data, response)
    }

    // MARK: - Safe URL Building

    private func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GoogleCalendarError.fetchFailed
        }
        return url
    }

    private func makeTokenURL() throws -> URL {
        guard let url = URL(string: tokenURL) else {
            throw GoogleCalendarError.authFailed
        }
        return url
    }

    // MARK: - Calendars

    func fetchCalendars() async throws -> [GoogleCalendar] {
        let url = try makeURL("/users/me/calendarList")
        let request = URLRequest(url: url)

        let (data, response) = try await authenticatedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.fetchFailed
        }

        let listResponse = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return listResponse.items
    }

    // MARK: - Events

    func fetchEvents(
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [GoogleEvent] {
        let formatter = ISO8601DateFormatter()
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        guard var components = URLComponents(string: "\(baseURL)/calendars/\(encodedID)/events") else {
            throw GoogleCalendarError.fetchFailed
        }
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: startDate)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: endDate)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]

        guard let url = components.url else {
            throw GoogleCalendarError.fetchFailed
        }
        let request = URLRequest(url: url)

        let (data, response) = try await authenticatedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.fetchFailed
        }

        let eventsResponse = try JSONDecoder().decode(EventListResponse.self, from: data)
        return eventsResponse.items ?? []
    }

    // MARK: - Create Event

    func createEvent(
        calendarID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        description: String? = nil
    ) async throws -> String {
        let formatter = ISO8601DateFormatter()
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        var eventBody: [String: Any] = [
            "summary": title,
            "start": ["dateTime": formatter.string(from: startDate)],
            "end": ["dateTime": formatter.string(from: endDate)],
        ]
        if let description {
            eventBody["description"] = description
        }

        let url = try makeURL("/calendars/\(encodedID)/events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

        let (data, response) = try await authenticatedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.writeFailed
        }

        let created = try JSONDecoder().decode(GoogleEvent.self, from: data)
        return created.id
    }

    // MARK: - Update Event

    func updateEvent(
        calendarID: String,
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        description: String? = nil
    ) async throws {
        let formatter = ISO8601DateFormatter()
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID

        var eventBody: [String: Any] = [
            "summary": title,
            "start": ["dateTime": formatter.string(from: startDate)],
            "end": ["dateTime": formatter.string(from: endDate)],
        ]
        if let description {
            eventBody["description"] = description
        }

        let url = try makeURL("/calendars/\(encodedCalID)/events/\(encodedEventID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

        let (_, response) = try await authenticatedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.writeFailed
        }
    }

    // MARK: - Delete Event

    func deleteEvent(calendarID: String, eventID: String) async throws {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID

        let url = try makeURL("/calendars/\(encodedCalID)/events/\(encodedEventID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await authenticatedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 410 else {
            throw GoogleCalendarError.writeFailed
        }
    }
}

// MARK: - Error

enum GoogleCalendarError: LocalizedError {
    case notAuthenticated
    case authFailed
    case fetchFailed
    case writeFailed
    case clientIDNotConfigured

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Google Calendar."
        case .authFailed: return "Google sign-in failed."
        case .fetchFailed: return "Failed to fetch Google Calendar data."
        case .writeFailed: return "Failed to write to Google Calendar."
        case .clientIDNotConfigured: return "Google Calendar is not configured yet."
        }
    }
}

// MARK: - Response Models

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct CalendarListResponse: Codable {
    let items: [GoogleCalendar]
}

struct GoogleCalendar: Codable, Identifiable {
    let id: String
    let summary: String
    let backgroundColor: String?
    let primary: Bool?

    var displayName: String { summary }
}

struct EventListResponse: Codable {
    let items: [GoogleEvent]?
}

struct GoogleEvent: Codable, Identifiable {
    let id: String
    let summary: String?
    let start: GoogleDateTime?
    let end: GoogleDateTime?
    let description: String?

    var title: String { summary ?? "Untitled" }

    var startDate: Date? {
        if let dateTime = start?.dateTime {
            return ISO8601DateFormatter().date(from: dateTime)
        }
        if let dateStr = start?.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr)
        }
        return nil
    }
}

struct GoogleDateTime: Codable {
    let dateTime: String?
    let date: String?
}
