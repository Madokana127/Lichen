import SwiftUI
import LichenCore

/// Lichen 应用入口。
@main
public struct LichenApp: App {
    @State private var appState = AppState(sessionStore: PersistentSessionStore())

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    /// 主题跟随 `AppState.theme`；`system` 交回系统外观。
    private var preferredColorScheme: ColorScheme? {
        switch appState.theme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
}
