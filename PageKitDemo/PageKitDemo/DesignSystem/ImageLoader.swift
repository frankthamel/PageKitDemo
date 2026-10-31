import ImageIO
import UIKit

/// The app's image pipeline. It fetches and decodes away from the main actor, and shrinks
/// each picture to the size it is shown at, so scrolling never pays for a full-size decode.
nonisolated final class ImageLoader: Sendable {
    /// The loader the rows share, so a picture is cached across rows and tabs.
    static let shared = ImageLoader()

    private let fetch: @Sendable (URL) async throws -> Data
    /// `NSCache` is thread-safe, though its type does not say so.
    private nonisolated(unsafe) let cache = NSCache<NSString, UIImage>()

    /// Creates a loader.
    /// - Parameter fetch: Gets an image's bytes. Replaced in tests.
    init(fetch: @escaping @Sendable (URL) async throws -> Data = ImageLoader.download) {
        self.fetch = fetch
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    /// The image at `url`, just large enough to fill `pixelSize`. It is never enlarged.
    ///
    /// Cancelling stops the work, so a row that scrolls away stops paying for its image.
    /// `@concurrent` matters: without it this would run on the caller, the main actor.
    @concurrent func image(for url: URL, filling pixelSize: CGSize) async throws -> UIImage {
        let key = "\(url.absoluteString)|\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let data = try await fetch(url)
        try Task.checkCancellation()
        let image = try Self.downsample(data, filling: pixelSize)
        try Task.checkCancellation()
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Decodes straight to the smaller size, without ever holding the full-size bitmap.
    private static func downsample(_ data: Data, filling pixelSize: CGSize) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            throw URLError(.cannotDecodeContentData)
        }
        // ImageIO limits the long edge, but filling a frame depends on the short one.
        let scale = min(1, max(pixelSize.width / width, pixelSize.height / height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,     // decode here, not during a draw
            kCGImageSourceThumbnailMaxPixelSize: Int((max(width, height) * scale).rounded(.up))
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw URLError(.cannotDecodeContentData)
        }
        return UIImage(cgImage: thumbnail)
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
