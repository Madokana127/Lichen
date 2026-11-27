import Foundation
import SwiftUI

/// 承载开始页和聊天页，并叠加会话抽屉、设置和连接表单。
public struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var connectVisible = false
    @State private var connectProgress: CGFloat = 0
    @State private var isClosingConnect = false

    public init() {}

    public var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        ZStack {
            palette.bgCanvas
                .ignoresSafeArea()

            content
                .offset(x: appState.isDrawerOpen ? 18 : 0)
                .allowsHitTesting(
                    !appState.isDrawerOpen
                        && appState.screen != .settings
                        && !connectVisible
                )

            if appState.isDrawerOpen {
                drawer(palette: palette)
                    .zIndex(2)
            }

            if appState.screen == .settings || (appState.screen == .connect && appState.connectSource == .settings) {
                SettingsView()
                    .background(palette.bg.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }

            if connectVisible {
                GeometryReader { proxy in
                    connectLayer(proxy: proxy, palette: palette)
                }
                .zIndex(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "root")
        .animation(panelAnimation, value: appState.isDrawerOpen)
        .alert("操作未完成", isPresented: Binding(
            get: { appState.operationError != nil },
            set: { if !$0 { appState.operationError = nil } }
        )) {
            Button("好", role: .cancel) { appState.operationError = nil }
        } message: {
            Text(appState.operationError ?? "")
        }
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

    // MARK: 四屏内容

    @ViewBuilder
    private var content: some View {
        if baseScreen == .start { StartView() } else { ChatView() }
    }

    private var baseScreen: AppScreen {
        switch appState.screen {
        case .start, .chat: appState.screen
        case .status, .settings: appState.backgroundScreen
        case .connect:
            switch appState.connectSource {
            case .chat: .chat
            case .settings: appState.backgroundScreen
            case .start, nil: .start
            }
        }
    }

    // MARK: 状态抽屉

    private func drawer(palette: ColorPalette) -> some View {
        ZStack(alignment: .leading) {
            palette.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(panelAnimation) {
                        appState.closeDrawer()
                    }
                }
                .transition(.opacity)

            SessionsView()
                .containerRelativeFrame(.horizontal) { length, _ in
                    length * 0.78
                }
                .frame(maxHeight: .infinity)
                .background(palette.bg)
                .shadow(color: palette.shadow, radius: 16, x: 8, y: 0)
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
                    let radius = revealRadius(center: center, size: maskProxy.size) * connectProgress

                    Circle()
                        .frame(width: radius * 2, height: radius * 2)
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

        if reduceMotion {
            connectVisible = true
            connectProgress = 1
            return
        }

        connectVisible = true
        connectProgress = 0

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !isClosingConnect, appState.screen == .connect else { return }
            withAnimation(DesignTokens.reveal) {
                connectProgress = 1
            }
        }
    }

    private func dismissConnect() {
        guard !isClosingConnect else { return }
        isClosingConnect = true

        if reduceMotion {
            connectProgress = 0
            connectVisible = false
            isClosingConnect = false
            appState.closeConnect()
            return
        }

        withAnimation(DesignTokens.reveal, completionCriteria: .removed) {
            connectProgress = 0
        } completion: {
            connectVisible = false
            isClosingConnect = false
            appState.closeConnect()
        }
    }

    /// 抽屉 / 设置层的转场动画；开启「减弱动态效果」时直接切换。
    private var panelAnimation: Animation? {
        reduceMotion ? nil : DesignTokens.panel
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
