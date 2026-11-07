import SwiftUI

/// 应用根视图，承载三个一级入口。
struct RootView: View {
    var body: some View {
        TabView {
            SessionsView()
                .tabItem { Label("会话", systemImage: "terminal") }

            GatewayView()
                .tabItem { Label("网关", systemImage: "network") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        // TODO: 后续任务加入全局状态路由（例如未连接时引导到网关页）。
    }
}
