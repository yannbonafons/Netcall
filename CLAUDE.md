# Netcall

Lightweight Swift networking library wrapping `URLSession`.

## Project structure

```
Sources/Netcall/
  NetCallClient.swift      # Actor-based HTTP client (singleton via .shared)
  NetCallRequestInfo.swift  # Enum modeling GET/POST requests
  NetCallError.swift        # Error types for HTTP responses
Tests/NetcallTests/         # Swift Testing framework
Example/NetcallApp/         # Demo app (Xcode project via project.yml)
```

## Stack

- Swift 6, strict concurrency (`actor`, `Sendable`)
- SPM (swift-tools-version: 6.0)
- Minimum deployment: iOS 17
- Testing framework: Swift Testing (`import Testing`)

## Architecture

- `NetCallClient` is an **actor** (thread-safe by design), accessed via `NetCallClient.shared`
- `NetCallClientProtocol` defines the public contract
- `NetCallRequestInfo` is an enum (`get` / `post`) carrying URL, query items, and optional body
- `NetCallError` maps HTTP status codes to typed errors

## Conventions

- MARK: comments to organize file sections
- Doc comments (`///`) on public API
- No force unwraps — use `guard let` / `throw`
- async/await only, no Combine or completion handlers
- camelCase variables, PascalCase types
