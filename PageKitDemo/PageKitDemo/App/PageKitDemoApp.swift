import NewsClientLive
import PageKit
import SwiftUI

/// Shows the two feeds as tabs. Both tabs use the same view model and the same views:
/// only the source, and so the kind of token, differs.
@main
struct PageKitDemoApp: App {
    @State private var articles = FeedViewModel(source: ArticlesIndexSource(service: LiveNewsService()))
    @State private var blogs = FeedViewModel(source: BlogsCursorSource(service: LiveNewsService()))

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Articles", systemImage: "newspaper") {
                    FeedScreen(title: "Articles", viewModel: articles)
                }
                Tab("Blogs", systemImage: "text.alignleft") {
                    FeedScreen(title: "Blogs", viewModel: blogs)
                }
            }
            .tint(Palette.signalText)
        }
    }
}
