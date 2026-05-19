import Foundation
import PrintUI
import Testing
import UIKit
@testable import Netcall

// swiftlint:disable force_unwrapping type_body_length file_length

// MARK: - Mock URLProtocol

nonisolated
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Models

nonisolated
private struct TestModel: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

nonisolated
private struct SnakeCaseModel: Codable, Sendable, Equatable {
    let firstName: String
    let lastName: String
}

private final class CapturingLogProvider: LogProvider, @unchecked Sendable {
    let enabledLevels = Set(LogLevel.allCases)

    private let lock = NSLock()
    private var capturedEvents: [LogEvent] = []

    var events: [LogEvent] {
        lock.withLock { capturedEvents }
    }

    func log(_ event: LogEvent) {
        lock.withLock {
            capturedEvents.append(event)
        }
    }
}

// MARK: - Helpers

private func makeClient(baseURL: String? = nil, sharedHeaders: [String: String] = [:]) -> NetCallClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return NetCallClient(
        session: session,
        sharedHeaders: sharedHeaders,
        baseURL: baseURL.flatMap { URL(string: $0) }
    )
}

private func mockResponse(
    url: String = "https://api.test.com/test",
    statusCode: Int = 200,
    data: Data = Data()
) -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
    return (data, response)
}

private func encode<T: Encodable>(_ value: T) throws -> Data {
    try JSONEncoder().encode(value)
}

private func makeImageData() throws -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    let image = renderer.image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    return try #require(image.pngData())
}

private func diskCacheURL(for imageURLString: String) -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(String(imageURLString.hashValue))
}

private func removeDiskCache(for imageURLString: String) {
    try? FileManager.default.removeItem(at: diskCacheURL(for: imageURLString))
}

private func waitForDiskCache(for imageURLString: String) async throws {
    let cacheURL = diskCacheURL(for: imageURLString)
    for _ in 0..<20 where !FileManager.default.fileExists(atPath: cacheURL.path) {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(FileManager.default.fileExists(atPath: cacheURL.path))
}

// MARK: - All Tests (serialized to avoid MockURLProtocol.handler conflicts)

@Suite(.serialized)
enum NetcallTests {

    // MARK: - Request Construction Tests

    @Suite("Request Construction")
    struct RequestConstructionTests {

        @Test("GET request uses correct URL and method")
        func getRequest() async throws {
            let client = makeClient()
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .fullURL("https://api.test.com/users"))
            )

            #expect(capturedRequest?.httpMethod == "GET")
            #expect(capturedRequest?.url?.absoluteString == "https://api.test.com/users")
        }

        @Test("POST request includes JSON body and Content-Type")
        func postRequestWithJSONBody() async throws {
            let client = makeClient()
            var capturedRequest: URLRequest?

            let body = TestModel(id: 1, name: "new")
            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(body))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .post(
                    url: .fullURL("https://api.test.com/users"),
                    body: try .json(body)
                )
            )

            #expect(capturedRequest?.httpMethod == "POST")
            #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
            // Note: httpBody is nil in URLProtocol — body is consumed via stream
        }

        @Test("Query items are included in URL")
        func queryItems() async throws {
            let client = makeClient()
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/search"),
                    queryItems: [URLQueryItem(name: "q", value: "swift")]
                )
            )

            let urlString = capturedRequest?.url?.absoluteString ?? ""
            #expect(urlString.contains("q=swift"))
        }

        @Test("Shared headers are merged with per-request headers")
        func customHeaders() async throws {
            let client = makeClient(sharedHeaders: ["Authorization": "Bearer token"])
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/data"),
                    headerParam: .init(headers: ["X-Custom": "value"])
                )
            )

            #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(capturedRequest?.value(forHTTPHeaderField: "X-Custom") == "value")
        }

        @Test("Per-request header overrides shared header")
        func headerOverride() async throws {
            let client = makeClient(sharedHeaders: ["Authorization": "Bearer old"])
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/data"),
                    headerParam: .init(headers: ["Authorization": "Bearer new"])
                )
            )

            #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer new")
        }

        @Test("Base URL resolves path component")
        func baseURLWithPathComponent() async throws {
            let client = makeClient(baseURL: "https://api.test.com")
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .pathComponent("users"))
            )

            #expect(capturedRequest?.url?.absoluteString == "https://api.test.com/users")
        }

        @Test("Full URL ignores base URL")
        func fullURLIgnoresBase() async throws {
            let client = makeClient(baseURL: "https://api.test.com")
            var capturedRequest: URLRequest?

            MockURLProtocol.handler = { request in
                capturedRequest = request
                return mockResponse(data: try encode(TestModel(id: 1, name: "test")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .fullURL("https://other.api.com/data"))
            )

            #expect(capturedRequest?.url?.absoluteString == "https://other.api.com/data")
        }
    }

    // MARK: - Response Handling Tests

    @Suite("Response Handling")
    struct ResponseHandlingTests {

        @Test("200 returns decoded JSON")
        func http200ReturnsDecodedData() async throws {
            let client = makeClient()
            let expected = TestModel(id: 42, name: "hello")

            MockURLProtocol.handler = { _ in
                mockResponse(data: try encode(expected))
            }

            let result: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .fullURL("https://api.test.com/test"))
            )

            #expect(result == expected)
        }

        @Test("4xx throws clientError")
        func http4xxThrowsClientError() async throws {
            let client = makeClient()

            MockURLProtocol.handler = { _ in
                mockResponse(statusCode: 403)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(url: .fullURL("https://api.test.com/test"))
                )
                Issue.record("Expected NetCallError")
            } catch let error as NetCallError {
                guard case .clientError(code: 403) = error else {
                    Issue.record("Expected clientError(403), got \(error)")
                    return
                }
            }
        }

        @Test("5xx throws serverError")
        func http5xxThrowsServerError() async throws {
            let client = makeClient()

            MockURLProtocol.handler = { _ in
                mockResponse(statusCode: 500)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(url: .fullURL("https://api.test.com/test"))
                )
                Issue.record("Expected NetCallError")
            } catch let error as NetCallError {
                guard case .serverError(code: 500) = error else {
                    Issue.record("Expected serverError(500), got \(error)")
                    return
                }
            }
        }

        @Test("requestData returns raw Data")
        func requestDataReturnsRawData() async throws {
            let client = makeClient()
            let rawData = Data("raw content".utf8)

            MockURLProtocol.handler = { _ in
                mockResponse(data: rawData)
            }

            let result = try await client.requestData(
                requestInfo: .get(url: .fullURL("https://api.test.com/file"))
            )

            #expect(result == rawData)
        }

        @Test("request (void) does not throw on 204")
        func requestVoidDoesNotThrowOn204() async throws {
            let client = makeClient()

            MockURLProtocol.handler = { _ in
                mockResponse(statusCode: 204)
            }

            try await client.request(
                requestInfo: .delete(url: .fullURL("https://api.test.com/item/1"))
            )
        }

        @Test("Custom JSONDecoder with snake_case strategy")
        func customDecoder() async throws {
            let client = makeClient()
            let json = #"{"first_name":"John","last_name":"Doe"}"#

            MockURLProtocol.handler = { _ in
                mockResponse(data: Data(json.utf8))
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let result: SnakeCaseModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .fullURL("https://api.test.com/user")),
                decoder: decoder
            )

            #expect(result == SnakeCaseModel(firstName: "John", lastName: "Doe"))
        }
    }

    // MARK: - 401 / Auth Tests

    @Suite("Unauthorized Handling")
    struct UnauthorizedHandlingTests {

        @Test("401 without hook throws unauthorized")
        func http401ThrowsUnauthorized() async throws {
            let client = makeClient()

            MockURLProtocol.handler = { _ in
                mockResponse(statusCode: 401)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(url: .fullURL("https://api.test.com/secure"))
                )
                Issue.record("Expected NetCallError.unauthorized")
            } catch let error as NetCallError {
                guard case .unauthorized = error else {
                    Issue.record("Expected unauthorized, got \(error)")
                    return
                }
            }
        }

        @Test("401 triggers refresh hook then retries successfully")
        func http401TriggersRefreshHook() async throws {
            let client = makeClient()
            var requestCount = 0
            let expected = TestModel(id: 1, name: "refreshed")

            MockURLProtocol.handler = { _ in
                requestCount += 1
                if requestCount == 1 {
                    return mockResponse(statusCode: 401)
                }
                return mockResponse(data: try encode(expected))
            }

            await client.setUnauthorizedRefreshHook { }

            let result: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(url: .fullURL("https://api.test.com/secure"))
            )

            // If hook wasn't called, request would fail with unauthorized — success proves hook ran
            #expect(result == expected)
            #expect(requestCount == 2)
        }

        @Test("isRefreshCall skips refresh hook")
        func refreshCallSkipsHook() async throws {
            let client = makeClient()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(statusCode: 401)
            }

            await client.setUnauthorizedRefreshHook { }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(
                        url: .fullURL("https://api.test.com/refresh"),
                        callParam: .init(isRefreshCall: true)
                    )
                )
                Issue.record("Expected NetCallError.unauthorized")
            } catch is NetCallError {
                // Expected
            }

            // Only 1 request — hook was skipped, no retry
            #expect(requestCount == 1)
        }

        @Test("isRefreshCall prevents retry on unauthorized even with retryOnUnauthorized")
        func isRefreshCallPreventsRetryOnUnauthorized() async throws {
            let client = makeClient()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(statusCode: 401)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(
                        url: .fullURL("https://api.test.com/refresh"),
                        callParam: .init(
                            retryPolicy: .init(maxRetry: 3, retryDelay: 0, retryOnUnauthorized: true),
                            isRefreshCall: true
                        )
                    )
                )
                Issue.record("Expected NetCallError.unauthorized")
            } catch is NetCallError {
                // Expected
            }

            // Should only be called once — no retries because isRefreshCall blocks it
            #expect(requestCount == 1)
        }
    }

    // MARK: - Retry Tests

    @Suite("Retry Policy")
    struct RetryPolicyTests {

        @Test("Retries on server error up to maxRetry")
        func retryPolicyRetriesOnServerError() async throws {
            let client = makeClient()
            var requestCount = 0
            let expected = TestModel(id: 1, name: "recovered")

            MockURLProtocol.handler = { _ in
                requestCount += 1
                if requestCount <= 2 {
                    return mockResponse(statusCode: 500)
                }
                return mockResponse(data: try encode(expected))
            }

            let result: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/flaky"),
                    callParam: .init(retryPolicy: .init(maxRetry: 3, retryDelay: 0))
                )
            )

            #expect(result == expected)
            #expect(requestCount == 3)
        }

        @Test("Does not retry on client error (4xx non-401)")
        func retryPolicyDoesNotRetryOnClientError() async throws {
            let client = makeClient()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(statusCode: 403)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(
                        url: .fullURL("https://api.test.com/forbidden"),
                        callParam: .init(retryPolicy: .init(maxRetry: 3, retryDelay: 0))
                    )
                )
                Issue.record("Expected NetCallError")
            } catch is NetCallError {
                // Expected
            }

            #expect(requestCount == 1)
        }

        @Test("Stops retrying after maxRetry reached")
        func retryExhausted() async throws {
            let client = makeClient()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(statusCode: 500)
            }

            do {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(
                        url: .fullURL("https://api.test.com/down"),
                        callParam: .init(retryPolicy: .init(maxRetry: 2, retryDelay: 0))
                    )
                )
                Issue.record("Expected NetCallError")
            } catch is NetCallError {
                // Expected
            }

            // 1 initial + 2 retries = 3
            #expect(requestCount == 3)
        }
    }

    // MARK: - Logging Tests

    @Suite("Logging")
    struct LoggingTests {

        @Test("printCall logs successful requests until logging is disabled")
        func printCallLoggingCanBeDisabled() async throws {
            let client = makeClient()
            let provider = CapturingLogProvider()
            LoggerManager.instance.setProviders(providers: [provider])

            MockURLProtocol.handler = { _ in
                mockResponse(data: try encode(TestModel(id: 1, name: "logged")))
            }

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/logged"),
                    callParam: .init(printCall: true)
                )
            )

            #expect(provider.events.contains { event in
                event.level == .info &&
                    event.message == "Request success" &&
                    event.category.identifier == LogCategory.data.rawValue
            })

            let eventCountBeforeDisable = provider.events.count
            NetCallClient.disableLogging()

            let _: TestModel = try await client.fetchRemoteData(
                requestInfo: .get(
                    url: .fullURL("https://api.test.com/not-logged"),
                    callParam: .init(printCall: true)
                )
            )

            #expect(provider.events.count == eventCountBeforeDisable)
        }
    }

    // MARK: - Image Tests

    @Suite("Images")
    struct ImageTests {

        @Test("fetchImage returns cached image from memory without a second request")
        func fetchImageUsesMemoryCache() async throws {
            let client = makeClient()
            let imageData = try makeImageData()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(url: "https://api.test.com/image.png", data: imageData)
            }

            let firstImage = await client.fetchImage(from: "https://api.test.com/image.png", useDisk: false)
            let secondImage = await client.fetchImage(from: "https://api.test.com/image.png", useDisk: false)

            #expect(firstImage != nil)
            #expect(secondImage != nil)
            #expect(requestCount == 1)
        }

        @Test("fetchImage saves to disk and a new cache manager reads it without network")
        func fetchImageUsesDiskCache() async throws {
            let imageURLString = "https://api.test.com/disk-image.png"
            removeDiskCache(for: imageURLString)
            defer { removeDiskCache(for: imageURLString) }

            let client = makeClient()
            let imageData = try makeImageData()
            var requestCount = 0

            MockURLProtocol.handler = { _ in
                requestCount += 1
                return mockResponse(url: imageURLString, data: imageData)
            }

            let fetchedImage = await client.fetchImage(from: imageURLString, useDisk: true)
            try await waitForDiskCache(for: imageURLString)

            #expect(fetchedImage != nil)
            #expect(requestCount == 1)

            let diskBackedCache = ImageCacheManager(countLimit: 0)
            let cachedImage = diskBackedCache.get(forKey: imageURLString, useDisk: true)
            #expect(cachedImage != nil)
        }
    }

    // MARK: - Cancel Tests

    @Suite("Cancellation")
    struct CancellationTests {

        @Test("cancelAll cancels in-flight requests")
        func cancelAllTest() async throws {
            let client = makeClient()

            MockURLProtocol.handler = { _ in
                Thread.sleep(forTimeInterval: 5)
                return mockResponse()
            }

            let task = Task {
                let _: TestModel = try await client.fetchRemoteData(
                    requestInfo: .get(url: .fullURL("https://api.test.com/slow"))
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            await client.cancelAll()

            do {
                try await task.value
                Issue.record("Expected cancellation error")
            } catch is NetCallError {
                // Expected: .cancelled
            }
        }
    }
}

// swiftlint:enable force_unwrapping type_body_length file_length
