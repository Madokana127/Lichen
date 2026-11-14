import Foundation
import SwiftUI

/// 应用根视图：四屏路由 + 状态抽屉 / 设置层 / 连接层。
///
/// 连接层使用圆形遮罩从触发点扩散；关闭时先反向收拢，再交给
/// `AppState.closeConnect()` 恢复入口页（对话页入口同时恢复 Agent 浮框）。
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var connectVisible = false
    @State private var connectProgress: CGFloat = 0
    @State private var isClosingConnect = false

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        GeometryReader { proxy in
            ZStack {
                palette.bgCanvas
                    .ignoresSafeArea()

                content
                    .scaleEffect(appState.isDrawerOpen ? 0.985 : 1, anchor: .leading)
                    .offset(x: appState.isDrawerOpen ? 18 : 0)
                    .allowsHitTesting(
                        !appState.isDrawerOpen
                            && appState.screen != .settings
                            && !connectVisible
                    )
                    .animation(DesignTokens.panel, value: appState.isDrawerOpen)

                if appState.isDrawerOpen || appState.screen == .status {
                    drawer(size: proxy.size, palette: palette)
                        .zIndex(2)
                }

                if appState.screen == .settings {
                    SettingsView()
                        .background(palette.bg.ignoresSafeArea())
                        .transition(.move(edge: .trailing))
                        .zIndex(3)
                }

                if connectVisible {
                    connectLayer(proxy: proxy, palette: palette)
                        .zIndex(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "root")
            .animation(DesignTokens.panel, value: appState.screen)
            .animation(DesignTokens.panel, value: appState.isDrawerOpen)
            .onAppear {
                if appState.screen == .connect {
                    presentConnect()
                }
            }
            .onChange(of: appState.screen) { _, newScreen in
                if newScreen == .connect {
                    presentConnect()
                }
            }
        }
    }

    // MARK: 四屏内容

    @ViewBuilder
    private var content: some View {
        switch appState.screen {
        case .start:
            StartView()
        case .chat, .status, .settings:
            ChatView()
        case .connect:
            if appState.connectSource == .chat {
                ChatView()
            } else {
                StartView()
            }
        }
    }

    // MARK: 状态抽屉

    private func drawer(size: CGSize, palette: ColorPalette) -> some View {
        ZStack(alignment: .leading) {
            palette.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DesignTokens.panel) {
                        appState.closeDrawer()
                    }
                }
                .transition(.opacity)

            SessionsView()
                .frame(width: size.width * 0.78)
                .frame(maxHeight: .infinity)
                .background(palette.bg)
                .shadow(color: palette.shadow, radius: 24, x: 12, y: 0)
                .transition(.move(edge: .leading))
        }
    }

    // MARK: 连接层

    private func connectLayer(proxy: GeometryProxy, palette: ColorPalette) -> some View {
        let safeTop = proxy.safeAreaInsets.top

        return GatewayView(onClose: dismissConnect)
            .background(palette.bg)
            .ignoresSafeArea()
            .mask {
                GeometryReader { maskProxy in
                    let center = revealCenter(in: maskProxy.size, safeTop: safeTop)
                    let radius = revealRadius(center: center, size: maskProxy.size)

                    Circle()
                        .frame(width: radius * 2, height: radius * 2)
                        .scaleEffect(max(connectProgress, 0.0001))
                        .position(center)
                }
            }
    }

    private func revealCenter(in size: CGSize, safeTop: CGFloat) -> CGPoint {
        guard let anchor = appState.connectAnchor else {
            return CGPoint(x: size.width / 2, y: size.height * 0.82)
        }
        let raw = CGPoint(x: CGFloat(anchor.x), y: CGFloat(anchor.y) + safeTop)
        return CGPoint(
            x: min(max(raw.x, 0), size.width),
            y: min(max(raw.y, 0), size.height)
        )
    }

    private func revealRadius(center: CGPoint, size: CGSize) -> CGFloat {
        let horizontal = max(center.x, size.width - center.x)
        let vertical = max(center.y, size.height - center.y)
        return max(sqrt(horizontal * horizontal + vertical * vertical), 1)
    }

    private func presentConnect() {
        guard !isClosingConnect else { return }
        connectVisible = true
        connectProgress = 0

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            withAnimation(DesignTokens.reveal) {
                connectProgress = 1
            }
        }
    }

    private func dismissConnect() {
        guard !isClosingConnect else { return }
        isClosingConnect = true

        withAnimation(DesignTokens.reveal) {
            connectProgress = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 580_000_000)
            connectVisible = false
            isClosingConnect = false
            appState.closeConnect()
        }
    }
}

#Preview("根视图 · 开始") {
    RootView()
        .environment(AppState.preview())
}

#Preview("根视图 · 对话") {
    RootView()
        .environment(AppState.preview(screen: .chat))
        .preferredColorScheme(.dark)
}
