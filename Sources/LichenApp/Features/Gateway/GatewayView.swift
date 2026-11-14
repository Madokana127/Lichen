import Foundation
import SwiftUI
import LichenCore

/// 连接页：远程网关 / SSL 两种方式，测试后保存并连接。
///
/// 页面本身不做圆形转场，关闭时由 ``RootView`` 先反向收拢再回调 `onClose`。
struct GatewayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    @State private var host = "agent.example.invalid"
    @State private var portText = "8787"
    @State private var method: ConnectionMethod = .gateway
    @State private var authMode: GatewayAuthMode = .token
    @State private var token = ""
    @State private var brand: AgentBrand = .claude
    @State private var allowSelfSigned = false
    @State private var verifyCertificate = true
    @State private var timeout: TimeInterval = 30
    @State private var showAdvanced = false
    @State private var customHeaders = ""
    @State private var testStatus: String?
    @State private var isTesting = false
    @State private var isConnecting = false
    @State private var errorText: String?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host
        case port
        case token
        case headers
    }

    private let timeoutOptions: [TimeInterval] = [10, 30, 60]

    var body: some View {
        let palette = DesignTokens.colors(for: colorScheme)

        VStack(spacing: 0) {
            header(palette: palette)
            scrollContent(palette: palette)
            footer(palette: palette)
        }
        .padding(.top, 54)
        .padding(.bottom, 20)
        .background(background(palette: palette).ignoresSafeArea())
        .onAppear {
            token = appState.accessToken
            if !appState.additionalHeaders.isEmpty {
                customHeaders = appState.additionalHeaders
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
            }
        }
    }

    // MARK: 头部

    private func header(palette: ColorPalette) -> some View {
        HStack(spacing: 7) {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(palette.ink2)
                    .frame(width: DesignTokens.tapTarget, height: DesignTokens.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回上一页")

            VStack(alignment: .leading, spacing: 1) {
                Text("新连接")
                    .font(DesignTokens.mono(9))
                    .tracking(0.7)
                    .foregroundStyle(palette.ink4)
                Text("连接 Agent")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }

            Spacer(minLength: DesignTokens.spacing2)

            Text("网关")
                .font(DesignTokens.mono(8.5))
                .foregroundStyle(palette.ink3)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay {
                    Capsule().stroke(palette.lineStrong, lineWidth: 1)
                }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .frame(minHeight: 56)
    }

    // MARK: 表单

    private func scrollContent(palette: ColorPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("通过远程网关接入电脑端 Agent；选择 SSL 时以 wss / TLS 加密连接。凭据只在本次连接中使用，不写入日志。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink3)
                    .lineSpacing(3)
                    .frame(maxWidth: 330, alignment: .leading)
                    .padding(.top, 2)
                    .padding(.bottom, 10)

                gatewaySection(palette: palette)
                authSection(palette: palette)
                brandSection(palette: palette)
                advancedSection(palette: palette)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .padding(.bottom, DesignTokens.spacing5)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func gatewaySection(palette: ColorPalette) -> some View {
        section(title: "网关", index: "01 / 04", palette: palette) {
            HStack(alignment: .bottom, spacing: 9) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("主机地址")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                    fieldInput(palette: palette) {
                        TextField("agent.example.invalid", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .host)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("端口")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                    fieldInput(palette: palette) {
                        TextField("8787", text: $portText)
                            .font(DesignTokens.mono(12))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .port)
                    }
                }
                .frame(width: 82)
            }

            Text("填写电脑端 Agent 暴露的网关主机地址；SSL 模式使用 wss / TLS 加密连接。")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.ink4)
                .lineSpacing(2)

            methodSegment(palette: palette)

            if method == .ssl {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "允许自签名证书",
                        subtitle: "网关使用自签名证书时开启",
                        isOn: Binding(
                            get: { allowSelfSigned },
                            set: { newValue in
                                allowSelfSigned = newValue
                                verifyCertificate = !newValue
                            }
                        ),
                        palette: palette
                    )

                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                        .padding(.leading, 12)

                    toggleRow(
                        title: "验证 TLS 证书",
                        subtitle: "关闭后接受未经系统信任的证书",
                        isOn: Binding(
                            get: { verifyCertificate },
                            set: { newValue in
                                verifyCertificate = newValue
                                allowSelfSigned = !newValue
                            }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func authSection(palette: ColorPalette) -> some View {
        section(title: "鉴权", index: "02 / 04", palette: palette) {
            HStack(spacing: 2) {
                segmentButton(
                    title: "访问令牌",
                    isActive: authMode == .token,
                    palette: palette
                ) {
                    withAnimation(DesignTokens.standard) {
                        authMode = .token
                    }
                }

                segmentButton(
                    title: "OAuth",
                    isActive: authMode == .oauth,
                    palette: palette
                ) {
                    withAnimation(DesignTokens.standard) {
                        authMode = .oauth
                    }
                }
            }
            .padding(2)
            .background(
                palette.surfaceSunken,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(authMode == .token ? "访问令牌" : "OAuth 访问令牌")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)

                fieldInput(palette: palette) {
                    SecureField("粘贴令牌（不回显）", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .token)
                }
            }

            Text(authMode == .token
                 ? "令牌由电脑端网关生成，可随时吊销。"
                 : "OAuth 模式会先换取一次性 WebSocket 票据，再建立连接。")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.ink4)
        }
    }

    private func brandSection(palette: ColorPalette) -> some View {
        section(title: "Agent 品牌", index: "03 / 04", palette: palette) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                spacing: 7
            ) {
                ForEach(AgentBrand.allCases, id: \.rawValue) { option in
                    brandOption(option, palette: palette)
                }
            }

            Text("将命名为 \(autoName)（品牌 + 加入顺序，可稍后重命名）")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.ink4)
        }
    }

    private func advancedSection(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignTokens.standard) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.spacing2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高级")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                        Text("超时 · 自定义头")
                            .font(DesignTokens.mono(9))
                            .foregroundStyle(palette.ink4)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.ink3)
                        .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                }
                .frame(minHeight: DesignTokens.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("连接超时")
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.ink3)
                            Spacer()
                            Text("timeout")
                                .font(DesignTokens.mono(8.5))
                                .foregroundStyle(palette.ink4)
                        }

                        HStack(spacing: 2) {
                            ForEach(timeoutOptions, id: \.self) { seconds in
                                segmentButton(
                                    title: "\(Int(seconds))s",
                                    isActive: timeout == seconds,
                                    palette: palette
                                ) {
                                    withAnimation(DesignTokens.quick) {
                                        timeout = seconds
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("自定义请求头")
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.ink3)

                        fieldInput(palette: palette) {
                            TextField("X-Lichen-Workspace: lichen.swiftpm", text: $customHeaders, axis: .vertical)
                                .font(DesignTokens.mono(10.5))
                                .lineLimit(2...4)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .headers)
                        }
                    }
                }
                .padding(.bottom, DesignTokens.spacing3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 底部

    private func footer(palette: ColorPalette) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: DesignTokens.spacing2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(testStatusColor(palette: palette))
                        .frame(width: 5, height: 5)
                    Text(testStatus ?? "尚未测试")
                        .font(DesignTokens.mono(9))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: DesignTokens.spacing2)

                Button(action: testConnection) {
                    Text(isTesting ? "测试中…" : "测试连接")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .overlay {
                            Capsule().stroke(palette.lineStrong, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isTesting || isConnecting)
            }

            Button(action: saveAndConnect) {
                HStack(spacing: 8) {
                    Text(isConnecting ? "连接中…" : "保存并连接")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: isConnecting ? "hourglass" : "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(palette.accentInk)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    palette.accent,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.danger)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DesignTokens.spacing5)
        .padding(.top, DesignTokens.spacing3)
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: 复用件

    private func section<Content: View>(
        title: String,
        index: String,
        palette: ColorPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(index)
                    .font(DesignTokens.mono(8.5))
                    .tracking(0.6)
                    .foregroundStyle(palette.ink4)
            }

            content()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    private func fieldInput<Content: View>(
        palette: ColorPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: 12.5))
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: DesignTokens.tapTarget)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                    .stroke(palette.lineStrong, lineWidth: 1)
            }
    }

    private func methodSegment(palette: ColorPalette) -> some View {
        HStack(spacing: 2) {
            segmentButton(
                title: "远程网关",
                isActive: method == .gateway,
                palette: palette
            ) {
                withAnimation(DesignTokens.standard) {
                    method = .gateway
                }
            }

            segmentButton(
                title: "SSL",
                isActive: method == .ssl,
                palette: palette
            ) {
                withAnimation(DesignTokens.standard) {
                    method = .ssl
                }
            }
        }
        .padding(2)
        .background(
            palette.surfaceSunken,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .accessibilityLabel("连接方式")
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

    private func brandOption(_ option: AgentBrand, palette: ColorPalette) -> some View {
        let isActive = brand == option

        return Button {
            withAnimation(DesignTokens.quick) {
                brand = option
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 18, weight: .medium))
                Text(option.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? palette.accentStrong : palette.ink3)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(
                isActive ? palette.accentSoft : palette.surface,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isActive ? palette.accent : palette.line, lineWidth: isActive ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
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

    private func background(palette: ColorPalette) -> some View {
        ZStack {
            palette.bg
            RadialGradient(
                colors: [palette.accentSoft.opacity(0.7), palette.bg.opacity(0)],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    // MARK: 数据与动作

    private var nextOrder: Int {
        (appState.agents.map(\.order).max() ?? 0) + 1
    }

    private var autoName: String {
        String(format: "%@ %02d", brand.displayName, nextOrder)
    }

    private var portValue: Int? {
        Int(portText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var configuration: GatewayConfiguration? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let port = portValue,
              (1...65535).contains(port) else {
            return nil
        }

        return GatewayConfiguration(
            displayName: autoName,
            host: trimmedHost,
            port: port,
            method: method,
            authMode: authMode,
            allowSelfSignedCertificate: allowSelfSigned || !verifyCertificate,
            timeout: timeout
        )
    }

    private var parsedHeaders: [String: String] {
        var result: [String: String] = [:]
        for rawLine in customHeaders.split(whereSeparator: \.isNewline) {
            guard let separator = rawLine.firstIndex(of: ":") else { continue }
            let key = String(rawLine[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(rawLine[rawLine.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    private func testStatusColor(palette: ColorPalette) -> Color {
        guard let testStatus else { return palette.ink4 }
        if testStatus.contains("成功") {
            return palette.accent
        }
        if testStatus.contains("失败") || testStatus.contains("请填写") {
            return palette.danger
        }
        return palette.ink4
    }

    private func testConnection() {
        guard let configuration else {
            testStatus = "请填写有效的主机与端口"
            return
        }

        focusedField = nil
        isTesting = true
        testStatus = "正在测试…"
        errorText = nil
        appState.accessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.additionalHeaders = parsedHeaders

        Task { @MainActor in
            let result = await appState.testConnection(configuration: configuration)
            testStatus = result
            isTesting = false
        }
    }

    private func saveAndConnect() {
        guard !isConnecting else { return }
        guard let configuration else {
            errorText = "请填写有效的主机与端口（1...65535）。"
            testStatus = "请填写有效的主机与端口"
            return
        }

        focusedField = nil
        isConnecting = true
        errorText = nil
        appState.accessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.additionalHeaders = parsedHeaders

        let agent = Agent(
            brand: brand,
            displayName: configuration.displayName,
            order: nextOrder,
            configuration: configuration,
            isConnected: false
        )
        appState.addAgent(agent)

        Task { @MainActor in
            await appState.connect(configuration: configuration)
            isConnecting = false

            if appState.isConnected {
                onClose()
            } else {
                errorText = appState.lastErrorMessage ?? "连接未完成，请检查主机、端口与凭据。"
                if let index = appState.agents.firstIndex(where: { $0.id == agent.id }) {
                    appState.agents[index].isConnected = false
                }
            }
        }
    }
}

#Preview("连接页 · 明亮") {
    GatewayView(onClose: {})
        .environment(AppState.preview())
        .preferredColorScheme(.light)
}

#Preview("连接页 · 黑暗") {
    GatewayView(onClose: {})
        .environment(AppState.preview())
        .preferredColorScheme(.dark)
}
