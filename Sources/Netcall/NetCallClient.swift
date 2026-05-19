import Foundation
import UIKit
import PrintUI

/// NetCallClient class used to execute http requests
public actor NetCallClient: NetCallClientProtocol {
    // MARK: - Properties
    let session: URLSession
    var imageCacheManager: ImageCacheManagerProtocol
    var sharedHeaders: [String: String]
    var sharedImageHeaders: [String: String]
    var baseURL: URL?
    var activeNetworkTasks: [UUID: Task<(Data, URLResponse), Error>]
    var unauthorizedRefreshHook: NetCallUnauthorizedRefreshHook?
    var unauthorizedRefreshTask: Task<Void, Error>?
    
    // MARK: - Init
    public init(session: URLSession = .shared,
                imageCacheManager: ImageCacheManagerProtocol = ImageCacheManager(),
                sharedHeaders: [String: String] = [:],
                sharedImageHeaders: [String: String] = [:],
                baseURL: URL? = nil) {
        self.session = session
        self.imageCacheManager = imageCacheManager
        self.sharedHeaders = sharedHeaders
        self.sharedImageHeaders = sharedImageHeaders
        self.baseURL = baseURL
        self.activeNetworkTasks = [:]
        self.unauthorizedRefreshHook = nil
        self.unauthorizedRefreshTask = nil
    }
    
    // MARK: - Shared
    public static let shared = NetCallClient(session: makeDefaultSession())
    
    private static func makeDefaultSession() -> URLSession {
        let conf = URLSessionConfiguration.default
        conf.allowsExpensiveNetworkAccess = true
        conf.httpMaximumConnectionsPerHost = 60
        conf.timeoutIntervalForRequest = 30
        return URLSession(configuration: conf)
    }
    
    // MARK: - Public static functions
    public static func disableLogging() {
        LoggerManager.instance.disableDefaultSubsystem()
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
    
    public func setImageSharedHeader(name: String, value: String?) {
        if let value {
            sharedImageHeaders[name] = value
        } else {
            sharedImageHeaders.removeValue(forKey: name)
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
    
    /// Executes an HTTP request and decodes the JSON response.
    /// - Parameters:
    ///   - requestInfo: NetCallRequestInfo
    ///   - decoder: JSONDecoder to use for decoding
    /// - Returns: Decoded response payload
    public func fetchRemoteData<T: Codable & Sendable>(
        requestInfo: NetCallRequestInfo,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await requestData(requestInfo: requestInfo)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw mapDecodingError(error)
        }
    }
    
    /// Executes an HTTP request without reading the response body.
    public func request(requestInfo: NetCallRequestInfo) async throws {
        _ = try await requestData(requestInfo: requestInfo)
    }
    
    /// Executes an HTTP request and returns the raw response data.
    public func requestData(requestInfo: NetCallRequestInfo) async throws -> Data {
        var retryCount = 0
        var hasWaitedForUnauthorizedRefresh = false
        
        while true {
            do {
                let (data, response) = try await executeNetworkRequest(requestInfo: requestInfo)
                let outcome = try await handleResponse(
                    data: data,
                    response: response,
                    requestInfo: requestInfo,
                    retryCount: &retryCount,
                    hasWaitedForUnauthorizedRefresh: &hasWaitedForUnauthorizedRefresh
                )
                
                if case .success(let payload) = outcome {
                    if requestInfo.callParam.printCall {
                        logInfo("Request success",
                                metadata: ["request info": requestInfo.description],
                                category: LogCategory.data.rawValue)
                    }
                    return payload
                } else {
                    logInfo("Retry request",
                            metadata: ["urlTarget": requestInfo.urlTarget.description,
                                       "retry count": "\(retryCount)"],
                            category: LogCategory.data.rawValue)
                }
            } catch {
                logError("Failed to request data",
                         metadata: ["error": error.localizedDescription],
                         category: LogCategory.data.rawValue)
                try await handleRequestFailure(error,
                                               retryCount: &retryCount,
                                               callParam: requestInfo.callParam)
            }
        }
    }
    
    public func fetchImage(from urlString: String, useDisk: Bool) async -> UIImage? {
        if let cached = await imageCacheManager.get(forKey: urlString,
                                                    useDisk: useDisk) {
            return cached
        }
        
        do {
            let data = try await requestData(
                requestInfo: .get(url: .fullURL(urlString),
                                  queryItems: [],
                                  headerParam: NetCallRequestInfo.HeaderParam(headers: sharedImageHeaders,
                                                                              useSharedHeaders: false),
                                  callParam: NetCallRequestInfo.CallParam(timeoutInterval: 10,
                                                                          retryPolicy: NetCallRequestInfo.CallParam.RetryPolicy.default))
            )
            
            guard let fetchedImage = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            await imageCacheManager.save(fetchedImage,
                                         for: urlString,
                                         saveToDisk: useDisk)
            return fetchedImage
        } catch let error {
            logError("Failed to fetch image",
                     metadata: ["error": error.localizedDescription],
                     category: LogCategory.image.rawValue)
            return nil
        }
    }
}
