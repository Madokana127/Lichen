import Foundation
import LichenCore
import MarkdownView
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 对话页：完美对齐 StartView 风格，带有二级思考强度菜单、消息流、底部发送按钮、点击空白收起键盘，以及远程模型刷新功能。
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = ""
    @State private var showAttachmentChoices = false
    @FocusState private var isInputFocused: Bool

    private let contextFiles = [
        "Package.swift",
        "PROJECT_README.md",
        "Sources/LichenCore"
    ]

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        ZStack {
            // 背景渐变：与 StartView 保持完全一致
            RadialGradient(
                colors: [palette.accentSoft.opacity(0.75), palette.bg],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            FloatingConversationBars { insets in
                transcript(palette: palette, insets: insets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            } top: {
                topNavBar(palette: palette)
                    .padding(.horizontal, DesignTokens.spacing4)
                    .padding(.top, DesignTokens.spacing2)
            } bottom: {
                composer(palette: palette)
                    .padding(.horizontal, DesignTokens.spacing4)
                    .padding(.bottom, DesignTokens.spacing4)
            }
        }
        // 附件选择弹窗
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

    // MARK: - 1. 顶部导航栏
    private func topNavBar(palette: ColorPalette) -> some View {
        HStack(spacing: 12) {
            // 历史对话按钮 + 模型选择菜单 + 独立的刷新按钮
            HStack(spacing: 8) {
                // 左上角按钮：打开 SessionsView
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
                .accessibilityLabel("打开会话")

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
                AgentMenu(source: .chat, palette: palette)
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

    // MARK: - 2. 消息流
    private func transcript(palette: ColorPalette, insets: EdgeInsets) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    dayDivider(palette: palette)

                    if appState.currentMessages.isEmpty && appState.isLoadingCurrentRemoteHistory {
                        ProgressView("正在读取远程历史…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if appState.currentMessages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundStyle(palette.accent)
                            Text("开始与 \(appState.currentAgent?.displayName ?? "Agent") 对话")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.ink)
                            Text("输入问题或选择上下文开始交流")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(items(from: appState.currentMessages)) { item in
                            switch item {
                            case .message(let message):
                                messageView(message, palette: palette)
                            case .thoughts(let messages):
                                ThoughtBlock(messages: messages, palette: palette)
                            }
                        }
                    }
                }
                .padding(.vertical, DesignTokens.spacing3)
            }
            .contentMargins(.horizontal, DesignTokens.spacing4, for: .scrollContent)
            .contentMargins(.top, insets.top, for: .scrollContent)
            .contentMargins(.bottom, insets.bottom, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onChange(of: appState.currentMessages.count) { _, _ in
                scrollToBottom(proxy)
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
                ApprovalCardView(messageID: message.id, card: card, palette: palette)
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
                if message.delivery == .sending {
                    Text("发送中…")
                        .font(DesignTokens.fontCaption)
                        .foregroundStyle(palette.ink4)
                } else if message.delivery == .failed {
                    Text("未确认送达")
                        .font(DesignTokens.fontCaption)
                        .foregroundStyle(palette.danger)
                }
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

                Spacer()

                Text(timeLabel(message.createdAt))
                    .font(DesignTokens.mono(9.5))
                    .foregroundStyle(palette.ink4)
            }

            MarkdownView(
                ReplyMath.compatibleMarkdown(message.text),
                theme: replyTheme(palette: palette, emphasized: message.isEmphasized)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !message.text.isEmpty {
                CopyReplyButton(text: message.text, palette: palette)
            }
        }
    }

    private func replyTheme(palette: ColorPalette, emphasized: Bool) -> MarkdownTheme {
        var theme = MarkdownTheme()
        theme.align(to: 13.5)
        if emphasized { theme.fonts.body = theme.fonts.bold }
        theme.spacings.final = 0
        #if canImport(UIKit)
        theme.colors.body = UIColor(palette.ink)
        theme.colors.emphasis = UIColor(palette.accentStrong)
        theme.colors.code = UIColor(palette.ink)
        theme.colors.codeBackground = UIColor(palette.codeBackground)
        #elseif canImport(AppKit)
        theme.colors.body = NSColor(palette.ink)
        theme.colors.emphasis = NSColor(palette.accentStrong)
        theme.colors.code = NSColor(palette.ink)
        theme.colors.codeBackground = NSColor(palette.codeBackground)
        #endif
        return theme
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

    // MARK: - 3. 底部输入 Dock
    private func composer(palette: ColorPalette) -> some View {
        HStack(spacing: 12) {
            Button {
                showAttachmentChoices = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("附加文件到上下文")

            TextField("问问 Lichen…", text: $draft, axis: .vertical)
                .font(DesignTokens.fontBody)
                .lineLimit(1...4)
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .focused($isInputFocused)
                .onSubmit {
                    sendDraft()
                }

            if appState.isCurrentSessionActive {
                Button {
                    Task { await appState.stopGenerating() }
                } label: {
                    Group {
                        if appState.isStoppingCurrentSession {
                            ProgressView().tint(palette.accentInk)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.accentInk)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(palette.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(appState.isStoppingCurrentSession)
                .accessibilityLabel(appState.isStoppingCurrentSession ? "正在请求停止" : "停止远端输出")
            } else {
                Button {
                    sendDraft()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canSend ? palette.accentInk : palette.ink4)
                        .frame(width: 36, height: 36)
                        .background(
                            canSend ? palette.accent : palette.surfaceSunken,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("发送消息")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .conversationGlass(in: Capsule(), fallback: palette.surface, border: palette.line, shadow: palette.shadow)
    }

    // MARK: - 动作与辅助
    private func sendDraft() {
        guard !appState.isCurrentSessionActive else { return }
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

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var brandSymbol: String {
        appState.currentAgent?.brand.symbolName ?? "sparkles"
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
private struct CopyReplyButton: View {
    let text: String
    let palette: ColorPalette
    @State private var copied = false

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            copied = true
            #elseif canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            copied = pasteboard.setString(text, forType: .string)
            #endif
        } label: {
            Label(copied ? "已复制" : "复制输出", systemImage: copied ? "checkmark" : "document.on.document")
                .font(DesignTokens.fontCaption)
                .foregroundStyle(copied ? palette.accentStrong : palette.ink2)
                .padding(.trailing, DesignTokens.spacing2)
                .frame(minHeight: DesignTokens.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }
}

private struct ApprovalCardView: View {
    @Environment(AppState.self) private var appState

    let messageID: UUID
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
            }

            if !card.description.isEmpty {
                Text(card.description)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink2)
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
                .background(palette.codeBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            let status = appState.approvalStatus(for: messageID)
            switch status {
            case .sent(let choice):
                Text("已发送：\(label(for: choice))")
                    .font(DesignTokens.mono(10))
                    .foregroundStyle(choice == .deny ? palette.danger : palette.accentStrong)
            case .sending:
                statusLabel("正在发送审批结果…")
            case .cancelled:
                statusLabel("此审批已取消或连接已失效")
            case .unavailable:
                statusLabel("此审批当前不可操作")
            case .pending, .failed:
                if case .failed = status {
                    statusLabel("发送失败，可重试")
                }
                HStack(spacing: 6) {
                    ForEach(card.choices.isEmpty ? ApprovalChoice.allCases : card.choices, id: \.rawValue) { choice in
                        Button {
                            appState.respondApproval(messageID: messageID, choice: choice)
                        } label: {
                            Text(label(for: choice))
                                .font(.system(size: 11, weight: choice == .once ? .semibold : .medium))
                                .foregroundStyle(choice == .once ? palette.accentInk : (choice == .deny ? palette.danger : palette.ink2))
                                .frame(maxWidth: .infinity, minHeight: DesignTokens.tapTarget)
                                .background(choice == .once ? palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    if choice != .once {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(palette.line, lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(DesignTokens.spacing3)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous).stroke(palette.line, lineWidth: 1))
        .shadow(color: palette.shadow, radius: 12, x: 0, y: 6)
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.mono(10))
            .foregroundStyle(palette.ink3)
    }

    private func label(for choice: ApprovalChoice) -> String {
        switch choice {
        case .once: return "允许一次"
        case .session: return "本会话"
        case .always: return "始终允许"
        case .deny: return "拒绝"
        }
    }
}
