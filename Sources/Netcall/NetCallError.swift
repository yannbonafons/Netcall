//
//  NetCallError.swift
//
//
//  Created by Yann Bonafons on 07/02/2024.
//

import Foundation

/// HTTP error cases
public enum NetCallError: Error {
    case badRequest
    case responseFormat
    case unauthorized
    case clientError(code: Int)
    case serverError(code: Int)
    case cancelled
    case networkError(code: URLError.Code)
    case decodingError(message: String)
    case customError(message: String, error: Error? = nil)

    public var message: String {
        switch self {
        case .badRequest:
            return "Bad request"
        case .responseFormat:
            return "Response format error"
        case .unauthorized:
            return "Unauthorized"
        case .clientError(code: let code):
            return "Client error with code: \(code)"
        case .serverError(code: let code):
            return "Server error with code: \(code)"
        case .cancelled:
            return "Request was cancelled"
        case .networkError(code: let code):
            return "Network error with code: \(code.rawValue)"
        case .decodingError(message: let message):
            return "Decoding error: \(message)"
        case .customError(message: let message, _):
            return message
        }
    }
}
