import Foundation
import UIKit

/// What can go wrong talking to the desktop, each with one plain sentence for the person.
nonisolated enum APIError: Error, Equatable, Sendable {
    case notPaired
    case badAddress
    case offline(String)
    case unauthorized
    case server(status: Int, detail: String)
    case unreadable(String)

    var plain: String {
        switch self {
        case .notPaired:
            return "This iPhone is not paired with a desktop yet."
        case .badAddress:
            return "That address does not look right. Use the one Kairos shows, like desk.example.com."
        case .offline(let reason):
            return reason
        case .unauthorized:
            return "This iPhone is no longer paired. Pair it again from your desktop."
        case .server(let status, let detail):
            return detail.isEmpty ? "Your desktop answered with an error (\(status))." : detail
        case .unreadable:
            return "Your desktop sent something this app could not read. Update Kairos, or update this app."
        }
    }

    /// The desktop was not reached at all (as opposed to reached and refusing).
    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    /// Any thrown error as one plain sentence.
    static func plain(_ error: Error) -> String {
        if let error = error as? APIError { return error.plain }
        if error is CancellationError { return "Stopped." }
        return "Something went wrong. Try again."
    }

    static func from(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline("This iPhone is offline. Check Wi-Fi or mobile data.")
        case .timedOut:
            return .offline("Your desktop took too long to answer. Check that Kairos is open on it.")
        case .cannotFindHost, .dnsLookupFailed:
            return .offline("That address could not be found. Check it against the one Kairos shows.")
        case .cannotConnectToHost, .networkConnectionLost:
            return .offline("Your desktop did not answer. Check that Kairos is open and remote access is on.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return .offline("A secure connection could not be made to that address.")
        case .appTransportSecurityRequiresSecureConnection:
            return .offline("The address must be a secure one that starts with https.")
        case .badURL, .unsupportedURL:
            return .badAddress
        default:
            return .offline("Your desktop could not be reached. Try again in a moment.")
        }
    }
}

/// The desktop's `{"detail": ...}` error body. FastAPI sends text, or a list of `{msg}` for a bad request.
nonisolated struct APIErrorBody: Decodable, Sendable {
    var detail: JSONValue?

    var text: String {
        guard let detail else { return "" }
        if let text = detail.string { return text }
        if let first = detail.array?.first, let message = first["msg"]?.string { return message }
        return ""
    }
}

/// A file staged for upload or just read from the phone.
nonisolated struct OutgoingFile: Hashable, Sendable {
    var name: String
    var mimeType: String
    var data: Data
}

/// Talks to one desktop: builds the address, signs every request with the phone's token,
/// sends and reads JSON, and turns every failure into an `APIError`.
final class APIClient {
    let base: URL
    private let token: String?
    private let session: URLSession
    private let streamSession: URLSession

    init(base: URL, token: String?) {
        self.base = base
        self.token = token
        let plain = URLSessionConfiguration.ephemeral
        plain.timeoutIntervalForRequest = 30
        plain.timeoutIntervalForResource = 180
        plain.waitsForConnectivity = false
        plain.httpCookieStorage = nil
        plain.httpShouldSetCookies = false
        session = URLSession(configuration: plain)
        // The live stream sends a keepalive every 15 seconds; 45 seconds of nothing means it is gone.
        let stream = URLSessionConfiguration.ephemeral
        stream.timeoutIntervalForRequest = 45
        stream.timeoutIntervalForResource = 60 * 60 * 24
        stream.httpCookieStorage = nil
        stream.httpShouldSetCookies = false
        streamSession = URLSession(configuration: stream)
    }

    /// Turn what the person typed ("desk.example.com", "https://desk.example.com/") into a base address.
    static func baseURL(from typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            // Another kind of address (ftp://...) is not a Kairos desktop.
            guard !text.contains("://") else { return nil }
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              let url = components.url else { return nil }
        return url
    }

    // MARK: Building requests

    func url(_ path: String, query: [String: String?] = [:]) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw APIError.badAddress }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = prefix + (path.hasPrefix("/") ? path : "/" + path)
        let items = query.keys.sorted().compactMap { key -> URLQueryItem? in
            guard let value = query[key] ?? nil else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty {
            components.queryItems = items
            // A plus sign in a file name must not arrive as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.badAddress }
        return url
    }

    func urlRequest(_ method: String, _ path: String, query: [String: String?] = [:]) throws -> URLRequest {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    // MARK: Sending

    /// Send a request and hand back the answer's bytes, or throw an `APIError`.
    func send(_ request: URLRequest) async throws -> Data {
        let answer: (Data, URLResponse)
        do {
            answer = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline("Your desktop could not be reached. Try again in a moment.")
        }
        try APIClient.check(answer.1, body: answer.0)
        return answer.0
    }

    static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.offline("Your desktop could not be reached. Try again in a moment.")
        }
        guard !(200..<300).contains(http.statusCode) else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        let detail = (try? KJSON.decode(APIErrorBody.self, from: body))?.text ?? ""
        if detail.isEmpty {
            switch http.statusCode {
            case 403: throw APIError.server(status: 403, detail: "Your account on the desktop is not allowed to do that.")
            case 404: throw APIError.server(status: 404, detail: "Your desktop does not have that. It may need a newer Kairos.")
            case 413: throw APIError.server(status: 413, detail: "That file is too large to send.")
            case 429: throw APIError.server(status: 429, detail: "Too many tries. Wait a moment and try again.")
            case 502, 503, 504: throw APIError.offline("Your desktop did not answer. Check that Kairos is open and remote access is on.")
            default: break
            }
        }
        throw APIError.server(status: http.statusCode, detail: detail)
    }

    private func body(_ json: [String: Any]?) throws -> Data? {
        guard let json else { return nil }
        guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try KJSON.decode(T.self, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    /// Any method. A JSON body is sent when `json` is given, even an empty one.
    func request<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:], json: [String: Any]? = nil) async throws -> T {
        var request = try urlRequest(method, path, query: query)
        if let data = try body(json) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try decode(try await send(request))
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await request("GET", path, query: query)
    }

    func post<T: Decodable>(_ path: String, json: [String: Any] = [:]) async throws -> T {
        try await request("POST", path, json: json)
    }

    /// Any method where the answer's body does not matter (a 202 or a 204 is fine).
    func call(_ method: String, _ path: String, query: [String: String?] = [:], json: [String: Any]? = nil) async throws {
        var request = try urlRequest(method, path, query: query)
        if let data = try body(json) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        _ = try await send(request)
    }

    /// The raw bytes of a file on the desktop.
    func bytes(_ path: String, query: [String: String?] = [:]) async throws -> Data {
        var request = try urlRequest("GET", path, query: query)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return try await send(request)
    }

    /// Send one file as a form upload under the field name `file`.
    func upload<T: Decodable>(_ path: String, file: OutgoingFile) async throws -> T {
        var request = try urlRequest("POST", path)
        let boundary = "kairos-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let safeName = file.name.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try decode(try await send(request))
    }

    /// Open a server-sent event stream. The caller reads its lines until it ends or throws.
    func openStream(_ path: String) async throws -> URLSession.AsyncBytes {
        var request = try urlRequest("GET", path)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (bytes, response) = try await streamSession.bytes(for: request)
            try APIClient.check(response, body: Data())
            return bytes
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        }
    }

    // MARK: This phone

    /// The hardware name, like "iPhone17,1".
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let text = mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 { result.append(Character(UnicodeScalar(UInt8(value)))) }
        }
        return text.isEmpty ? "iPhone" : text
    }

    static var deviceName: String { UIDevice.current.name }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
