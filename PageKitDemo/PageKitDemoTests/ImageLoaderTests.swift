import Foundation
import Testing
import UIKit
@testable import PageKitDemo

struct ImageLoaderTests {
    /// Counts fetches and can hand back anything, so no test touches the network.
    private actor Server {
        private(set) var fetches = 0
        private var result: Result<Data, Error>

        init(_ result: Result<Data, Error>) { self.result = result }

        func fetch() throws -> Data {
            fetches += 1
            return try result.get()
        }
    }

    private let url = URL(string: "https://example.com/picture.png")!

    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makeLoader(_ server: Server) -> ImageLoader {
        ImageLoader(fetch: { _ in try await server.fetch() })
    }

    private func pixels(_ image: UIImage) -> CGSize {
        CGSize(width: image.cgImage?.width ?? 0, height: image.cgImage?.height ?? 0)
    }

    @Test func downsamplesSoTheShortEdgeStillFillsTheTarget() async throws {
        let loader = makeLoader(Server(.success(png(width: 400, height: 200))))

        let image = try await loader.image(for: url, filling: CGSize(width: 100, height: 100))

        #expect(pixels(image) == CGSize(width: 200, height: 100))
    }

    @Test func neverEnlargesASmallImage() async throws {
        let loader = makeLoader(Server(.success(png(width: 40, height: 20))))

        let image = try await loader.image(for: url, filling: CGSize(width: 100, height: 100))

        #expect(pixels(image) == CGSize(width: 40, height: 20))
    }

    @Test func theSameURLAndSizeComeFromTheCache() async throws {
        let server = Server(.success(png(width: 400, height: 200)))
        let loader = makeLoader(server)
        let size = CGSize(width: 100, height: 100)

        let first = try await loader.image(for: url, filling: size)
        let second = try await loader.image(for: url, filling: size)

        #expect(first === second)
        #expect(await server.fetches == 1)
    }

    @Test func anotherSizeIsAnotherCacheEntry() async throws {
        let server = Server(.success(png(width: 400, height: 200)))
        let loader = makeLoader(server)

        _ = try await loader.image(for: url, filling: CGSize(width: 100, height: 100))
        _ = try await loader.image(for: url, filling: CGSize(width: 50, height: 50))

        #expect(await server.fetches == 2)
    }

    @Test func aFailedFetchThrowsAndIsNotCached() async throws {
        let server = Server(.failure(URLError(.badServerResponse)))
        let loader = makeLoader(server)
        let size = CGSize(width: 100, height: 100)

        await #expect(throws: URLError.self) { try await loader.image(for: url, filling: size) }
        await #expect(throws: URLError.self) { try await loader.image(for: url, filling: size) }

        #expect(await server.fetches == 2)
    }

    @Test func dataThatIsNotAnImageThrows() async {
        let loader = makeLoader(Server(.success(Data("not an image".utf8))))

        await #expect(throws: URLError.self) {
            try await loader.image(for: url, filling: CGSize(width: 100, height: 100))
        }
    }

    @Test func cancellingStopsTheFetch() async {
        let loader = ImageLoader(fetch: { _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return Data()
        })
        let size = CGSize(width: 100, height: 100)
        let url = url
        let task = Task { try await loader.image(for: url, filling: size) }

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func workCancelledAfterTheFetchIsNotCached() async throws {
        let server = Server(.success(png(width: 400, height: 200)))
        let loader = ImageLoader(fetch: { _ in
            let data = try await server.fetch()
            if await server.fetches == 1 {
                withUnsafeCurrentTask { $0?.cancel() }   // cancelled just as the bytes arrive
            }
            return data
        })
        let size = CGSize(width: 100, height: 100)
        let url = url

        await #expect(throws: CancellationError.self) {
            try await Task { try await loader.image(for: url, filling: size) }.value
        }
        _ = try await loader.image(for: url, filling: size)

        #expect(await server.fetches == 2)
    }
}
