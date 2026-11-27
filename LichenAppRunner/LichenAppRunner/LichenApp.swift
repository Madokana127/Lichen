import SwiftUI
import LichenCore

@main struct LichenApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState(
        sessionStore: PersistentSessionStore(),
        agentStore: AgentStore(),
        credentialStore: KeychainGatewayCredentialStore()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task { await appState.restore() }
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, !appState.keepsSessionInBackground {
                        Task { await appState.disconnect() }
                    }
                }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appState.theme {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
