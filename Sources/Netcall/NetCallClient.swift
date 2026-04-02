import Foundation

public protocol NetCallClientProtocol: Sendable {
    /// Fetch
    func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T
    
    /// Header
    func updateSharedHeaders(_ headers: [String: String]) async
    func setSharedHeader(name: String, value: String?) async

    /// Base URL
    func updateBaseURL(_ baseURL: String?) async
}

/// NetCallClient class used to execute http requests
public actor NetCallClient: NetCallClientProtocol {
    // MARK: - Properties
    public static let shared = NetCallClient()
    private let session: URLSession
    private var sharedHeaders: [String: String]
    private var baseURL: URL?

    // MARK: - Init
    private init(sharedHeaders: [String: String] = [:], baseURL: URL? = nil) {
        let conf = URLSessionConfiguration.default
        conf.allowsExpensiveNetworkAccess = true
        conf.httpMaximumConnectionsPerHost = 60
        conf.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: conf)
        self.sharedHeaders = sharedHeaders
        self.baseURL = baseURL
    }

    // MARK: - Public functions
    public func updateSharedHeaders(_ headers: [String: String]) {
        self.sharedHeaders = headers
    }

    public func setSharedHeader(name: String, value: String?) {
        if let value {
            sharedHeaders[name] = value
        } else {
            sharedHeaders.removeValue(forKey: name)
        }
    }

    public func updateBaseURL(_ baseURL: String?) {
        if let baseURL {
            self.baseURL = URL(string: baseURL)
        } else {
            self.baseURL = nil
        }
    }

    /// Aims to execute http request
    /// - Parameters:
    ///   - requestInfo: NetCallRequestInfo
    /// - Returns: Decoded response payload
    public func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T {
        let urlRequest = try getUrlRequest(requestInfo: requestInfo)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetCallError.responseFormat
        }

        try validateStatusCode(httpResponse, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw mapDecodingError(error)
        }
    }

    // MARK: - Private functions
    /// Aims to get an URLRequest. Will throw an NetCallError if URL cannot be generated from the given NetCallRequestInfo
    /// - Parameters:
    ///   - requestInfo: NetCallRequestInfo
    /// - Returns: URLRequest
    private func getUrlRequest(requestInfo: NetCallRequestInfo) throws -> URLRequest {
        let endPointUrl = try resolveURL(from: requestInfo.urlTarget)

        var urlComponents = URLComponents(url: endPointUrl, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = requestInfo.queryItems

        guard let urlForRequest = urlComponents?.url else {
            throw NetCallError.badRequest
        }

        var urlRequest = URLRequest(url: urlForRequest)
        urlRequest.httpMethod = requestInfo.methodName

        if let timeoutInterval = requestInfo.callParam.timeoutInterval {
            urlRequest.timeoutInterval = timeoutInterval
        }

        for (name, value) in makeHeaders(for: requestInfo) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        if let requestBody = requestInfo.body {
            switch requestBody {
            case .json(let data):
                urlRequest.httpBody = data
                if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            case .raw(let data, let contentType):
                urlRequest.httpBody = data
                if let contentType {
                    urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
                }
            }
        }

        return urlRequest
    }

    private func makeHeaders(for requestInfo: NetCallRequestInfo) -> [String: String] {
        if requestInfo.headerParam.useSharedHeaders {
            return sharedHeaders.merging(requestInfo.headerParam.headers) { _, requestValue in requestValue }
        }

        return requestInfo.headerParam.headers
    }

    private func resolveURL(from urlTarget: NetCallRequestInfo.URLTarget) throws -> URL {
        switch urlTarget {
        case .fullURL(let fullURL):
            guard let url = URL(string: fullURL) else {
                throw NetCallError.badRequest
            }
            return url
        case .pathComponent(let pathComponent):
            guard let baseURL else {
                throw NetCallError.badRequest
            }
            return baseURL.appendingPathComponent(pathComponent)
        }
    }

    private func validateStatusCode(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw NetCallError.unauthorized
        case 400..<500:
            throw NetCallError.clientError(code: response.statusCode)
        case 500..<600:
            throw NetCallError.serverError(code: response.statusCode)
        default:
            throw NetCallError.customError(
                message: "Unknown status code: \(response.statusCode). Body: \(bodyDescription(from: data))"
            )
        }
    }

    private func mapTransportError(_ error: Error) -> NetCallError {
        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .networkError(code: urlError.code)
        }

        if let netCallError = error as? NetCallError {
            return netCallError
        }

        return .customError(message: "Transport error", error: error)
    }

    private func mapDecodingError(_ error: Error) -> NetCallError {
        if let decodingError = error as? DecodingError {
            return .decodingError(message: String(describing: decodingError))
        }

        return .customError(message: "Decoding failed", error: error)
    }

    private func bodyDescription(from data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        return String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
    }
}
