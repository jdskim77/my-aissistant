import AuthenticationServices
import Foundation

/// Google Calendar REST API client using OAuth2 via ASWebAuthenticationSession.
actor GoogleCalendarService {
    private let clientID: String
    private let redirectURI: String
    private var accessToken: String?
    private var refreshToken: String?

    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    init(clientID: String = "", redirectURI: String = "com.myaissistant:/oauth2callback") {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    // MARK: - Auth

    var isAuthenticated: Bool {
        accessToken != nil
    }

    /// Build the OAuth2 authorization URL for use with ASWebAuthenticationSession.
    func authorizationURL() -> URL? {
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
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

        var request = URLRequest(url: URL(string: tokenURL)!)
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
        self.refreshToken = tokenResponse.refreshToken
    }

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    func signOut() {
        self.accessToken = nil
        self.refreshToken = nil
    }

    // MARK: - Calendars

    func fetchCalendars() async throws -> [GoogleCalendar] {
        guard let accessToken else { throw GoogleCalendarError.notAuthenticated }

        var request = URLRequest(url: URL(string: "\(baseURL)/users/me/calendarList")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
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
        guard let accessToken else { throw GoogleCalendarError.notAuthenticated }

        let formatter = ISO8601DateFormatter()
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: startDate)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: endDate)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.fetchFailed
        }

        let eventsResponse = try JSONDecoder().decode(EventListResponse.self, from: data)
        return eventsResponse.items ?? []
    }
}

// MARK: - Error

enum GoogleCalendarError: LocalizedError {
    case notAuthenticated
    case authFailed
    case fetchFailed
    case clientIDNotConfigured

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Google Calendar."
        case .authFailed: return "Google sign-in failed."
        case .fetchFailed: return "Failed to fetch Google Calendar data."
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
