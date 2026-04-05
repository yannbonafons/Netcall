//
//  NetCallRequestInfo.swift
//
//
//  Created by Yann Bonafons on 07/02/2024.
//

import Foundation

public enum NetCallRequestInfo: Sendable {
    nonisolated public enum URLTarget: Sendable {
        case pathComponent(String)
        case fullURL(String)
    }

    nonisolated public struct HeaderParam: Sendable {
        public let headers: [String: String]
        public let useSharedHeaders: Bool

        public init(headers: [String: String] = [:], useSharedHeaders: Bool = true) {
            self.headers = headers
            self.useSharedHeaders = useSharedHeaders
        }

        public static let `default` = HeaderParam()
    }

    nonisolated public struct CallParam: Sendable {
        nonisolated public struct RetryPolicy: Sendable {
            public let maxRetry: Int
            public let retryDelay: TimeInterval
            public let backoffMultiplier: Double
            public let retryOnUnauthorized: Bool

            public init(maxRetry: Int,
                        retryDelay: TimeInterval = 0.5,
                        backoffMultiplier: Double = 1.5,
                        retryOnUnauthorized: Bool = false) {
                self.maxRetry = max(0, maxRetry)
                self.retryDelay = max(0, retryDelay)
                self.backoffMultiplier = max(1, backoffMultiplier)
                self.retryOnUnauthorized = retryOnUnauthorized
            }
        }

        public let timeoutInterval: TimeInterval?
        public let retryPolicy: RetryPolicy?
        public let isRefreshCall: Bool

        public init(timeoutInterval: TimeInterval? = nil,
                    retryPolicy: RetryPolicy? = nil,
                    isRefreshCall: Bool = false) {
            self.timeoutInterval = timeoutInterval
            self.retryPolicy = retryPolicy
            self.isRefreshCall = isRefreshCall
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
}
