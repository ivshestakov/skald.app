import SwiftUI

@main
struct SkaldApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(SkaldSettings.shared)
        }
    }
}
