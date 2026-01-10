//
//  BrainAPIClient.swift
//  EmailApp
//
//  Low-level client for Brain/AI server endpoints
//

import Foundation
import os.log

// MARK: - Logger

private let brainLogger = Logger(subsystem: "com.orion.emailapp", category: "BrainAPI")

// MARK: - Brain API Error

/// Errors specific to Brain API operations
public enum BrainAPIError: Error, LocalizedError, Sendable {
    case invalidConfiguration(reason: String)
    case unauthorized
    case forbidden
    case notFound(resource: String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String)
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case encodingError(underlying: Error)
    case timeout
    case cancelled
    case invalidResponse
    case serviceUnavailable
    case unknown(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access denied"
        case .notFound(let resource):
            return "Resource not found: \(resource)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited. Please try again later"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decodingError(let underlying):
            return "Failed to parse response: \(underlying.localizedDescription)"
        case .encodingError(let underlying):
            return "Failed to encode request: \(underlying.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .invalidResponse:
            return "Invalid response from server"
        case .serviceUnavailable:
            return "Service is temporarily unavailable"
        case .unknown(let message):
            return message
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout, .networkError, .serviceUnavailable:
            return true
        default:
            return false
        }
    }

    public var suggestedRetryDelay: TimeInterval {
        switch self {
        case .rateLimited(let retryAfter):
            return retryAfter ?? 30
        case .serverError:
            return 5
        case .timeout, .networkError, .serviceUnavailable:
            return 2
        default:
            return 1
        }
    }
}

// MARK: - Brain API Configuration

/// Configuration for the Brain API client
public struct BrainAPIConfiguration: Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval
    public let maxRetries: Int
    public let retryDelay: TimeInterval
    public let debugMode: Bool

    public init(
        baseURL: URL,
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        debugMode: Bool = false
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.debugMode = debugMode
    }

    /// Default configuration (should be overridden with actual server URL)
    public static var `default`: BrainAPIConfiguration {
        BrainAPIConfiguration(
            baseURL: URL(string: "https://api.orion.app/brain")!,
            timeout: 30,
            maxRetries: 3,
            retryDelay: 1.0,
            debugMode: false
        )
    }

    #if DEBUG
    public static var development: BrainAPIConfiguration {
        BrainAPIConfiguration(
            baseURL: URL(string: "http://localhost:3000/brain")!,
            timeout: 60,
            maxRetries: 1,
            retryDelay: 0.5,
            debugMode: true
        )
    }
    #endif
}

// MARK: - Brain API Endpoints

/// Available Brain API endpoints
public enum BrainEndpoint: String {
    case summarize = "/ai/summarize"
    case suggestReplies = "/ai/suggest-replies"
    case extractTasks = "/ai/extract-tasks"
    case askQuestion = "/ai/ask"
    case relatedMemories = "/ai/memories"
    case transcribe = "/voice/transcribe"
    case textToSpeech = "/voice/tts"
    case consents = "/user/consents"
}

// MARK: - Brain API Client

/// Low-level client for Brain/AI server communication
public actor BrainAPIClient {
    // MARK: - Properties

    private let configuration: BrainAPIConfiguration
    private let session: URLSession
    private let authProvider: AuthSessionProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initialization

    public init(
        configuration: BrainAPIConfiguration = .default,
        session: URLSession = .shared,
        authProvider: AuthSessionProviding
    ) {
        self.configuration = configuration
        self.session = session
        self.authProvider = authProvider

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Perform a GET request
    public func get<T: Decodable>(
        endpoint: BrainEndpoint,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        return try await request(
            endpoint: endpoint.rawValue,
            method: .get,
            body: nil as EmptyBody?,
            queryItems: queryItems
        )
    }

    /// Perform a POST request with body
    public func post<T: Decodable, B: Encodable>(
        endpoint: BrainEndpoint,
        body: B
    ) async throws -> T {
        return try await request(
            endpoint: endpoint.rawValue,
            method: .post,
            body: body
        )
    }

    /// Perform a POST request without response body
    public func post<B: Encodable>(
        endpoint: BrainEndpoint,
        body: B
    ) async throws {
        let _: EmptyResponse = try await request(
            endpoint: endpoint.rawValue,
            method: .post,
            body: body
        )
    }

    /// Upload audio data for transcription
    public func uploadAudio(data: Data, mimeType: String = "audio/wav") async throws -> TranscriptionResult {
        let responseData = try await uploadData(
            endpoint: BrainEndpoint.transcribe.rawValue,
            data: data,
            mimeType: mimeType
        )

        return try decoder.decode(TranscriptionResult.self, from: responseData)
    }

    /// Get TTS audio for text
    public func getTTSAudio(text: String, voice: VoiceType, speed: Float = 1.0) async throws -> Data {
        let request = TTSRequest(text: text, voice: voice, speed: speed)

        let url = configuration.baseURL.appendingPathComponent(BrainEndpoint.textToSpeech.rawValue)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // Add auth token
        let token = try await authProvider.getAccessToken()
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        urlRequest.httpBody = try encoder.encode(request)

        if configuration.debugMode {
            brainLogger.debug("TTS Request: \(text.prefix(50))...")
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainAPIError.invalidResponse
        }

        try validateResponse(httpResponse, data: data)

        return data
    }

    // MARK: - Private Methods

    /// Perform a request with retries
    private func request<T: Decodable, B: Encodable>(
        endpoint: String,
        method: HTTPMethod,
        body: B?,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var lastError: BrainAPIError?

        for attempt in 0..<configuration.maxRetries {
            do {
                return try await performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    queryItems: queryItems
                )
            } catch let error as BrainAPIError where error.isRetryable {
                lastError = error

                if configuration.debugMode {
                    brainLogger.debug("Request failed (attempt \(attempt + 1)/\(self.configuration.maxRetries)): \(error.localizedDescription)")
                }

                if attempt < configuration.maxRetries - 1 {
                    let delay = configuration.retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch let error as BrainAPIError {
                throw error
            } catch {
                throw BrainAPIError.unknown(message: error.localizedDescription)
            }
        }

        throw lastError ?? BrainAPIError.unknown(message: "Request failed after \(configuration.maxRetries) attempts")
    }

    /// Perform a single request attempt
    private func performRequest<T: Decodable, B: Encodable>(
        endpoint: String,
        method: HTTPMethod,
        body: B?,
        queryItems: [URLQueryItem]?
    ) async throws -> T {
        // Build URL
        var urlComponents = URLComponents(url: configuration.baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        if let queryItems = queryItems {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw BrainAPIError.invalidConfiguration(reason: "Invalid URL")
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth token
        do {
            let token = try await authProvider.getAccessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            throw BrainAPIError.unauthorized
        }

        // Encode body
        if let body = body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw BrainAPIError.encodingError(underlying: error)
            }
        }

        if configuration.debugMode {
            logRequest(request)
        }

        // Perform request
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw BrainAPIError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainAPIError.invalidResponse
        }

        if configuration.debugMode {
            logResponse(httpResponse, data: data)
        }

        // Validate response
        try validateResponse(httpResponse, data: data)

        // Decode response
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BrainAPIError.decodingError(underlying: error)
        }
    }

    /// Upload data (for audio files)
    private func uploadData(
        endpoint: String,
        data: Data,
        mimeType: String
    ) async throws -> Data {
        let url = configuration.baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout

        // Add auth token
        do {
            let token = try await authProvider.getAccessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            throw BrainAPIError.unauthorized
        }

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

        if configuration.debugMode {
            brainLogger.debug("Uploading \(data.count) bytes to \(endpoint)")
        }

        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw BrainAPIError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainAPIError.invalidResponse
        }

        try validateResponse(httpResponse, data: responseData)

        return responseData
    }

    /// Validate HTTP response
    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw BrainAPIError.unauthorized
        case 403:
            throw BrainAPIError.forbidden
        case 404:
            throw BrainAPIError.notFound(resource: response.url?.path ?? "unknown")
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw BrainAPIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            let message = parseErrorMessage(from: data)
            throw BrainAPIError.serverError(statusCode: response.statusCode, message: message)
        default:
            let message = parseErrorMessage(from: data)
            throw BrainAPIError.serverError(statusCode: response.statusCode, message: message)
        }
    }

    /// Parse error message from response data
    private func parseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String {
                return message
            }
            if let error = json["error"] as? String {
                return error
            }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    /// Map URLError to BrainAPIError
    private func mapURLError(_ error: URLError) -> BrainAPIError {
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

    // MARK: - Logging

    private func logRequest(_ request: URLRequest) {
        brainLogger.debug("---> \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            brainLogger.debug("Body: \(bodyString.prefix(500))")
        }
    }

    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        brainLogger.debug("<--- \(response.statusCode) \(response.url?.absoluteString ?? "?")")
        if let responseString = String(data: data, encoding: .utf8) {
            brainLogger.debug("Response: \(responseString.prefix(500))")
        }
    }
}

// MARK: - Helper Types

/// Empty body for GET requests
private struct EmptyBody: Encodable {}

/// Empty response for POST requests without response body
private struct EmptyResponse: Decodable {}

// MARK: - HTTP Method (reused from Networking.swift if not already imported)

extension BrainAPIClient {
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }
}
