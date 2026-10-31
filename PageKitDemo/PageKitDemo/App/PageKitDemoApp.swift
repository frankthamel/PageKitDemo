import SwiftUI

/// Shows the two feeds as tabs. Both tabs use the same view model and the same views:
/// only the source, and so the kind of token, differs. `AppEnvironment` decides which
/// service feeds them, and the simulator panel opens from the masthead.
@main
struct PageKitDemoApp: App {
    @State private var environment: AppEnvironment
    @State private var simulator: SimulatorViewModel
    @State private var showsSimulator = false

    init() {
        let environment = AppEnvironment()
        _environment = State(initialValue: environment)
        _simulator = State(initialValue: SimulatorViewModel(mock: environment.mock) { await environment.clearCaches() })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let feeds = environment.feeds {
                    TabView {
                        Tab("Articles", systemImage: "newspaper") {
                            FeedScreen(title: "Articles", viewModel: feeds.articles, onOpenSimulator: openSimulator)
                        }
                        Tab("Blogs", systemImage: "text.alignleft") {
                            FeedScreen(title: "Blogs", viewModel: feeds.blogs, onOpenSimulator: openSimulator)
                        }
                    }
                    .id(environment.mode)
                } else {
                    Palette.paper.ignoresSafeArea()   // a blank sheet while the mode switches
                }
            }
            .tint(Palette.signalText)
            .sheet(isPresented: $showsSimulator) {
                SimulatorPanel(environment: environment, model: simulator)
            }
        }
    }

    private func openSimulator() {
        showsSimulator = true
    }
}
