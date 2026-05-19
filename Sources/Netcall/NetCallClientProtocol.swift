//
//  NetCallClientProtocol.swift
//  Netcall
//
//  Created by Yann Bonafons on 05/04/2026.
//

import Foundation

public protocol NetCallClientProtocol: Sendable {
    /// Fetch
    func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo, decoder: JSONDecoder) async throws -> T

    /// Raw data
    func requestData(requestInfo: NetCallRequestInfo) async throws -> Data

    /// Fire-and-forget (204, etc.)
    func request(requestInfo: NetCallRequestInfo) async throws

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

extension NetCallClientProtocol {
    /// Convenience: uses a default `JSONDecoder`.
    public func fetchRemoteData<T: Codable & Sendable>(requestInfo: NetCallRequestInfo) async throws -> T {
        try await fetchRemoteData(requestInfo: requestInfo, decoder: JSONDecoder())
    }
}
