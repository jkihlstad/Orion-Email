//
//  Networking.swift
//  EmailApp
//
//  Networking utilities for API communication
//

import Foundation
import os.log

// MARK: - Logger

private let networkLogger = Logger(subsystem: "com.orion.emailapp", category: "Networking")

// MARK: - HTTP Method

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Client Protocol

/// Protocol for API client implementations
public protocol APIClientProtocol: Sendable {
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)?,
        headers: [String: String]?,
        queryItems: [URLQueryItem]?
    ) async throws -> T

    func uploadData(
        endpoint: String,
        data: Data,
        mimeType: String,
        headers: [String: String]?
    ) async throws -> Data
}

// MARK: - API Error

/// Errors that can occur during API operations
public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decodingError(underlying: Error)
    case encodingError(underlying: Error)
    case networkError(underlying: Error)
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case timeout
    case cancelled
    case unknown(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, _):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Resource not found"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited. Please try again later"
        case .serverError(let code):
            return "Server error: \(code)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .unknown(let message):
            return message
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout, .networkError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Request Builder

/// Helper for building URL requests
public struct RequestBuilder {
    public let baseURL: URL
    public var defaultHeaders: [String: String]
    public var timeoutInterval: TimeInterval

    public init(baseURL: URL, defaultHeaders: [String: String] = [:], timeoutInterval: TimeInterval = 30) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
    }

    /// Build a URLRequest with the given parameters
    public func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Data? = nil,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        // Build URL with query items
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        if let queryItems = queryItems, !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval

        // Set default headers
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set custom headers (override defaults)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set body
        if let body = body {
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }
}

// MARK: - Response Handler

/// Helper for handling API responses
public struct ResponseHandler {
    public let decoder: JSONDecoder

    public init(decoder: JSONDecoder = .apiDecoder) {
        self.decoder = decoder
    }

    /// Handle URLSession response and decode to type T
    public func handleResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        try validateStatusCode(httpResponse.statusCode, data: data, response: httpResponse)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            networkLogger.error("Decoding error: \(error.localizedDescription)")
            throw APIError.decodingError(underlying: error)
        }
    }

    /// Validate HTTP status code
    public func validateStatusCode(_ statusCode: Int, data: Data?, response: HTTPURLResponse) throws {
        switch statusCode {
        case 200...299:
            return // Success
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: statusCode)
        default:
            throw APIError.httpError(statusCode: statusCode, data: data)
        }
    }
}

// MARK: - Base API Client

/// Base implementation of API client
public final class BaseAPIClient: APIClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let responseHandler: ResponseHandler
    private let encoder: JSONEncoder
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let debugMode: Bool

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        debugMode: Bool = false
    ) {
        var headers = defaultHeaders
        headers["Accept"] = "application/json"

        self.session = session
        self.requestBuilder = RequestBuilder(
            baseURL: baseURL,
            defaultHeaders: headers,
            timeoutInterval: timeoutInterval
        )
        self.responseHandler = ResponseHandler()
        self.encoder = .apiEncoder
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.debugMode = debugMode
    }

    /// Perform an API request with automatic retry on retryable errors
    public func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    headers: headers,
                    queryItems: queryItems
                )
            } catch let error as APIError where error.isRetryable {
                lastError = error

                if debugMode {
                    networkLogger.debug("Request failed (attempt \(attempt + 1)/\(self.maxRetries)): \(error.localizedDescription)")
                }

                // Wait before retry with exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? APIError.unknown(message: "Request failed after \(maxRetries) attempts")
    }

    /// Upload data (e.g., audio files)
    public func uploadData(
        endpoint: String,
        data: Data,
        mimeType: String,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = try requestBuilder.buildRequest(
            endpoint: endpoint,
            method: .post,
            headers: headers
        )

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var bodyData = Data()
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        bodyData.append(data)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = bodyData

        if debugMode {
            logRequest(request)
        }

        do {
            let (responseData, response) = try await session.data(for: request)

            if debugMode {
                logResponse(response, data: responseData)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            try responseHandler.validateStatusCode(httpResponse.statusCode, data: responseData, response: httpResponse)

            return responseData
        } catch let error as URLError {
            throw mapURLError(error)
        }
    }

    // MARK: - Private Methods

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)?,
        headers: [String: String]?,
        queryItems: [URLQueryItem]?
    ) async throws -> T {
        // Encode body if present
        var bodyData: Data? = nil
        if let body = body {
            do {
                bodyData = try encoder.encode(body)
            } catch {
                throw APIError.encodingError(underlying: error)
            }
        }

        let request = try requestBuilder.buildRequest(
            endpoint: endpoint,
            method: method,
            body: bodyData,
            headers: headers,
            queryItems: queryItems
        )

        if debugMode {
            logRequest(request)
        }

        do {
            let (data, response) = try await session.data(for: request)

            if debugMode {
                logResponse(response, data: data)
            }

            return try responseHandler.handleResponse(data: data, response: response)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkError(underlying: error)
        default:
            return .networkError(underlying: error)
        }
    }

    private func logRequest(_ request: URLRequest) {
        networkLogger.debug("---> \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")
        if let headers = request.allHTTPHeaderFields {
            networkLogger.debug("Headers: \(headers)")
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            networkLogger.debug("Body: \(bodyString)")
        }
    }

    private func logResponse(_ response: URLResponse, data: Data) {
        if let httpResponse = response as? HTTPURLResponse {
            networkLogger.debug("<--- \(httpResponse.statusCode) \(response.url?.absoluteString ?? "unknown")")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            let truncated = responseString.prefix(1000)
            networkLogger.debug("Response: \(truncated)")
        }
    }
}

// MARK: - JSON Encoder/Decoder Extensions

extension JSONEncoder {
    /// Standard API encoder with snake_case key encoding
    public static var apiEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Standard API decoder with snake_case key decoding
    public static var apiDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Reachability Helper

/// Simple reachability check
public actor NetworkReachability {
    public static let shared = NetworkReachability()

    private var isReachable: Bool = true

    private init() {}

    /// Check if network is reachable
    public func checkReachability() async -> Bool {
        // Simple implementation - try to reach a known endpoint
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                isReachable = httpResponse.statusCode == 200
                return isReachable
            }
            return false
        } catch {
            isReachable = false
            return false
        }
    }

    /// Get cached reachability state
    public func getCachedReachability() -> Bool {
        return isReachable
    }

    /// Update reachability state
    public func updateReachability(_ reachable: Bool) {
        isReachable = reachable
    }
}

// MARK: - Request Interceptor Protocol

/// Protocol for intercepting and modifying requests
public protocol RequestInterceptor: Sendable {
    func intercept(request: URLRequest) async throws -> URLRequest
    func intercept(response: URLResponse, data: Data) async throws -> (URLResponse, Data)
}

// MARK: - Auth Interceptor

/// Interceptor that adds authentication headers
public final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {
    private let tokenProvider: @Sendable () async throws -> String?

    public init(tokenProvider: @escaping @Sendable () async throws -> String?) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request

        if let token = try await tokenProvider() {
            modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return modifiedRequest
    }

    public func intercept(response: URLResponse, data: Data) async throws -> (URLResponse, Data) {
        return (response, data)
    }
}

// MARK: - Logging Interceptor

/// Interceptor for logging requests and responses
public final class LoggingInterceptor: RequestInterceptor, @unchecked Sendable {
    private let logger: Logger
    private let enabled: Bool

    public init(enabled: Bool = true) {
        self.logger = Logger(subsystem: "com.orion.emailapp", category: "API")
        self.enabled = enabled
    }

    public func intercept(request: URLRequest) async throws -> URLRequest {
        guard enabled else { return request }

        logger.info("---> \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        return request
    }

    public func intercept(response: URLResponse, data: Data) async throws -> (URLResponse, Data) {
        guard enabled else { return (response, data) }

        if let httpResponse = response as? HTTPURLResponse {
            logger.info("<--- \(httpResponse.statusCode) \(response.url?.absoluteString ?? "?")")
        }
        return (response, data)
    }
}
