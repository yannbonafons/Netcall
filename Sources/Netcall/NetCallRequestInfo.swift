//
//  NetCallRequestInfo.swift
//
//
//  Created by Yann Bonafons on 07/02/2024.
//

import Foundation

public enum NetCallRequestInfo: Sendable, CustomStringConvertible {
    nonisolated public enum URLTarget: Sendable, CustomStringConvertible {
        case pathComponent(String)
        case fullURL(String)
        
        public nonisolated var description: String {
            switch self {
            case .pathComponent(let path):
                "pathComponent(\(path))"
            case .fullURL(let urlString):
                "fullURL(\(urlString))"
            }
        }
    }

    nonisolated public struct HeaderParam: Sendable, CustomStringConvertible {
        public let headers: [String: String]
        public let useSharedHeaders: Bool
        
        public var description: String {
            let headersDescription = headers
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { "\($0.key)=\(redactedHeaderValue(name: $0.key, value: $0.value))" }
                .joined(separator: ", ")

            return "useSharedHeaders=\(useSharedHeaders), values=[\(headersDescription)]"
        }

        public init(headers: [String: String] = [:], useSharedHeaders: Bool = true) {
            self.headers = headers
            self.useSharedHeaders = useSharedHeaders
        }

        public static let `default` = HeaderParam()
    }

    nonisolated public struct CallParam: Sendable, CustomStringConvertible {
        nonisolated public struct RetryPolicy: Sendable, CustomStringConvertible {
            public let maxRetry: Int
            public let retryDelay: TimeInterval
            public let backoffMultiplier: Double
            public let retryOnUnauthorized: Bool
            
            public var description: String {
                "maxRetry=\(maxRetry), retryDelay=\(retryDelay), backoffMultiplier=\(backoffMultiplier), retryOnUnauthorized=\(retryOnUnauthorized)"
            }

            public init(maxRetry: Int,
                        retryDelay: TimeInterval = 0.5,
                        backoffMultiplier: Double = 1.5,
                        retryOnUnauthorized: Bool = false) {
                self.maxRetry = max(0, maxRetry)
                self.retryDelay = max(0, retryDelay)
                self.backoffMultiplier = max(1, backoffMultiplier)
                self.retryOnUnauthorized = retryOnUnauthorized
            }

            public static let `default` = RetryPolicy(maxRetry: 3)
        }

        public let timeoutInterval: TimeInterval?
        public let retryPolicy: RetryPolicy?
        public let isRefreshCall: Bool
        public let printCall: Bool
        
        public var description: String {
            let timeoutDescription = timeoutInterval.map { "\($0)" } ?? "nil"

            return [
                "timeoutInterval=\(timeoutDescription)",
                "retryPolicy=\(retryPolicy?.description ?? "nil")",
                "isRefreshCall=\(isRefreshCall)",
                "printCall=\(printCall)"
            ].joined(separator: ", ")
        }

        public init(timeoutInterval: TimeInterval? = 30,
                    retryPolicy: RetryPolicy? = nil,
                    isRefreshCall: Bool = false,
                    printCall: Bool = false) {
            self.timeoutInterval = timeoutInterval
            self.retryPolicy = retryPolicy
            self.isRefreshCall = isRefreshCall
            self.printCall = printCall
        }

        public static let `default` = CallParam()
    }

    nonisolated public enum Body: Sendable {
        case json(Data)
        case raw(Data, contentType: String?)

        public static func json<T: Encodable>(_ value: T,
                                              encoder: JSONEncoder = JSONEncoder()) throws -> Body {
            .json(try encoder.encode(value))
        }
    }

    case get(url: URLTarget,
             queryItems: [URLQueryItem] = [],
             headerParam: HeaderParam = .default,
             callParam: CallParam = .default)
    case post(url: URLTarget,
              queryItems: [URLQueryItem] = [],
              body: Body,
              headerParam: HeaderParam = .default,
              callParam: CallParam = .default)
    case put(url: URLTarget,
             queryItems: [URLQueryItem] = [],
             body: Body,
             headerParam: HeaderParam = .default,
             callParam: CallParam = .default)
    case patch(url: URLTarget,
               queryItems: [URLQueryItem] = [],
               body: Body,
               headerParam: HeaderParam = .default,
               callParam: CallParam = .default)
    case delete(url: URLTarget,
                queryItems: [URLQueryItem] = [],
                headerParam: HeaderParam = .default,
                callParam: CallParam = .default)

    nonisolated var methodName: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        }
    }

    nonisolated var urlTarget: URLTarget {
        switch self {
        case .get(let url, _, _, _),
             .post(let url, _, _, _, _),
             .put(let url, _, _, _, _),
             .patch(let url, _, _, _, _),
             .delete(let url, _, _, _):
            return url
        }
    }

    nonisolated var queryItems: [URLQueryItem] {
        switch self {
        case .get(_, let queryItems, _, _),
             .post(_, let queryItems, _, _, _),
             .put(_, let queryItems, _, _, _),
             .patch(_, let queryItems, _, _, _),
             .delete(_, let queryItems, _, _):
            return queryItems
        }
    }

    nonisolated var headerParam: HeaderParam {
        switch self {
        case .get(_, _, let headerParam, _),
             .post(_, _, _, let headerParam, _),
             .put(_, _, _, let headerParam, _),
             .patch(_, _, _, let headerParam, _),
             .delete(_, _, let headerParam, _):
            return headerParam
        }
    }

    nonisolated var callParam: CallParam {
        switch self {
        case .get(_, _, _, let callParam),
             .post(_, _, _, _, let callParam),
             .put(_, _, _, _, let callParam),
             .patch(_, _, _, _, let callParam),
             .delete(_, _, _, let callParam):
            return callParam
        }
    }

    nonisolated var body: Body? {
        switch self {
        case .post(_, _, let body, _, _),
             .put(_, _, let body, _, _),
             .patch(_, _, let body, _, _):
            return body
        case .get, .delete:
            return nil
        }
    }
    
    public nonisolated var description: String {
        [
            "method=\(methodName)",
            "url=\(urlTarget.description)",
            "queryItems=\(NetCallRequestInfo.describe(queryItems: queryItems))",
            "headers=\(headerParam.description)",
            "call=\(callParam.description)",
            "body=\(NetCallRequestInfo.describe(body: body))"
        ].joined(separator: ", ")
    }

    private nonisolated static func describe(queryItems: [URLQueryItem]) -> String {
        guard !queryItems.isEmpty else {
            return "[]"
        }

        return "[" + queryItems.map { item in
            if let value = item.value {
                return "\(item.name)=\(value)"
            }

            return item.name
        }.joined(separator: ", ") + "]"
    }

    private nonisolated static func describe(body: Body?) -> String {
        guard let body else {
            return "nil"
        }

        switch body {
        case .json(let data):
            return "json(bytes=\(data.count), preview=\(bodyPreview(from: data)))"
        case .raw(let data, let contentType):
            let contentTypeDescription = contentType ?? "nil"
            return "raw(bytes=\(data.count), contentType=\(contentTypeDescription), preview=\(bodyPreview(from: data)))"
        }
    }

    private nonisolated static func bodyPreview(from data: Data) -> String {
        guard !data.isEmpty else {
            return "empty"
        }

        guard let preview = String(data: data.prefix(1_024), encoding: .utf8) else {
            return "nonUTF8"
        }

        let suffix = data.count > 1_024 ? "..." : ""
        return "\"\(preview)\(suffix)\""
    }

    private nonisolated static func redactedHeaderValue(name: String, value: String) -> String {
        let lowercasedName = name.lowercased()
        let sensitiveHeaderNames = ["authorization", "cookie", "set-cookie", "x-api-key", "api-key"]

        if sensitiveHeaderNames.contains(where: { lowercasedName.contains($0) }) {
            return "<redacted>"
        }

        return value
    }
}
