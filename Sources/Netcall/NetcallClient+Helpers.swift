//
//  RequestDataOutcome.swift
//  Netcall
//
//  Created by Yann Bonafons on 11/05/2026.
//

import Foundation

// MARK: - Internal functions
extension NetCallClient {
    enum RequestDataOutcome {
        case success(Data)
        case retry
    }

    func handleResponse(
        data: Data,
        response: HTTPURLResponse,
        requestInfo: NetCallRequestInfo,
        retryCount: inout Int,
        hasWaitedForUnauthorizedRefresh: inout Bool
    ) async throws -> RequestDataOutcome {
        switch response.statusCode {
        case 200..<300:
            return .success(data)
        case 401:
            if !requestInfo.callParam.isRefreshCall && !hasWaitedForUnauthorizedRefresh {
                hasWaitedForUnauthorizedRefresh = true
                try await synchronizeUnauthorizedRefresh()
                return .retry
            }

            try await retryOrThrow(.unauthorized, retryCount: &retryCount, callParam: requestInfo.callParam)
            return .retry
        case 400..<500:
            try await retryOrThrow(
                .clientError(code: response.statusCode),
                retryCount: &retryCount,
                callParam: requestInfo.callParam
            )
            return .retry
        case 500..<600:
            try await retryOrThrow(
                .serverError(code: response.statusCode),
                retryCount: &retryCount,
                callParam: requestInfo.callParam
            )
            return .retry
        default:
            try await retryOrThrow(
                .customError(message: "Unknown status code: \(response.statusCode). Body: \(bodyDescription(from: data))"),
                retryCount: &retryCount,
                callParam: requestInfo.callParam
            )
            return .retry
        }
    }

    func handleRequestFailure(
        _ error: Error,
        retryCount: inout Int,
        callParam: NetCallRequestInfo.CallParam
    ) async throws {
        let mappedError = mapTransportError(error)
        try await retryOrThrow(mappedError, retryCount: &retryCount, callParam: callParam)
    }

    func retryOrThrow(
        _ error: NetCallError,
        retryCount: inout Int,
        callParam: NetCallRequestInfo.CallParam
    ) async throws {
        guard shouldRetry(error: error, retryCount: retryCount, callParam: callParam) else {
            throw error
        }

        try await waitBeforeRetry(retryCount: retryCount, callParam: callParam)
        retryCount += 1
    }

    func executeNetworkRequest(requestInfo: NetCallRequestInfo) async throws -> (Data, HTTPURLResponse) {
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

    func synchronizeUnauthorizedRefresh() async throws {
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

    func shouldRetry(error: NetCallError,
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
            return retryPolicy.retryOnUnauthorized && !callParam.isRefreshCall
        default:
            return false
        }
    }

    func waitBeforeRetry(retryCount: Int, callParam: NetCallRequestInfo.CallParam) async throws {
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
    func getUrlRequest(requestInfo: NetCallRequestInfo) throws -> URLRequest {
        let endPointUrl = try resolveURL(from: requestInfo.urlTarget)

        var urlComponents = URLComponents(url: endPointUrl, resolvingAgainstBaseURL: false)
        if !requestInfo.queryItems.isEmpty {
            urlComponents?.queryItems = requestInfo.queryItems
        }

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

    func makeHeaders(for requestInfo: NetCallRequestInfo) -> [String: String] {
        if requestInfo.headerParam.useSharedHeaders {
            return sharedHeaders.merging(requestInfo.headerParam.headers) { _, requestValue in requestValue }
        }

        return requestInfo.headerParam.headers
    }

    func resolveURL(from urlTarget: NetCallRequestInfo.URLTarget) throws -> URL {
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

    func mapTransportError(_ error: Error) -> NetCallError {
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

    func mapDecodingError(_ error: Error) -> NetCallError {
        if let decodingError = error as? DecodingError {
            return .decodingError(message: String(describing: decodingError))
        }

        return .customError(message: "Decoding failed", error: error)
    }

    func bodyDescription(from data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        return String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
    }
}
