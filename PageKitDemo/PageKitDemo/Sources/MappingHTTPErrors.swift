import NewsClient
import PageKit

/// Runs `work` and turns the news client's HTTP error into PageKit's, so PageKit retries
/// server errors and rate limits but not client errors. Other errors, such as `URLError`,
/// pass through unchanged because PageKit already knows how to classify them.
nonisolated func mappingHTTPErrors<Result>(_ work: () async throws -> Result) async throws -> Result {
    do {
        return try await work()
    } catch let NewsClientError.http(status, retryAfter) {
        throw PageKitHTTPError(status: status, retryAfter: retryAfter)
    }
}
