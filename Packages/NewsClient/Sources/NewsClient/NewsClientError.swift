import Foundation

/// Errors a ``NewsService`` can throw besides transport errors such as `URLError`.
public enum NewsClientError: Error, Equatable {
    /// The cursor was not one this service handed out.
    case invalidCursor
    /// The server answered with a failing status. `retryAfter` is the wait it asked for, if any.
    case http(status: Int, retryAfter: TimeInterval?)
    /// The response could not be decoded.
    case decoding
}
