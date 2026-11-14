import Foundation
import SwiftUI
import LichenCore

/// 全屏设置：连接状态、连接方式、Agent 品牌参数、外观与会话偏好。
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private let modelOptions = ["Sonnet 4.5", "Opus 4.5", "Haiku 4.5"]

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        VStack(spacing: 0) {
            header(palette: palette)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    connectionSection(palette: palette)
                    methodSection(palette: palette)
                    agentSection(palette: palette)
                    appearanceSection(palette: palette)
                    sessionSection(palette: palette)
                }
                .padding(.horizontal, DesignTokens.spacing5)
                .padding(.bottom, DesignTokens.spacing8)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.bg.ignoresSafeArea())
    }

    // MARK: 头部

    private func header(palette: ColorPalette) -> some View {
        HStack(spacing: DesignTokens.spacing2) {
            Button {
                appState.closeSettings()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(palette.ink2)
                    .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回状态页")

            Text("设置")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)

            Spacer()

            Text(appState.currentAgent?.displayName ?? "未选择 Agent")
                .font(DesignTokens.mono(9))
                .foregroundStyle(palette.ink3)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay {
                    Capsule().stroke(palette.line, lineWidth: 1)
                }
        }
        .padding(.leading, 4)
        .padding(.trailing, DesignTokens.spacing4)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 连接状态

    private func connectionSection(palette: ColorPalette) -> some View {
        section(title: "连接状态", palette: palette) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(appState.isConnected ? palette.accent : palette.ink4)
                        .frame(width: 6, height: 6)

                    Text(appState.connectionState.lichenStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)

                    Spacer()

                    Text(appState.isConnected ? "LIVE" : "OFFLINE")
                        .font(DesignTokens.mono(8))
                        .tracking(0.8)
                        .foregroundStyle(appState.isConnected ? palette.accentStrong : palette.ink4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay {
                            Capsule().stroke(palette.line, lineWidth: 1)
                        }
                }

                Text(appState.connectionState.lichenSummary)
                    .font(DesignTokens.mono(9.5))
                    .foregroundStyle(palette.ink3)

                if let configuration = appState.currentAgent?.configuration {
                    Text("\(configuration.method == .ssl ? "wss / TLS" : "ws") · \(configuration.host)\(configuration.port.map { ":\($0)" } ?? "")")
                        .font(DesignTokens.mono(9))
                        .foregroundStyle(palette.ink4)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()

                    if appState.isConnected {
                        miniButton("断开", tint: palette.danger, palette: palette) {
                            Task { await appState.disconnect() }
                        }
                    } else {
                        miniButton("重新连接", tint: palette.accentStrong, palette: palette) {
                            reconnect()
                        }
                        .disabled(appState.currentAgent == nil)
                        .opacity(appState.currentAgent == nil ? 0.5 : 1)
                    }
                }
            }
            .padding(DesignTokens.spacing3)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
        }
    }

    // MARK: 连接方式

    private func methodSection(palette: ColorPalette) -> some View {
        section(title: "连接方式", palette: palette) {
            HStack(spacing: 2) {
                segmentButton(
                    title: "远程网关",
                    isActive: currentMethod == .gateway,
                    palette: palette
                ) {
                    updateMethod(.gateway)
                }

                segmentButton(
                    title: "SSL",
                    isActive: currentMethod == .ssl,
                    palette: palette
                ) {
                    updateMethod(.ssl)
                }
            }
            .padding(2)
            .background(
                palette.surfaceSunken,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityLabel("连接方式")

            Text(currentMethod == .gateway
                 ? "远程网关：连接电脑端 Agent 暴露的网关地址；SSL 在此基础上启用 wss / TLS 加密。"
                 : "SSL：证书校验与自签名证书选项在连接页的证书区域配置。")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.ink4)
                .lineSpacing(2)
        }
    }

    // MARK: Agent 品牌设置

    private func agentSection(palette: ColorPalette) -> some View {
        section(title: agentSectionTitle, palette: palette) {
            settingRow(title: "默认模型", code: "model", palette: palette) {
                Picker(
                    "默认模型",
                    selection: Binding(
                        get: { appState.modelName },
                        set: { appState.modelName = $0 }
                    )
                ) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(palette.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                settingLabel(title: "推理强度", code: "effort", palette: palette)

                HStack(spacing: 2) {
                    ForEach(LichenEffort.allCases, id: \.rawValue) { effort in
                        segmentButton(
                            title: effort.rawValue,
                            isActive: appState.effort == effort,
                            palette: palette
                        ) {
                            withAnimation(DesignTokens.quick) {
                                appState.effort = effort
                            }
                        }
                    }
                }
                .padding(2)
                .background(
                    palette.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
        }
    }

    // MARK: 外观

    private func appearanceSection(palette: ColorPalette) -> some View {
        section(title: "外观", palette: palette) {
            HStack(spacing: 2) {
                ForEach(LichenTheme.allCases, id: \.rawValue) { theme in
                    segmentButton(
                        title: theme.displayName,
                        isActive: appState.theme == theme,
                        palette: palette
                    ) {
                        withAnimation(DesignTokens.standard) {
                            appState.setTheme(theme)
                        }
                    }
                }
            }
            .padding(2)
            .background(
                palette.surfaceSunken,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityLabel("外观主题")

            Text("明亮为 Lichen daylight；黑暗适合低光环境；跟随系统会随设备外观切换。")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.ink4)
                .lineSpacing(2)
        }
    }

    // MARK: 会话

    private func sessionSection(palette: ColorPalette) -> some View {
        section(title: "会话", palette: palette) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "后台保持会话",
                    subtitle: "离开应用后保持终端连接",
                    isOn: Binding(
                        get: { appState.keepsSessionInBackground },
                        set: { appState.keepsSessionInBackground = $0 }
                    ),
                    palette: palette
                )

                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
                    .padding(.leading, 12)

                toggleRow(
                    title: "自动重连",
                    subtitle: "网络恢复后重建网关连接",
                    isOn: Binding(
                        get: { appState.autoReconnect },
                        set: { appState.autoReconnect = $0 }
                    ),
                    palette: palette
                )
            }
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
        }
    }

    // MARK: 复用件

    private func section<Content: View>(
        title: String,
        palette: ColorPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink2)

            content()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    private func settingRow<Content: View>(
        title: String,
        code: String,
        palette: ColorPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: DesignTokens.spacing3) {
            settingLabel(title: title, code: code, palette: palette)
            Spacer()
            content()
        }
        .frame(minHeight: DesignTokens.tapTarget)
    }

    private func settingLabel(title: String, code: String, palette: ColorPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.ink)
            Text(code)
                .font(DesignTokens.mono(8.5))
                .foregroundStyle(palette.ink4)
        }
    }

    private func segmentButton(
        title: String,
        isActive: Bool,
        palette: ColorPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? palette.ink : palette.ink3)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    isActive ? palette.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(palette.lineStrong, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        palette: ColorPalette
    ) -> some View {
        HStack(spacing: DesignTokens.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.ink4)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(palette.accent)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
    }

    private func miniButton(
        _ title: String,
        tint: Color,
        palette: ColorPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .overlay {
                    Capsule().stroke(palette.lineStrong, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 数据

    private var currentMethod: ConnectionMethod {
        appState.currentAgent?.configuration.method ?? .gateway
    }

    private var agentSectionTitle: String {
        guard let brand = appState.currentAgent?.brand else {
            return "品牌设置"
        }
        return "\(brand.displayName.uppercased()) 品牌设置"
    }

    private func updateMethod(_ method: ConnectionMethod) {
        guard let currentAgentID = appState.currentAgentID,
              let index = appState.agents.firstIndex(where: { $0.id == currentAgentID }) else {
            return
        }
        withAnimation(DesignTokens.standard) {
            appState.agents[index].configuration.method = method
        }
    }

    private func reconnect() {
        guard let configuration = appState.currentAgent?.configuration else { return }
        Task { await appState.connect(configuration: configuration) }
    }
}

#Preview("设置页 · 明亮") {
    SettingsView()
        .environment(AppState.preview(screen: .settings))
        .preferredColorScheme(.light)
}

#Preview("设置页 · 黑暗") {
    SettingsView()
        .environment(AppState.preview(screen: .settings))
        .preferredColorScheme(.dark)
}
