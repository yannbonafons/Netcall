# Netcall

Lightweight Swift networking library wrapping `URLSession`.

## Project structure

```
Sources/Netcall/
  NetCallClient.swift      # Actor-based HTTP client (singleton via .shared)
  NetCallRequestInfo.swift  # Enum modeling HTTP requests (GET/POST/PUT/PATCH/DELETE)
  NetCallError.swift        # Typed errors for HTTP responses
Tests/NetcallTests/         # Swift Testing framework
Example/NetcallApp/         # Demo app (Xcode project via project.yml)
```

## Stack

- Swift 6, strict concurrency (`actor`, `Sendable`)
- SPM (swift-tools-version: 6.2)
- Minimum deployment: iOS 17
- Testing framework: Swift Testing (`import Testing`)
- Approachable concurrency: YES
- Default actor isolation: MainActor
- Strict concurrency checking: Complete
- SwiftLint via SPM build tool plugin

## Architecture

- `NetCallClient` is an **actor** (thread-safe by design), accessed via `NetCallClient.shared`
- `NetCallClientProtocol` defines the public contract (`fetchRemoteData`, header/baseURL management, `cancelAll`, auth hook)
- `NetCallRequestInfo` — enum with cases: `get`, `post`, `put`, `patch`, `delete`
  - `URLTarget` — `.pathComponent(String)` (resolved against `baseURL`) or `.fullURL(String)`
  - `HeaderParam` — per-request headers + `useSharedHeaders` flag (default: `true`)
  - `CallParam` — optional `timeoutInterval`, `RetryPolicy` (maxRetry, delay, backoff, retryOnUnauthorized), `isRefreshCall`
  - `Body` — `.json(Data)` / `.raw(Data, contentType:)` + convenience `.json(_:encoder:)` for `Encodable`
- `NetCallError` — typed errors: `badRequest`, `responseFormat`, `unauthorized`, `clientError(code:)`, `serverError(code:)`, `cancelled`, `networkError(code:)`, `decodingError(message:)`, `customError(message:error:)`
- **401 handling** — `setUnauthorizedRefreshHook` registers a callback; on 401, concurrent requests coalesce into a single refresh task, then retry
- **Retry** — configurable via `CallParam.RetryPolicy` with exponential backoff; retries on network/server errors (+ optionally on 401)

## Conventions

- MARK: comments to organize file sections
- Doc comments (`///`) on public API
- No force unwraps — use `guard let` / `throw`
- async/await only, no Combine or completion handlers
- camelCase variables, PascalCase types
