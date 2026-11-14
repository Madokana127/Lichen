import Foundation
import SwiftUI
import LichenCore

/// 对话页：标题栏、消息流、审批卡片与底部输入 dock。
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = ""
    @State private var agentTriggerAnchor: CGPoint = .zero
    @State private var addAgentAnchor: CGPoint = .zero
    @State private var showAttachmentChoices = false
    @FocusState private var isInputFocused: Bool

    private let contextFiles = [
        "Package.swift",
        "PROJECT_README.md",
        "Sources/LichenCore",
        "Sources/LichenApp"
    ]

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        VStack(spacing: 0) {
            header(palette: palette)
            transcript(palette: palette)
            composer(palette: palette)
        }
        .background(palette.bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            agentPopover(palette: palette)
        }
        .confirmationDialog(
            "附加到上下文",
            isPresented: $showAttachmentChoices,
            titleVisibility: .visible
        ) {
            ForEach(contextFiles, id: \.self) { file in
                Button(file) {
                    let prefix = draft.isEmpty ? "" : " "
                    draft += "\(prefix)@\(file) "
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择要加入当前提示词上下文的文件。")
        }
    }

    // MARK: 顶栏

    private func header(palette: ColorPalette) -> some View {
        HStack(spacing: DesignTokens.spacing1) {
            Button {
                appState.openDrawer()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.ink2)
                    .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开状态页")

            VStack(spacing: 2) {
                Text(appState.currentSession?.title ?? "新的会话")
                    .font(DesignTokens.fontHeadline)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isConnected ? palette.accent : palette.ink4)
                        .frame(width: 5, height: 5)
                    Text(agentStatusLine)
                        .font(DesignTokens.mono(9.5))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(DesignTokens.spring) {
                    appState.isAgentPopoverOpen.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.surface)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                        Image(systemName: brandSymbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(palette.ink2)
                    }
                    .frame(width: 32, height: 32)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.ink4)
                }
                .frame(minWidth: 58, minHeight: DesignTokens.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .revealAnchor($agentTriggerAnchor)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 5, height: 5)
                    .padding(.top, 9)
                    .padding(.trailing, 5)
            }
            .accessibilityLabel("切换 Agent")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(minHeight: 54)
        .background(palette.barGlass)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 消息流

    private func transcript(palette: ColorPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    dayDivider(palette: palette)

                    ForEach(items(from: appState.currentMessages)) { item in
                        switch item {
                        case .message(let message):
                            messageView(message, palette: palette)
                        case .thoughts(let messages):
                            ThoughtBlock(messages: messages, palette: palette)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.spacing4)
                .padding(.top, DesignTokens.spacing3)
                .padding(.bottom, DesignTokens.spacing2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: appState.currentMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onTapGesture {
                if appState.isAgentPopoverOpen {
                    withAnimation(DesignTokens.spring) {
                        appState.isAgentPopoverOpen = false
                    }
                }
            }
        }
    }

    private func dayDivider(palette: ColorPalette) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(palette.line).frame(height: 1)
            Text(dayLabel)
                .font(DesignTokens.mono(9.5))
                .foregroundStyle(palette.ink4)
                .fixedSize()
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private func messageView(_ message: SessionMessage, palette: ColorPalette) -> some View {
        switch message.role {
        case .user:
            userMessage(message, palette: palette)
        case .assistant:
            assistantMessage(message, palette: palette)
        case .thinking:
            ThoughtBlock(messages: [message], palette: palette)
        case .approval:
            if let card = message.approval {
                ApprovalCardView(card: card, palette: palette)
            } else {
                systemMessage(message, palette: palette)
            }
        case .tool:
            toolMessage(message, palette: palette)
        case .system:
            systemMessage(message, palette: palette)
        }
    }

    private func userMessage(_ message: SessionMessage, palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("你")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                Spacer()
                Text(timeLabel(message.createdAt))
                    .font(DesignTokens.mono(9.5))
                    .foregroundStyle(palette.ink4)
            }

            Text(message.text)
                .font(DesignTokens.fontBody)
                .foregroundStyle(palette.ink)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    palette.glassFaint,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                )
                .lichenBorder()
        }
    }

    private func assistantMessage(_ message: SessionMessage, palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surfaceSunken)
                    Image(systemName: brandSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                .frame(width: 20, height: 20)

                Text(appState.currentAgent?.displayName ?? "Agent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink2)

                Text("agent")
                    .font(DesignTokens.mono(8.5))
                    .foregroundStyle(palette.ink4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(palette.line, lineWidth: 1)
                    }

                Spacer()

                Text(timeLabel(message.createdAt))
                    .font(DesignTokens.mono(9.5))
                    .foregroundStyle(palette.ink4)
            }

            HStack(spacing: 7) {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 5, height: 5)
                Text("输出")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(palette.ink)
            }

            Text(message.text)
                .font(.system(size: 13.5, weight: message.isEmphasized ? .bold : .regular))
                .foregroundStyle(palette.ink)
                .lineSpacing(4)
        }
    }

    private func toolMessage(_ message: SessionMessage, palette: ColorPalette) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.ink3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName ?? "工具")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                Text(message.text)
                    .font(DesignTokens.mono(10.5))
                    .foregroundStyle(palette.ink3)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .lichenSurface()
    }

    private func systemMessage(_ message: SessionMessage, palette: ColorPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text(message.text)
                .font(DesignTokens.fontCaption)
        }
        .foregroundStyle(palette.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 底部 dock

    private func composer(palette: ColorPalette) -> some View {
        VStack(spacing: 0) {
            dockBar(palette: palette)
            composerRow(palette: palette)
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusXLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.radiusXLarge, style: .continuous)
                .stroke(palette.composerLine, lineWidth: 1)
        }
        .shadow(color: palette.shadow, radius: 14, x: 0, y: 8)
        .padding(.horizontal, DesignTokens.spacing3)
        .padding(.top, DesignTokens.spacing1)
        .padding(.bottom, 15)
        .background(
            LinearGradient(
                colors: [palette.bg.opacity(0), palette.bg],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func dockBar(palette: ColorPalette) -> some View {
        HStack(spacing: 0) {
            dockChip(
                key: "模型",
                value: appState.modelName,
                icon: nil,
                palette: palette
            ) {
                withAnimation(DesignTokens.quick) {
                    appState.modelName = cycle(
                        appState.modelName,
                        through: ["Sonnet 4.5", "Opus 4.5", "Haiku 4.5"]
                    )
                }
            }
            .frame(maxWidth: .infinity)

            dockChip(
                key: "推理",
                value: appState.effort.rawValue,
                icon: nil,
                palette: palette
            ) {
                withAnimation(DesignTokens.quick) {
                    appState.effort = cycleEffort()
                }
            }
            .frame(width: 72)

            dockChip(
                key: "分支",
                value: appState.gitBranch,
                icon: "arrow.triangle.branch",
                palette: palette
            ) {
                withAnimation(DesignTokens.quick) {
                    appState.gitBranch = cycle(
                        appState.gitBranch,
                        through: ["main", "feature/ui", "release"]
                    )
                }
            }
            .frame(width: 98)

            VStack(spacing: 3) {
                Circle()
                    .fill(appState.isConnected ? palette.accent : palette.ink4)
                    .frame(width: 5, height: 5)
                Text("LIVE")
                    .font(DesignTokens.mono(7.5))
                    .foregroundStyle(palette.ink3)
            }
            .frame(width: 35)
            .frame(maxHeight: .infinity)
        }
        .frame(minHeight: 46)
        .background(palette.composerLine)
    }

    private func dockChip(
        key: String,
        value: String,
        icon: String?,
        palette: ColorPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(key)
                    .font(.system(size: 8.5, weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(palette.ink4)

                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.ink4)
                    }
                    Text(value)
                        .font(DesignTokens.mono(10.5))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(palette.ink4)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.line)
                .frame(width: 1)
        }
    }

    private func composerRow(palette: ColorPalette) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            Button {
                showAttachmentChoices = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.ink3)
                    .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("附加文件到上下文")

            TextField("给 \(appState.currentAgent?.displayName ?? "Agent") 发消息…", text: $draft, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .focused($isInputFocused)
                .padding(.vertical, 11)

            Button(action: sendDraft) {
                ZStack {
                    Circle()
                        .fill(canSend ? palette.accent : palette.surfaceSunken)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? palette.accentInk : palette.ink4)
                }
                .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送消息")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(palette.surface)
    }

    // MARK: Agent 浮框

    private func agentPopover(palette: ColorPalette) -> some View {
        AgentSwitcherPopover(addAgentAnchor: $addAgentAnchor, palette: palette)
            .padding(.top, 60)
            .padding(.trailing, DesignTokens.spacing3)
            .scaleEffect(
                appState.isAgentPopoverOpen ? 1 : 0.42,
                anchor: .topTrailing
            )
            .opacity(appState.isAgentPopoverOpen ? 1 : 0)
            .offset(y: appState.isAgentPopoverOpen ? 0 : -8)
            .blur(radius: appState.isAgentPopoverOpen ? 0 : 7)
            .allowsHitTesting(appState.isAgentPopoverOpen)
            .animation(DesignTokens.spring, value: appState.isAgentPopoverOpen)
    }

    // MARK: 动作

    private func sendDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.submitPrompt(trimmed)
        draft = ""
        isInputFocused = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = items(from: appState.currentMessages).last else { return }
        withAnimation(DesignTokens.standard) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func cycle<T: Equatable>(_ value: T, through options: [T]) -> T {
        guard let index = options.firstIndex(of: value), !options.isEmpty else {
            return options.first ?? value
        }
        return options[(index + 1) % options.count]
    }

    private func cycleEffort() -> LichenEffort {
        let options = LichenEffort.allCases
        guard let index = options.firstIndex(of: appState.effort) else {
            return .medium
        }
        return options[(index + 1) % options.count]
    }

    // MARK: 文案

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var brandSymbol: String {
        appState.currentAgent?.brand.symbolName ?? "sparkles"
    }

    private var agentStatusLine: String {
        let name = appState.currentAgent?.displayName ?? "未选择 Agent"
        let status = appState.isConnected ? "在线" : "离线"
        return "\(name) · \(status)"
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "今天 · HH:mm"
        return formatter.string(from: Date())
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func items(from messages: [SessionMessage]) -> [TranscriptItem] {
        var result: [TranscriptItem] = []
        var thoughtBuffer: [SessionMessage] = []

        func flushThoughts() {
            guard !thoughtBuffer.isEmpty else { return }
            result.append(.thoughts(thoughtBuffer))
            thoughtBuffer.removeAll()
        }

        for message in messages {
            if message.role == .thinking {
                thoughtBuffer.append(message)
            } else {
                flushThoughts()
                result.append(.message(message))
            }
        }
        flushThoughts()
        return result
    }
}

// MARK: - 消息分组

private enum TranscriptItem: Identifiable {
    case message(SessionMessage)
    case thoughts([SessionMessage])

    var id: String {
        switch self {
        case .message(let message):
            return message.id.uuidString
        case .thoughts(let messages):
            return "thoughts-\(messages.first?.id.uuidString ?? "empty")"
        }
    }
}

// MARK: - 思考块

private struct ThoughtBlock: View {
    let messages: [SessionMessage]
    let palette: ColorPalette

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignTokens.standard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.spacing2) {
                    Text("思考过程")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink2)

                    Text("\(messages.count) 步")
                        .font(DesignTokens.mono(9))
                        .foregroundStyle(palette.ink4)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.ink3)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: DesignTokens.tapTarget)
                .padding(.horizontal, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thoughtToggle")
            .accessibilityLabel(isExpanded ? "收起思考过程" : "展开思考过程")

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        HStack(alignment: .top, spacing: DesignTokens.spacing2) {
                            Text(String(format: "%02d", index + 1))
                                .font(DesignTokens.mono(8.5))
                                .foregroundStyle(palette.ink4)
                                .padding(.top, 2)
                            Text(message.text)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.ink3)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
            } else if let preview = messages.first?.text {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
                    .lineLimit(2)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 8)
            }
        }
        .background(palette.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous))
    }
}

// MARK: - 审批卡片

private struct ApprovalCardView: View {
    @Environment(AppState.self) private var appState

    let card: ApprovalCard
    let palette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.warn)
                Text("需要批准")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("COMMAND")
                    .font(DesignTokens.mono(8))
                    .tracking(0.8)
                    .foregroundStyle(palette.ink4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(palette.line, lineWidth: 1)
                    }
            }

            if !card.description.isEmpty {
                Text(card.description)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink2)
                    .lineSpacing(2)
            }

            if !card.command.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Text("$")
                        .font(DesignTokens.mono(11))
                        .foregroundStyle(palette.accent)
                    Text(card.command)
                        .font(DesignTokens.mono(11))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    palette.codeBackground,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            }

            if let resolved = appState.approvalResults[card.requestID] {
                Text("已处理：\(label(for: resolved))")
                    .font(DesignTokens.mono(10))
                    .foregroundStyle(resolved == .deny ? palette.danger : palette.accentStrong)
                    .padding(.top, 2)
            } else {
                HStack(spacing: 6) {
                    ForEach(choices, id: \.rawValue) { choice in
                        approvalButton(choice)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(DesignTokens.spacing3)
        .background(
            palette.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        }
        .shadow(color: palette.shadow, radius: 12, x: 0, y: 6)
    }

    private var choices: [ApprovalChoice] {
        card.choices.isEmpty ? ApprovalChoice.allCases : card.choices
    }

    private func approvalButton(_ choice: ApprovalChoice) -> some View {
        let primary = choice == .once
        let foreground: Color = {
            if primary { return palette.accentInk }
            return choice == .deny ? palette.danger : palette.ink2
        }()

        return Button {
            appState.respondApproval(card, choice: choice)
        } label: {
            Text(label(for: choice))
                .font(.system(size: 11, weight: primary ? .semibold : .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.tapTarget)
                .background(
                    primary ? palette.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func label(for choice: ApprovalChoice) -> String {
        switch choice {
        case .once:
            return "允许一次"
        case .session:
            return "本会话"
        case .always:
            return "始终允许"
        case .deny:
            return "拒绝"
        }
    }
}

// MARK: - Agent 切换浮框

private struct AgentSwitcherPopover: View {
    @Environment(AppState.self) private var appState

    @Binding var addAgentAnchor: CGPoint
    let palette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("切换 AGENT")
                .font(DesignTokens.mono(9))
                .tracking(0.8)
                .foregroundStyle(palette.ink4)
                .padding(.horizontal, 9)
                .padding(.top, 5)
                .padding(.bottom, 7)

            ScrollView(.vertical) {
                VStack(spacing: 1) {
                    ForEach(appState.agents) { agent in
                        agentRow(agent)
                    }
                }
            }
            .frame(maxHeight: 264)
            .scrollIndicators(.hidden)

            HStack(spacing: 6) {
                popAction(
                    title: "新会话",
                    icon: "plus",
                    accent: false
                ) {
                    Task { await appState.createSession() }
                }

                popAction(
                    title: "连接 Agent",
                    icon: "plus",
                    accent: true
                ) {
                    appState.openConnect(
                        from: .chat,
                        anchor: ConnectAnchor(
                            x: Double(addAgentAnchor.x),
                            y: Double(addAgentAnchor.y)
                        )
                    )
                }
                .revealAnchor($addAgentAnchor)
            }
            .padding(.top, 7)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
            }
        }
        .padding(8)
        .frame(width: 292)
        .background(palette.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: appState.isAgentPopoverOpen ? 20 : 42,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: appState.isAgentPopoverOpen ? 20 : 42,
                style: .continuous
            )
            .stroke(palette.lineSoft, lineWidth: 1)
        }
        .shadow(color: palette.shadow, radius: 24, x: 0, y: 14)
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isCurrent = appState.currentAgentID == agent.id

        return Button {
            appState.selectAgent(agent)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isCurrent ? palette.accentSoft : palette.surface)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                    Image(systemName: agent.brand.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isCurrent ? palette.accent : palette.ink2)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("\(agent.brand.displayName) · \(agent.configuration.host) · \(agent.isConnected ? "在线" : "离线")")
                        .font(DesignTokens.mono(8.5))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isCurrent {
                    ZStack {
                        Circle().fill(palette.accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.accentInk)
                    }
                    .frame(width: 17, height: 17)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .background(
                isCurrent ? palette.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func popAction(
        title: String,
        icon: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(accent ? palette.accentStrong : palette.ink2)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                accent ? palette.accentSoft : palette.surfaceHover,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预览

#Preview("对话页 · 明亮") {
    ChatView()
        .environment(AppState.preview(screen: .chat))
        .preferredColorScheme(.light)
}

#Preview("对话页 · 黑暗") {
    ChatView()
        .environment(AppState.preview(screen: .chat))
        .preferredColorScheme(.dark)
}
