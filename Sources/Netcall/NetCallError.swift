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
        case .customError(message: let message, _):
            return message
        }
    }
}
