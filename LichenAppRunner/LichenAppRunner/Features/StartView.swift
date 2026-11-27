import Foundation
import LichenCore
import SwiftUI

/// 开始页：完全对齐目标 App 界面，支持历史抽屉、二级思考强度菜单、新建窗口及网关管理。
struct StartView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingHistory = false
    @State private var inputText = ""

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        ZStack {
            // 背景渐变
            RadialGradient(
                colors: [palette.accentSoft.opacity(0.75), palette.bg],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            FloatingConversationBars { insets in
                GeometryReader { proxy in
                    ScrollView {
                        centerContent(palette: palette)
                            .padding(.horizontal, DesignTokens.spacing5)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(0, proxy.size.height - insets.top - insets.bottom))
                    }
                    .contentMargins(.top, insets.top, for: .scrollContent)
                    .contentMargins(.bottom, insets.bottom, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize)
                }
            } top: {
                topNavBar(palette: palette)
                    .padding(.horizontal, DesignTokens.spacing4)
                    .padding(.top, DesignTokens.spacing2)
            } bottom: {
                bottomInputBar(palette: palette)
                    .padding(.horizontal, DesignTokens.spacing4)
                    .padding(.bottom, DesignTokens.spacing6)
            }
        }
    }

    // MARK: - 1. 顶部导航栏
    private func topNavBar(palette: ColorPalette) -> some View {
        HStack(spacing: 12) {
            // 历史对话按钮 + 模型选择菜单 + 独立的刷新按钮
            HStack(spacing: 8) {
                // 历史对话按钮
                Button {
                    appState.openDrawer()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .frame(width: 36, height: 36)
                        .conversationGlass(in: Circle(), fallback: palette.barGlass, border: palette.line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("历史对话")

                // 模型选择菜单
                Menu {
                    Section("当前网关模型") {
                        ForEach(appState.modelOptions, id: \.self) { model in
                            Button {
                                appState.modelName = model
                            } label: {
                                HStack {
                                    Text(model)
                                    if appState.modelName == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    // 二级子菜单：思考强度
                    Menu {
                        ForEach(LichenEffort.allCases, id: \.self) {
                            effortLevel in
                            Button {
                                appState.effort = effortLevel
                            } label: {
                                HStack {
                                    Text(effortLevel.rawValue)
                                    if appState.effort == effortLevel {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(
                            "思考强度：\(appState.effort.rawValue)",
                            systemImage: "brain"
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.modelName + appState.effort.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.ink3)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .conversationGlass(in: Capsule(), fallback: palette.barGlass, border: palette.line)
                }

                // 网关模型刷新按钮
                Button {
                    Task {
                        await appState.refreshModels()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .frame(width: 36, height: 36)
                        .conversationGlass(in: Circle(), fallback: palette.barGlass, border: palette.line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新模型列表")
            }

            Spacer()

            // 新建窗口 + 网关管理入口
            HStack(spacing: 10) {
                AgentMenu(source: .start, palette: palette)
                Button {
                    Task {
                        await appState.createSession()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .frame(width: 36, height: 36)
                        .conversationGlass(in: Circle(), fallback: palette.barGlass, border: palette.line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建对话窗口")
            }
        }
    }

    // MARK: - 2. 中部内容区
    private func centerContent(palette: ColorPalette) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(palette.accentSoft)
                    .frame(width: 84, height: 84)
                    .blur(radius: 14)

                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(palette.accent)
            }

            Text("Voice just got smarter")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(palette.ink)

            Text("Faster and more intelligent responses")
                .font(DesignTokens.fontBody)
                .foregroundStyle(palette.ink3)

            Button {
                // 语音 Live 交互逻辑
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Try Lichen Live")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
                .shadow(color: palette.shadow, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - 3. 底部胶囊输入栏
    private func bottomInputBar(palette: ColorPalette) -> some View {
        HStack(spacing: 12) {
            Button {
                // 附件或扩展菜单
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            TextField("问问 Lichen", text: $inputText)
                .font(DesignTokens.fontBody)
                .foregroundStyle(palette.ink)
                .onSubmit {
                    submitAndClear()
                }

            Button {
                submitAndClear()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? palette.accentInk : palette.ink4)
                    .frame(width: 36, height: 36)
                    .background(canSend ? palette.accent : palette.surfaceSunken, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送消息")
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .conversationGlass(in: Capsule(), fallback: palette.surface, border: palette.line, shadow: palette.shadow)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitAndClear() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.submitPrompt(text)
    }
}

#Preview("开始页 · 明亮") {
    StartView()
        .environment(AppState.preview())
        .preferredColorScheme(.light)
}

#Preview("开始页 · 黑暗") {
    StartView()
        .environment(AppState.preview())
        .preferredColorScheme(.dark)
}
