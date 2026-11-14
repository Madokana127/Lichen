import Foundation
import SwiftUI
import LichenCore

/// 开始页：品牌问候、已连接 Agent 卡片与底部圆形连接按钮。
struct StartView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var fabAnchor: CGPoint = .zero

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        ZStack {
            RadialGradient(
                colors: [palette.accentSoft.opacity(0.75), palette.bg],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header(palette: palette)
                greeting(palette: palette)
                agentsSection(palette: palette)
                Spacer(minLength: DesignTokens.spacing4)
                connectButton(palette: palette)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .padding(.top, DesignTokens.spacing2)
            .padding(.bottom, DesignTokens.spacing6)
        }
    }

    // MARK: 头部

    private func header(palette: ColorPalette) -> some View {
        HStack(spacing: DesignTokens.spacing3) {
            HStack(spacing: 9) {
                Image(systemName: "leaf")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(palette.ink)
                    .frame(width: 29, height: 29)

                Text("Lichen")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(palette.ink)

                Text("标志占位")
                    .font(DesignTokens.mono(8.5))
                    .foregroundStyle(palette.ink4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .foregroundStyle(palette.lineStrong)
                    }
            }

            Spacer(minLength: DesignTokens.spacing2)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isConnected ? palette.accent : palette.ink4)
                    .frame(width: 5, height: 5)
                Text(appState.connectionState.lichenSummary)
                    .font(DesignTokens.mono(9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(palette.glass, in: Capsule())
            .overlay {
                Capsule().stroke(palette.line, lineWidth: 1)
            }
        }
        .frame(minHeight: 36)
    }

    // MARK: 问候

    private func greeting(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLabel)
                .font(DesignTokens.mono(10))
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
                .padding(.bottom, DesignTokens.spacing3)

            Text("\(timeGreeting)。")
                .font(DesignTokens.fontGreeting)
                .tracking(-0.6)
                .foregroundStyle(palette.ink)

            Text("选择一台电脑上的 Agent，继续上次的会话。")
                .font(DesignTokens.fontBody)
                .foregroundStyle(palette.ink3)
                .padding(.top, DesignTokens.spacing2)
        }
        .padding(.top, 58)
    }

    // MARK: Agent 区块

    private func agentsSection(palette: ColorPalette) -> some View {
        let connected = appState.connectedAgents
        let primary = Array(connected.prefix(3))
        let remaining = Array(connected.dropFirst(3))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("已连接的 Agent")
                    .font(DesignTokens.fontCallout)
                    .foregroundStyle(palette.ink2)
                Spacer()
                Text(String(format: "%02d 台", connected.count))
                    .font(DesignTokens.mono(10))
                    .foregroundStyle(palette.ink4)
            }
            .padding(.top, DesignTokens.spacing3)
            .padding(.bottom, DesignTokens.spacing3)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
            }
            .padding(.bottom, DesignTokens.spacing3)

            if primary.isEmpty {
                emptyAgents(palette: palette)
            } else {
                HStack(spacing: 10) {
                    ForEach(primary) { agent in
                        agentCard(agent, palette: palette)
                    }
                }
            }

            if !remaining.isEmpty {
                Text("更多 Agent")
                    .font(DesignTokens.mono(9))
                    .tracking(0.6)
                    .foregroundStyle(palette.ink4)
                    .padding(.top, DesignTokens.spacing3)
                    .padding(.bottom, DesignTokens.spacing2)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(remaining) { agent in
                            agentRow(agent, palette: palette)
                        }
                    }
                }
                .frame(maxHeight: 132)
                .scrollIndicators(.hidden)
            }
        }
        .padding(.top, 76)
    }

    private func emptyAgents(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有已连接的 Agent")
                .font(DesignTokens.fontCallout)
                .foregroundStyle(palette.ink2)
            Text("使用底部的加号连接远程网关。")
                .font(DesignTokens.fontCaption)
                .foregroundStyle(palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.spacing4)
        .lichenSurface()
    }

    private func agentCard(_ agent: Agent, palette: ColorPalette) -> some View {
        let selected = appState.currentAgentID == agent.id

        return Button {
            appState.selectAgent(agent)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? palette.accentSoft : palette.surfaceSunken)
                    Image(systemName: agent.brand.symbolName)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(selected ? palette.accent : palette.ink2)
                }
                .frame(width: 36, height: 36)

                Spacer(minLength: DesignTokens.spacing2)

                Text(agent.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)

                Text(agent.brand.displayName)
                    .font(DesignTokens.mono(9))
                    .foregroundStyle(palette.ink3)
                    .lineLimit(1)
                    .padding(.top, 2)

                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.isConnected ? palette.accent : palette.ink4)
                        .frame(width: 5, height: 5)
                    Text(agent.isConnected ? "已连接" : "未连接")
                        .font(DesignTokens.mono(8.5))
                        .foregroundStyle(palette.ink3)
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(11)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous)
                    .stroke(selected ? palette.accent : palette.line, lineWidth: selected ? 1.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(palette.accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.accentInk)
                    }
                    .frame(width: 17, height: 17)
                    .padding(9)
                }
            }
            .shadow(color: palette.shadow, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func agentRow(_ agent: Agent, palette: ColorPalette) -> some View {
        Button {
            appState.selectAgent(agent)
        } label: {
            HStack(spacing: DesignTokens.spacing2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.surfaceSunken)
                    Image(systemName: agent.brand.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("\(agent.brand.displayName) · \(agent.isConnected ? "已连接" : "未连接")")
                        .font(DesignTokens.mono(9))
                        .foregroundStyle(palette.ink3)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.ink4)
            }
            .padding(.horizontal, DesignTokens.spacing2)
            .padding(.vertical, 7)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部加号

    private func connectButton(palette: ColorPalette) -> some View {
        VStack(spacing: 10) {
            Button {
                let anchor = ConnectAnchor(
                    x: Double(fabAnchor.x),
                    y: Double(fabAnchor.y)
                )
                appState.openConnect(from: .start, anchor: anchor)
            } label: {
                ZStack {
                    Circle()
                        .fill(palette.accent)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                }
                .frame(width: 58, height: 58)
                .overlay {
                    Circle()
                        .stroke(palette.accentSoft2, lineWidth: 1)
                        .scaleEffect(1.18)
                }
                .shadow(color: palette.shadow, radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .revealAnchor($fabAnchor)
            .accessibilityLabel("添加 Agent，打开连接页")

            Text("连接新的 Agent")
                .font(DesignTokens.fontCaption)
                .foregroundStyle(palette.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.spacing8)
    }

    // MARK: 文案

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE · M月d日"
        return formatter.string(from: Date())
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6:
            return "夜深了"
        case 6..<11:
            return "早上好"
        case 11..<14:
            return "中午好"
        case 14..<18:
            return "下午好"
        default:
            return "晚上好"
        }
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
