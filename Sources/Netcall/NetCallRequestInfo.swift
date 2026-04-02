//
//  NetCallRequestInfo.swift
//  
//
//  Created by Yann Bonafons on 07/02/2024.
//

import Foundation

/// List all the possible http method
public enum NetCallRequestInfo: Sendable {
    /// Use this method as a get and pass url parameters and paginator if needed
    case get(urlString: String,
             params: [URLQueryItem]? = nil)
    /// Use this method as a post and pass body if needed
    case post(urlString: String,
              params: [URLQueryItem]? = nil,
              body: [String: Any]?)
    
    /// Method name
    nonisolated var name: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        }
    }
    
    nonisolated var urlString: String {
        switch self {
        case .get(let url, _), .post(let url, _, _):
            return url
        }
    }
    
    nonisolated var queryItems: [URLQueryItem] {
        switch self {
        case .get(_, let params), .post(_, let params, _):
            return params ?? []
        }
    }
}
