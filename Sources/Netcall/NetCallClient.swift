import Foundation

public typealias NetCallUnauthorizedRefreshHook = @Sendable () async throws -> Void

public protocol NetCallClientProtocol: Sendable {
    /// Fetch
    func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T
    
    /// Header
    func updateSharedHeaders(_ headers: [String: String]) async
    func setSharedHeader(name: String, value: String?) async

    /// Base URL
    func updateBaseURL(_ baseURL: String?) async

    /// Request lifecycle
    func cancelAll() async

    /// Auth
    func setUnauthorizedRefreshHook(_ hook: NetCallUnauthorizedRefreshHook?) async
}

/// NetCallClient class used to execute http requests
public actor NetCallClient: NetCallClientProtocol {
    // MARK: - Properties
    public static let shared = NetCallClient()
    private let session: URLSession
    private var sharedHeaders: [String: String]
    private var baseURL: URL?
    private var activeNetworkTasks: [UUID: Task<(Data, URLResponse), Error>]
    private var unauthorizedRefreshHook: NetCallUnauthorizedRefreshHook?
    private var unauthorizedRefreshTask: Task<Void, Error>?

    // MARK: - Init
    private init(sharedHeaders: [String: String] = [:], baseURL: URL? = nil) {
        let conf = URLSessionConfiguration.default
        conf.allowsExpensiveNetworkAccess = true
        conf.httpMaximumConnectionsPerHost = 60
        conf.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: conf)
        self.sharedHeaders = sharedHeaders
        self.baseURL = baseURL
        self.activeNetworkTasks = [:]
        self.unauthorizedRefreshHook = nil
        self.unauthorizedRefreshTask = nil
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

    public func cancelAll() {
        for task in activeNetworkTasks.values {
            task.cancel()
        }
        activeNetworkTasks.removeAll()

        unauthorizedRefreshTask?.cancel()
        unauthorizedRefreshTask = nil
    }

    public func setUnauthorizedRefreshHook(_ hook: NetCallUnauthorizedRefreshHook?) {
        unauthorizedRefreshHook = hook
    }

    /// Aims to execute http request
    /// - Parameters:
    ///   - requestInfo: NetCallRequestInfo
    /// - Returns: Decoded response payload
    public func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T {
        let data = try await performRequest(requestInfo: requestInfo)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw mapDecodingError(error)
        }
    }

    // MARK: - Private functions
    private func performRequest(requestInfo: NetCallRequestInfo) async throws -> Data {
        var retryCount = 0
        var hasWaitedForUnauthorizedRefresh = false

        while true {
            do {
                let (data, response) = try await executeNetworkRequest(requestInfo: requestInfo)

                switch response.statusCode {
                case 200..<300:
                    return data
                case 401:
                    if !requestInfo.callParam.isRefreshCall && !hasWaitedForUnauthorizedRefresh {
                        hasWaitedForUnauthorizedRefresh = true
                        try await synchronizeUnauthorizedRefresh()
                        continue
                    }

                    let unauthorizedError = NetCallError.unauthorized
                    guard shouldRetry(error: unauthorizedError,
                                      retryCount: retryCount,
                                      callParam: requestInfo.callParam) else {
                        throw unauthorizedError
                    }

                    try await waitBeforeRetry(retryCount: retryCount, callParam: requestInfo.callParam)
                    retryCount += 1
                case 400..<500:
                    let clientError = NetCallError.clientError(code: response.statusCode)
                    guard shouldRetry(error: clientError,
                                      retryCount: retryCount,
                                      callParam: requestInfo.callParam) else {
                        throw clientError
                    }

                    try await waitBeforeRetry(retryCount: retryCount, callParam: requestInfo.callParam)
                    retryCount += 1
                case 500..<600:
                    let serverError = NetCallError.serverError(code: response.statusCode)
                    guard shouldRetry(error: serverError,
                                      retryCount: retryCount,
                                      callParam: requestInfo.callParam) else {
                        throw serverError
                    }

                    try await waitBeforeRetry(retryCount: retryCount, callParam: requestInfo.callParam)
                    retryCount += 1
                default:
                    let unknownStatusError = NetCallError.customError(
                        message: "Unknown status code: \(response.statusCode). Body: \(bodyDescription(from: data))"
                    )
                    guard shouldRetry(error: unknownStatusError,
                                      retryCount: retryCount,
                                      callParam: requestInfo.callParam) else {
                        throw unknownStatusError
                    }

                    try await waitBeforeRetry(retryCount: retryCount, callParam: requestInfo.callParam)
                    retryCount += 1
                }
            } catch {
                let mappedError = mapTransportError(error)
                guard shouldRetry(error: mappedError,
                                  retryCount: retryCount,
                                  callParam: requestInfo.callParam) else {
                    throw mappedError
                }

                try await waitBeforeRetry(retryCount: retryCount, callParam: requestInfo.callParam)
                retryCount += 1
            }
        }
    }

    private func executeNetworkRequest(requestInfo: NetCallRequestInfo) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try getUrlRequest(requestInfo: requestInfo)
        let taskID = UUID()
        let task = Task { try await session.data(for: urlRequest) }
        activeNetworkTasks[taskID] = task

        defer {
            activeNetworkTasks.removeValue(forKey: taskID)
        }

        do {
            let (data, response) = try await task.value
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetCallError.responseFormat
            }
            return (data, httpResponse)
        } catch {
            throw mapTransportError(error)
        }
    }

    private func synchronizeUnauthorizedRefresh() async throws {
        var createdTask = false
        if unauthorizedRefreshTask == nil {
            guard let unauthorizedRefreshHook else {
                throw NetCallError.unauthorized
            }
            unauthorizedRefreshTask = Task {
                try await unauthorizedRefreshHook()
            }
            createdTask = true
        }

        guard let refreshTask = unauthorizedRefreshTask else {
            throw NetCallError.unauthorized
        }

        defer {
            if createdTask {
                unauthorizedRefreshTask = nil
            }
        }

        do {
            try await refreshTask.value
        } catch {
            throw NetCallError.customError(message: "Unauthorized refresh failed", error: error)
        }
    }

    private func shouldRetry(error: NetCallError,
                             retryCount: Int,
                             callParam: NetCallRequestInfo.CallParam) -> Bool {
        guard let retryPolicy = callParam.retryPolicy else {
            return false
        }

        guard retryCount < retryPolicy.maxRetry else {
            return false
        }

        switch error {
        case .networkError, .serverError:
            return true
        case .unauthorized:
            return retryPolicy.retryOnUnauthorized
        default:
            return false
        }
    }

    private func waitBeforeRetry(retryCount: Int, callParam: NetCallRequestInfo.CallParam) async throws {
        guard let retryPolicy = callParam.retryPolicy else {
            return
        }

        let delay = retryPolicy.retryDelay * pow(retryPolicy.backoffMultiplier, Double(retryCount))
        guard delay > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

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

    private func mapTransportError(_ error: Error) -> NetCallError {
        if let netCallError = error as? NetCallError {
            return netCallError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .networkError(code: urlError.code)
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
