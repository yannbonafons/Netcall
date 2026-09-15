//
//  NetCallClientProtocol.swift
//  Netcall
//
//  Created by Yann Bonafons on 05/04/2026.
//

import UIKit

public protocol NetCallClientProtocol {
    /// Fetch
    func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo, decoder: JSONDecoder) async throws -> T

    /// Raw data
    func requestData(requestInfo: NetCallRequestInfo) async throws -> Data

    /// Fire-and-forget (204, etc.)
    func request(requestInfo: NetCallRequestInfo) async throws

    /// Request lifecycle
    func cancelAll() async
}

extension NetCallClientProtocol {
    /// Convenience: uses a default `JSONDecoder`.
    public func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T {
        try await fetchRemoteData(requestInfo: requestInfo, decoder: JSONDecoder())
    }
}

public protocol NetCallConfigurationProtocol {
    /// Confugure  all headers
    func updateSharedHeaders(_ headers: [String: String]) async
    
    /// Set a specific header
    func setSharedHeader(name: String, value: String?) async
    
    /// Set a specific header for image fetching
    func setImageSharedHeader(name: String, value: String?) async
    
    /// Set base URL (domain use on all NetCallClientProtocol requests)
    func updateBaseURL(_ baseURL: String?) async
    
    /// Set a refresh hook that will be called on a 401 error. This is the opportunity to refresh an auth token
    func setUnauthorizedRefreshHook(_ hook: NetCallUnauthorizedRefreshHook?) async
}

public protocol NetCallImageClientProtocol {
    /// Fetch an image. The fetched image will be store in cache (and optionnaly on the disk)
    func fetchImage(from urlString: String, useDisk: Bool) async -> UIImage?
}
