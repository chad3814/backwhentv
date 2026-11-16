import SwiftUI

@main
struct BackWhenTVApp: App {
    @State private var store = GuideStore()
    @State private var player = PlayerController()
    @State private var usage = UsageReporter()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, player: player, usage: usage)
                .preferredColorScheme(.dark)
        }
    }
}
