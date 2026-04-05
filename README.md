# Netcall

Lightweight Swift networking library wrapping `URLSession`. Actor-based, fully `Sendable`, async/await only.

## Features

- **Actor-isolated client** — thread-safe by design (`NetCallClient` is an `actor`)
- **HTTP methods** — GET, POST, PUT, PATCH, DELETE
- **Base URL + path components** or full URLs
- **Shared headers** — set once, applied to every request (overridable per-request)
- **Retry policy** — configurable max retries, delay, exponential backoff
- **401 handling** — automatic token refresh via `unauthorizedRefreshHook`, with request coalescing
- **Request cancellation** — `cancelAll()` to cancel in-flight requests
- **Typed errors** — `NetCallError` maps HTTP status codes, network errors, and decoding failures

## Requirements

- iOS 17+
- Swift 6.0
- Xcode 26+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/yannbonafons/Netcall", from: "1.0.0")
]
```

## Quick Start

```swift
import Netcall

// Configure the shared client
let client = NetCallClient.shared
await client.updateBaseURL("https://api.example.com")
await client.updateSharedHeaders(["Authorization": "Bearer token"])

// GET request
let users: [User] = try await client.fetchRemoteData(
    requestInfo: .get(url: .pathComponent("/users"))
)

// POST request with JSON body
let newUser: User = try await client.fetchRemoteData(
    requestInfo: .post(
        url: .pathComponent("/users"),
        body: try .json(CreateUserRequest(name: "John"))
    )
)

// With retry policy
let data: MyResponse = try await client.fetchRemoteData(
    requestInfo: .get(
        url: .fullURL("https://other-api.com/data"),
        callParam: .init(retryPolicy: .init(maxRetry: 3))
    )
)

// 401 auto-refresh
await client.setUnauthorizedRefreshHook {
    // Refresh your token here
    let newToken = try await refreshToken()
    await client.setSharedHeader(name: "Authorization", value: "Bearer \(newToken)")
}
```

## Example App: NetcallApp

Launch the Example app located in the `Example/` folder for a working demo.

## License

MIT — see [LICENSE](LICENSE).
