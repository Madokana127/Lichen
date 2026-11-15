import Foundation
import SwiftUI
import LichenCore

/// 状态抽屉：搜索、Agent 信息、按项目分组的会话与设置入口。
struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showMore = false

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)
        let groups = appState.groupedSessions

        VStack(spacing: 0) {
            header(palette: palette)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if groups.isEmpty {
                        emptyState(palette: palette)
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title.uppercased())
                                    .font(DesignTokens.mono(9))
                                    .tracking(0.9)
                                    .foregroundStyle(palette.ink4)
                                    .padding(.horizontal, 9)
                                    .padding(.top, 4)

                                ForEach(group.sessions) { session in
                                    sessionRow(session, palette: palette)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.spacing3)
                .padding(.top, DesignTokens.spacing2)
                .padding(.bottom, DesignTokens.spacing5)
            }
            .scrollIndicators(.hidden)

            footer(palette: palette)
        }
        .background(palette.bg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.line)
                .frame(width: 1)
        }
        .alert("重命名 Agent", isPresented: $isRenaming) {
            TextField("显示名称", text: $renameText)
            Button("保存") {
                appState.renameCurrentAgent(to: renameText)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前 Agent 的显示名称会立即更新。")
        }
        .confirmationDialog("更多操作", isPresented: $showMore, titleVisibility: .visible) {
            Button("刷新会话") {
                Task { await appState.refreshSessions() }
            }
            Button("清除搜索") {
                appState.searchText = ""
            }
            Button("断开连接", role: .destructive) {
                Task { await appState.disconnect() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 头部

    private func header(palette: ColorPalette) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: DesignTokens.spacing2) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.ink4)

                    TextField("搜索会话…", text: searchBinding)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.ink)
                        .tint(palette.accent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !appState.searchText.isEmpty {
                        Button {
                            appState.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.ink4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(palette.surfaceSunken, in: Capsule())
                .overlay {
                    Capsule().stroke(palette.line, lineWidth: 1)
                }

                Button {
                    showMore = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(palette.ink3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("会话排序与视图")
            }

            HStack(spacing: 9) {
                glyph(size: 30, palette: palette)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(appState.currentAgent?.displayName ?? "未选择 Agent")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)

                        Button {
                            renameText = appState.currentAgent?.displayName ?? ""
                            isRenaming = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.ink4)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重命名 Agent")
                        .disabled(appState.currentAgent == nil)
                    }

                    Text(agentMeta)
                        .font(DesignTokens.mono(9))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    appState.closeDrawer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.ink3)
                        .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭状态页")
            }
        }
        .padding(.horizontal, DesignTokens.spacing3)
        .padding(.top, DesignTokens.spacing2)
        .padding(.bottom, DesignTokens.spacing3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 会话

    private func sessionRow(_ session: Session, palette: ColorPalette) -> some View {
        let isCurrent = appState.selectedSessionID == session.id

        return Button {
            appState.selectSession(session)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? palette.accentStrong : palette.ink)
                    .lineLimit(1)

                if let preview = session.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.ink4)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                isCurrent ? palette.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyState(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.searchText.isEmpty ? "还没有会话" : "没有匹配的会话")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.ink2)
            Text(appState.searchText.isEmpty
                 ? "在对话页发送第一条消息，或新建会话。"
                 : "尝试更短的关键词，或清除搜索。")
                .font(.system(size: 10))
                .foregroundStyle(palette.ink4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.spacing3)
        .lichenSurface()
        .padding(.top, DesignTokens.spacing2)
    }

    // MARK: 底部

    private func footer(palette: ColorPalette) -> some View {
        HStack(spacing: DesignTokens.spacing2) {
            Button {
                appState.openSettings()
            } label: {
                HStack(spacing: 9) {
                    glyph(size: 28, palette: palette)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.currentAgent?.displayName ?? "未选择 Agent")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text("设置与连接")
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.ink4)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.ink3)
                }
                .padding(.horizontal, 9)
                .frame(minHeight: 50)
                .background(
                    palette.surface,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开设置")

            Button {
                showMore = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.ink3)
                    .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, DesignTokens.spacing3)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 复用

    private func glyph(size: CGFloat, palette: ColorPalette) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.surfaceSunken)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
            Image(systemName: appState.currentAgent?.brand.symbolName ?? "questionmark")
                .font(.system(size: size * 0.52, weight: .medium))
                .foregroundStyle(palette.ink2)
        }
        .frame(width: size, height: size)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { appState.searchText },
            set: { appState.searchText = $0 }
        )
    }

    private var agentMeta: String {
        guard let agent = appState.currentAgent else {
            return "选择 Agent 后开始会话"
        }
        return "\(agent.brand.displayName) · 连接 \(String(format: "%02d", agent.order))"
    }
}

#Preview("状态抽屉 · 明亮") {
    SessionsView()
        .frame(width: 304, height: 760)
        .environment(AppState.preview(screen: .status))
        .preferredColorScheme(.light)
}

#Preview("状态抽屉 · 黑暗") {
    SessionsView()
        .frame(width: 304, height: 760)
        .environment(AppState.preview(screen: .status))
        .preferredColorScheme(.dark)
}
