import SwiftUI
import LichenApp
import LichenCore

@main struct MyApp: App {
    
    @State private var appState = AppState(sessionStore: PersistentSessionStore())
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
