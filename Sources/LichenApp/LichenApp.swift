import SwiftUI
import LichenCore

/// Lichen 应用入口。
///
/// 注意：`LichenApp` 当前是 SwiftPM library target。若要在 Xcode 中作为 App 运行，
/// 需要把 Package.swift 中的该 target 改为 `.executableTarget` 并补一个 `.executable`
/// product；若只用于 Preview，则去掉下面的 `@main` 并保留 `struct ... : App`。
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
