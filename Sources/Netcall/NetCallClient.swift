import Foundation

public protocol NetCallClientProtocol: Sendable {
    func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T
}

/// NetCallClient class used to execute http requests
public actor NetCallClient: NetCallClientProtocol {
    // MARK: - Properties
    public static let shared = NetCallClient()
    private let session: URLSession
    
    // MARK: - Init
    private init() {
        let conf = URLSessionConfiguration.default
        conf.allowsExpensiveNetworkAccess = true
        conf.httpMaximumConnectionsPerHost = 60
        conf.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: conf)
    }
    
    // MARK: - Public functions
    /// Aims to execute http request
    /// - Parameters:
    ///   - method: HTTPMethod
    /// - Returns: Result<T, NetCallError>
    public func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T {
        let urlRequest = try getUrlRequest(requestInfo: requestInfo)
        let (data, response) = try await self.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetCallError.responseFormat
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let decodedData = try JSONDecoder().decode(T.self, from: data)
            return decodedData
        case 401:
            throw NetCallError.unauthorized
        case 400..<500:
            throw NetCallError.clientError(code: httpResponse.statusCode)
        case 500..<600:
            throw NetCallError.serverError(code: httpResponse.statusCode)
        default:
            throw NetCallError.customError(message: "Unknown Status code")
        }
    }
    
    // MARK: - Private functions
    /// Aims to get an URLRequest. Will throw an NetCallError if URL cannot be generated from the given NetCallRequestInfo
    /// - Parameters:
    ///   - requestInfo: NetCallRequestInfo
    /// - Returns: URLRequest
    private func getUrlRequest(requestInfo: NetCallRequestInfo) throws -> URLRequest {
        // Instanciate endPointUrl from endpoint path
        guard let endPointUrl = URL(string: requestInfo.urlString) else {
            throw NetCallError.badRequest
        }
        // Instanciate urlComponents with endPointUrl
        var urlComponents = URLComponents(url: endPointUrl,
                                          resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = requestInfo.queryItems
        guard let urlForRequest = urlComponents?.url else {
            throw NetCallError.badRequest
        }
        // Instanciate an urlRequest with urlForRequest
        var urlRequest = URLRequest(url: urlForRequest)
        // Add http method to urlRequest
        urlRequest.httpMethod = requestInfo.name

        // Return urlRequest
        return urlRequest
    }
}
