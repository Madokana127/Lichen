import Foundation
import LichenCore
import MarkdownParser
import MarkdownView
import Testing
@testable import LichenAppRunner

@MainActor
struct LichenAppRunnerTests {
    @Test func replyMathRendersUnsupportedOperatorNamesInFormulas() {
        #expect(ReplyMath.compatibleMarkdown(#"\in\operatorname{Im}(A)"#) == #"\(\in\mathrm{Im}(A)\)"#)
        #expect(
            ReplyMath.compatibleMarkdown(#"If $x\in\operatorname{Im}(A)$, then \[\operatorname{rank}(A)=2\]"#)
                == #"If \(x\in\mathrm{Im}(A)\), then \[\mathrm{rank}(A)=2\]"#
        )
    }

    @Test func laplaceProofFormulasRenderWithTheChatRenderer() {
        let source = #"""
        设 $A_{ij}=(-1)^{i+j}M_{ij}$，并令 $\sigma=\hat\pi_{i_j}$。

        $$\det A=\sum_{j=1}^{n}a_{ij}A_{ij}\qquad\Big(\text{相应地 }\det A=\sum_{i=1}^{n}a_{ij}A_{ij}\Big).$$

        $$\det A=\sum_{j=1}^{n}a_{1j}\sum_{\substack{\sigma\in S_n\\ \sigma(1)=j}}\operatorname{sgn}(\sigma)\prod_{k=2}^{n}a_{k\sigma(k)}.$$

        $$\boxed{\ \det A=\sum_{j=1}^{n}(-1)^{i+j}a_{ij}M_{ij}=\sum_{j=1}^{n}a_{ij}A_{ij}.\ }$$

        余子式来自 $\begin{pmatrix}1&0\\0&M_{ij}\end{pmatrix}$。$\blacksquare$
        """#
        let markdown = ReplyMath.compatibleMarkdown(source)
        #expect(markdown.contains("相应地"))
        #expect(markdown.contains("■"))
        let content = MarkdownContent(markdown: markdown)
        #expect(content.rendered.count == 7)
        for formula in content.rendered.values {
            #expect(formula.image != nil, "\(formula.text)")
        }
    }

    @Test func generalizedLaplaceProofRendersArrowsFractionsAndTableMath() {
        let source = #"""
        沿 $i_t$ 依次作用：$i_t\xrightarrow{\rho}t\xrightarrow{\pi\oplus\tau}\pi(t)\xrightarrow{\kappa^{-1}}j_{\pi(t)}=\sigma(i_t)$。

        $$\operatorname{inv}(\delta)=\sum_{t=1}^{k}(i_t-t)=\sum I-\tfrac{k(k+1)}{2}\ \Longrightarrow\ \operatorname{sgn}\rho=(-1)^{\sum I-k(k+1)/2}.$$

        $$\operatorname{inv}(\delta)=\#\{(t,s):r_s<i_t\}.$$
        $$\boxed{\ \det A=\sum_{|J|=k}(-1)^{\sum I+\sum J}\,\det A[I|J]\cdot \det A[I^c|J^c],\qquad \sum I=\sum_{t=1}^k i_t,\ \ \sum J=\sum_{t=1}^k j_t.}$$
        $$\bigwedge_{i=1}^{n}\text{row}_i=(-1)^{\sum I-\frac{k(k+1)}2}\Big(\bigwedge_{i\in I}\text{row}_i\Big)\wedge\Big(\bigwedge_{i\in I^c}\text{row}_i\Big)$$

        | $J$ | 符号 $(-1)^{\sum I+\sum J}$ | $\det A[I\vert J]$ | 项 |
        |---|---|---|---|
        | $\{1,2\}$ | $(-1)^{1+3+1+2}=-\ $ | $4$ | $-8$ |
        """#
        let content = MarkdownContent(markdown: ReplyMath.compatibleMarkdown(source))
        #expect(content.rendered.count == 13)
        for formula in content.rendered.values {
            #expect(formula.image != nil, "\(formula.text)")
        }
    }

    @Test func modelStyleLatexRendersWithTheChatRenderer() {
        // Output conventions: https://huggingface.co/blog/open-r1/update-2
        // Delimiters and AMS environments: https://docs.mathjax.org/en/latest/basic/mathematics.html
        // Command samples: https://katex.org/docs/supported
        let samples: [(name: String, markdown: String, expectedImages: Int)] = [
            ("Open R1 word problem, adapted from rows 0–1", #"""
            设 \(x = \frac{1}{v-r}\)。由题意：
            1. \[
               -3x=-0.5\implies x=\frac{1}{6}
               \]
            2. \(\boxed{v=10}\) 并且 \(\boxed{r=4}\)。
            """#, 4),
            ("Open R1 nested fractions and boxed answer, adapted from row 4", #"""
            化简 $\frac{8x+13}{3}=\frac{19-12x}{2}-\left(16x-\frac{7-4x}{6}\right)$ 后，
            \[\boxed{\dfrac{1}{4}}\]
            """#, 2),
            ("Inline subscripts and integrals", #"用 $x_{i_j}^2$，并计算 $$\int_{-\infty}^{\infty} e^{-x^2}\,dx=\sqrt{\pi}$$。"#, 2),
            ("Aligned system", #"$$\begin{aligned}2x+y&=5\\x-y&=1\end{aligned}$$"#, 1),
            ("Piecewise function", #"$$f(x)=\begin{cases}x^2&\text{if }x\ge 0\\-x&\text{if }x<0\end{cases}$$"#, 1),
            ("Matrix and determinant", #"$$A=\begin{bmatrix}1&2\\3&4\end{bmatrix},\quad\det A=\begin{vmatrix}1&2\\3&4\end{vmatrix}=-2$$"#, 1),
            ("Combinatorics and conditional probability", #"由 $P(A\mid B)=\frac{P(A\cap B)}{P(B)}$ 和 $\binom{n}{k}=\frac{n!}{k!(n-k)!}$。"#, 2),
            ("Named and limit operators", #"$$\operatorname{rank}(A)=2,\qquad \lim_{x\to 0}\frac{\sin x}{x}=1$$"#, 1),
            ("Stacked sum conditions and arrows", #"$$\sum_{\substack{i,j\ge 0\\i+j=n}}\binom{n}{i}=2^n,\qquad A\xrightarrow{T}B$$"#, 1),
            ("Markdown table", #"""
            | 量 | 公式 |
            |---|---|
            | 期望 | $\mathbb{E}[X]=\sum_i x_i p_i$ |
            | 方差 | $\operatorname{Var}(X)=\mathbb{E}[X^2]-\mathbb{E}[X]^2$ |
            """#, 2),
        ]

        for sample in samples {
            let content = MarkdownContent(markdown: ReplyMath.compatibleMarkdown(sample.markdown))
            #expect(content.rendered.count == sample.expectedImages, "\(sample.name)")
            for formula in content.rendered.values {
                #expect(formula.image != nil, "\(sample.name): \(formula.text)")
            }
        }
    }

    @Test func modelStyleLatexRendersEquationAndAnnotations() {
        let samples: [(source: String, contents: [String])] = [
            (#"$$\begin{equation}a^2+b^2=c^2\end{equation}$$"#, ["a^2+b^2=c^2"]),
            (#"\[\begin{equation*}x+y=z\end{equation*}\]"#, ["x+y=z"]),
            (#"$A\xrightarrow[\alpha]{\beta}B$"#, [#"\alpha"#, #"\beta"#, #"\longrightarrow"#]),
            (#"$A\overset{\mathrm{def}}{=}B$"#, [#"\mathrm{def}"#, "="])
        ]
        for sample in samples {
            let content = MarkdownContent(markdown: ReplyMath.compatibleMarkdown(sample.source))
            #expect(content.rendered.count == 1, "\(sample.source)")
            for formula in content.rendered.values {
                #expect(formula.image != nil, "\(formula.text)")
                for expected in sample.contents {
                    #expect(formula.text.contains(expected))
                }
            }
        }
    }

    @Test func modelStyleLatexPreservesLiteralPricesAndCode() {
        let source = #"""
        价格是 $2.50 和 $2.00。代码 `$\frac{1}{2}$` 不渲染。

        ~~~markdown
        $$\sum_i i$$
        ~~~
        """#
        let content = MarkdownContent(markdown: ReplyMath.compatibleMarkdown(source))
        let hasLiteralParagraph = content.blocks.contains { block in
            guard case let .paragraph(nodes) = block else { return false }
            return nodes.contains { node in
                if case let .text(text) = node { return text.contains("$2.50 和 $2.00") }
                return false
            } && nodes.contains { node in
                if case let .code(code) = node { return code == #"$\frac{1}{2}$"# }
                return false
            } && !nodes.contains { node in
                if case .math = node { return true }
                return false
            }
        }
        #expect(hasLiteralParagraph, "\(content.blocks)")

        let hasLiteralFence = content.blocks.contains { block in
            if case let .codeBlock(_, code) = block { return code.contains(#"$$\sum_i i$$"#) }
            return false
        }
        #expect(hasLiteralFence)
    }

    @Test func replyMathLeavesMarkdownCodeAndProseUntouched() {
        let source = #"""
        Literal \operatorname{Im}(A), or the code span `$\operatorname{Im}(A)$`.

        ~~~latex
        \[\operatorname{Im}(A)\]
        ~~~

        An equation: \(x\in\operatorname{Im}(A)\).
        """#
        #expect(ReplyMath.compatibleMarkdown(source) == source.replacingOccurrences(
            of: #"\(x\in\operatorname{Im}(A)\)"#, with: #"\(x\in\mathrm{Im}(A)\)"#
        ))
    }

    @Test func synchronizesStoredSessionsAndLoadsTheirPagedTranscript() async throws {
        let agent = makeAgent("Agent")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistentSessionStore(directoryURL: directory)
        let client = StubGateway()
        client.historyRPC = { method, params in
            let cursor = params?["cursor"]?.stringValue
            switch method {
            case GatewayMethod.sessionList:
                guard params?["scope"]?.stringValue == "stored" else {
                    return .object(["sessions": .array([])])
                }
                if cursor == nil {
                    return .object([
                        "sessions": .array([.object(["id": .string("saved-first")])]),
                        "next_cursor": .string("more-sessions")
                    ])
                }
                #expect(cursor == "more-sessions")
                return .object(["sessions": .array([.object([
                    "id": .string("saved-second"), "title": .string("Remote conversation")
                ])])])
            case GatewayMethod.sessionTranscript:
                #expect(params?["session_id"]?.stringValue == "saved-second")
                if cursor == nil {
                    return .object([
                        "rows": .array([.object(["role": .string("user"), "text": .string("Past question")])]),
                        "next_cursor": .string("more-messages")
                    ])
                }
                #expect(cursor == "more-messages")
                return .object(["rows": .array([
                    .object(["role": .string("assistant"), "text": .string("Past answer")])
                ])])
            default:
                return nil
            }
        }
        let state = makeState(client: client, agents: [agent], sessions: [], store: store)

        await state.refreshSessions()
        #expect(Set(state.sessions.compactMap(\.remoteHistoryID)) == ["saved-first", "saved-second"])
        #expect(state.currentSession == nil)
        let session = try #require(state.sessions.first { $0.remoteHistoryID == "saved-second" })
        state.selectSession(session)
        try await waitUntil { !state.isLoadingCurrentRemoteHistory }

        #expect(state.currentMessages.map(\.text) == ["Past question", "Past answer"])
        #expect(state.currentSession?.remoteID == nil)

        let reopened = AppState(sessionStore: PersistentSessionStore(directoryURL: directory), agents: [agent])
        await reopened.restore()
        let savedSession = try #require(reopened.sessions.first { $0.id == session.id })
        reopened.selectSession(savedSession)
        try await waitUntil { reopened.currentMessages.count == 2 }
        #expect(reopened.currentMessages == state.currentMessages)
    }

    @Test func olderGatewayLoadsHistoryByResumingTheSavedSessionOnce() async throws {
        let agent = makeAgent("Agent")
        let client = StubGateway()
        var resumes = 0
        client.historyRPC = { method, params in
            switch method {
            case GatewayMethod.sessionList:
                if params?["scope"] != nil { throw GatewayError.server(code: 4002, message: "unknown field") }
                return .object(["sessions": .array([.object(["id": .string("saved")])])])
            case GatewayMethod.sessionTranscript:
                throw GatewayError.server(code: -32601, message: "unknown method")
            case GatewayMethod.sessionResume:
                resumes += 1
                #expect(params?["session_id"]?.stringValue == "saved")
                return .object([
                    "session_id": .string("active"),
                    "messages": .array([.object(["role": .string("assistant"), "content": .string("Old answer")])])
                ])
            default:
                return nil
            }
        }
        let state = makeState(client: client, agents: [agent], sessions: [])

        await state.refreshSessions()
        state.selectSession(try #require(state.sessions.first))
        state.submitPrompt("Continue")
        try await waitUntil { client.submittedSessionIDs == ["active"] }

        #expect(resumes == 1)
        #expect(state.currentMessages.map(\.text) == ["Old answer", "Continue"])
    }

    @Test(arguments: [true, false])
    func gatewayUsesTheAdvertisedAuthenticationMethod(usesSessionToken: Bool) async throws {
        let http = AuthenticationHTTPStub(provider: usesSessionToken ? "session-token" : "oidc")
        var upgradeURL: URL?
        let client = URLSessionGatewayClient(
            credentials: GatewayCredentials(token: "test-token"),
            timings: GatewayTimings(handshakeTimeout: 2),
            automaticallyReconnects: false,
            http: http,
            webSocketFactory: { request in
                upgradeURL = request.url
                return ReadyWebSocket()
            }
        )
        // An old saved preference must not override the gateway's only supported method.
        let configuration = GatewayConfiguration(
            displayName: "Test", host: "https://gateway.example.invalid",
            authMode: usesSessionToken ? .oauth : .token
        )

        try await client.connect(to: configuration)
        await client.disconnect()

        let url = try #require(upgradeURL)
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.path == "/api/ws")
        if usesSessionToken {
            #expect(http.requests.map { $0.url?.path } == ["/api/status"])
            #expect(parameters == [URLQueryItem(name: "token", value: "test-token")])
        } else {
            #expect(http.requests.map { $0.url?.path } == ["/api/status", "/api/auth/ws-ticket"])
            #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(parameters == [URLQueryItem(name: "ticket", value: "one-time-ticket")])
        }
    }

    @Test func successfulConnectionSavesCredentialsAndReconnectsOnNextLaunch() async throws {
        let suite = "LichenAppRunnerTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let agent = makeAgent("Saved Agent")
        let credentials = GatewayCredentials(token: "test-token", additionalHeaders: ["X-Test": "value"])
        let credentialStore = StubCredentialStore()
        let firstLaunch = AppState(
            gateway: StubGateway(), agentStore: AgentStore(defaults: defaults), credentialStore: credentialStore
        )
        #expect(await firstLaunch.connect(agent: agent, credentials: credentials))
        #expect(credentialStore.entries[agent.id] == credentials)

        let gateway = StubGateway()
        let nextLaunch = AppState(
            gateway: gateway, agentStore: AgentStore(defaults: defaults), credentialStore: credentialStore
        )
        await nextLaunch.restore()
        await nextLaunch.restore()

        #expect(gateway.connectedConfigurations == [agent.configuration])
        #expect(credentialStore.loadedAgentIDs == [agent.id])
        #expect(nextLaunch.connectedAgentID == agent.id)
    }

    @Test func selectingAnotherAgentDoesNotSendOverTheOldConnection() async throws {
        let first = makeAgent("First")
        let second = makeAgent("Second")
        let firstSession = makeSession(agent: first, remoteID: "shared-id")
        let secondSession = makeSession(agent: second, remoteID: "shared-id")
        let client = StubGateway()
        let state = makeState(client: client, agents: [first, second], sessions: [firstSession, secondSession])

        state.selectSession(secondSession)
        state.submitPrompt("Only for the second Agent")

        try await waitUntil { state.currentMessages.first?.delivery == .failed }
        #expect(state.connectedAgentID == first.id)
        #expect(state.currentAgentID == second.id)
        #expect(client.submittedSessionIDs.isEmpty)
    }

    @Test func firstPromptAfterRestoringHistoryStartsANewConversation() async throws {
        let agent = makeAgent("Agent")
        let history = makeSession(agent: agent, remoteID: "previous-session")
        let client = StubGateway()
        let state = AppState(
            gateway: client, sessionStore: InMemorySessionStore(initial: [history]),
            agents: [agent], connectionState: client.currentState
        )

        await state.restore()
        #expect(state.sessions.map(\.id) == [history.id])
        #expect(state.currentSession == nil)
        state.submitPrompt("Start a fresh conversation")

        try await waitUntil { state.currentMessages.first?.delivery == .sent }
        #expect(state.currentSession?.id != history.id)
        #expect(client.submittedSessionIDs == ["created-session"])
        #expect(client.createdSessions == 1)

        state.selectSession(history)
        state.submitPrompt("Continue the conversation I selected")
        try await waitUntil { state.currentMessages.first?.delivery == .sent }
        #expect(state.currentSession?.id == history.id)
        #expect(client.submittedSessionIDs == ["created-session", "previous-session"])
        #expect(client.createdSessions == 1)
    }

    @Test func twoPromptsBindTheSameNewRemoteSession() async throws {
        let agent = makeAgent("Agent")
        let client = StubGateway()
        let state = makeState(client: client, agents: [agent], sessions: [])

        state.submitPrompt("First prompt")
        state.submitPrompt("Second prompt")

        try await waitUntil {
            let messages = state.currentMessages
            return messages.count == 2 && messages.allSatisfy { $0.delivery == .sent }
        }
        #expect(client.createdSessions == 1)
        #expect(client.submittedSessionIDs == ["created-session", "created-session"])
        #expect(state.currentSession?.remoteID == "created-session")
    }

    @Test func stopGeneratingSendsHermesInterruptOnlyToTheCurrentRemoteSession() async throws {
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        let client = StubGateway()
        let state = makeState(client: client, agents: [agent], sessions: [session])

        client.emit(.init(type: GatewayEventType.messageDelta, sessionID: session.remoteID, payload: .string("partial")))
        try await waitUntil { state.isCurrentSessionActive }
        await state.stopGenerating()

        #expect(client.interruptedSessionIDs == ["remote-session"])
        #expect(state.isConnected)
        client.emit(.init(
            type: GatewayEventType.messageComplete, sessionID: session.remoteID,
            payload: .object(["status": .string("interrupted"), "text": .string("")])
        ))
        try await waitUntil { !state.isCurrentSessionActive }
        #expect(state.currentMessages.map(\.text) == ["partial"])
    }

    @Test func turnCanBeStoppedBeforeSubmissionRPCReturns() async throws {
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        let client = StubGateway()
        client.holdPromptResponse = true
        defer { client.releasePromptResponse() }
        let state = makeState(client: client, agents: [agent], sessions: [session])

        state.submitPrompt("Generate a long response")
        try await waitUntil { client.pendingPromptResponse != nil }
        #expect(state.isCurrentSessionActive)
        await state.stopGenerating()
        #expect(client.interruptedSessionIDs == ["remote-session"])
        #expect(client.pendingPromptResponse != nil)
    }

    @Test func alreadyIdleResponseClearsStopState() async throws {
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        let client = StubGateway()
        client.interruptResult = .object(["status": .string("not_interrupted")])
        let state = makeState(client: client, agents: [agent], sessions: [session])
        client.emit(.init(type: GatewayEventType.messageStart, sessionID: session.remoteID))
        try await waitUntil { state.isCurrentSessionActive }

        await state.stopGenerating()

        #expect(!state.isCurrentSessionActive)
    }

    @Test func failedSubmissionTurnsStopBackIntoSend() async throws {
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        let client = StubGateway()
        client.rejectPrompt = true
        let state = makeState(client: client, agents: [agent], sessions: [session])

        state.submitPrompt("Will fail locally")
        try await waitUntil { state.currentMessages.first?.delivery == .failed }
        #expect(!state.isCurrentSessionActive)
        #expect(client.interruptedSessionIDs.isEmpty)
    }

    @Test func delayedReplyFollowsItsRemoteIDInsteadOfTheCurrentSelection() async throws {
        let agent = makeAgent("Agent")
        let origin = makeSession(agent: agent, remoteID: "non-uuid-origin")
        let selected = makeSession(agent: agent, remoteID: "non-uuid-selected")
        let client = StubGateway()
        let state = makeState(client: client, agents: [agent], sessions: [origin, selected])

        state.selectSession(selected)
        client.emit(.init(type: GatewayEventType.messageDelta, sessionID: origin.remoteID, payload: .string("First")))
        client.emit(.init(type: GatewayEventType.messageComplete, sessionID: origin.remoteID, payload: .string("First reply")))
        client.emit(.init(type: GatewayEventType.messageComplete, sessionID: "unknown", payload: .string("Wrong session")))

        try await waitUntil { state.messages[origin.id]?.first?.text == "First reply" }
        #expect(state.currentMessages.isEmpty)
        #expect(state.sessions.count == 2)
        #expect(state.messages[origin.id]?.map(\.text) == ["First reply"])
    }

    @Test func completedReplySurvivesReopeningTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistentSessionStore(directoryURL: directory)
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        try await store.update(session)
        let client = StubGateway()
        let state = makeState(client: client, agents: [agent], sessions: [session], store: store)

        client.emit(.init(type: GatewayEventType.messageDelta, sessionID: session.remoteID, payload: .string("Hello")))
        client.emit(.init(type: GatewayEventType.messageComplete, sessionID: session.remoteID, payload: .string("Hello world")))

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while try await store.messages(sessionID: session.id).isEmpty {
            try #require(clock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(state.messages[session.id]?.map(\.text) == ["Hello world"])
        let reopened = PersistentSessionStore(directoryURL: directory)
        #expect(try await reopened.messages(sessionID: session.id).map(\.text) == ["Hello world"])
        #expect(try await reopened.listSessions().first?.messageCount == 1)
    }

    @Test func failedApprovalCanRetryWithTheOriginalTypedRPCID() async throws {
        let agent = makeAgent("Agent")
        let session = makeSession(agent: agent, remoteID: "remote-session")
        let client = StubGateway()
        client.rejectApproval = true
        let state = makeState(client: client, agents: [agent], sessions: [session])

        client.emit(ServerRequest(id: .int(42), method: GatewayMethod.approval, params: .object([
            "session_id": .string("remote-session"),
            "request_id": .string("business-id")
        ])))

        try await waitUntil { state.messages[session.id]?.first?.approval != nil }
        let message = try #require(state.messages[session.id]?.first)
        state.respondApproval(messageID: message.id, choice: .once)
        try await waitUntil {
            if case .failed = state.approvalStatus(for: message.id) { return true }
            return false
        }

        #expect(client.approvalIDs == [.int(42)])
        #expect(state.messages[session.id]?.count == 1)
        client.rejectApproval = false
        state.respondApproval(messageID: message.id, choice: .once)
        try await waitUntil {
            if case .sent(.once) = state.approvalStatus(for: message.id) { return true }
            return false
        }
        #expect(client.approvalIDs == [.int(42), .int(42)])
    }

    @Test func corruptedSnapshotIsNotOverwrittenByANewSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sessions.json")
        let original = Data("not a valid snapshot".utf8)
        try original.write(to: file)

        let store = PersistentSessionStore(directoryURL: directory)
        await #expect(throws: DecodingError.self) {
            try await store.createSession(title: "New")
        }
        #expect(try Data(contentsOf: file) == original)
    }

    private func makeAgent(_ name: String) -> Agent {
        Agent(
            brand: .hermes, displayName: name, order: 1,
            configuration: GatewayConfiguration(displayName: name, host: "gateway.example.invalid")
        )
    }

    private func makeSession(agent: Agent, remoteID: String) -> Session {
        let now = Date()
        return Session(id: UUID(), title: "Session", createdAt: now, updatedAt: now, agentID: agent.id, remoteID: remoteID)
    }

    private func makeState(
        client: StubGateway, agents: [Agent], sessions: [Session], store: any SessionStore = InMemorySessionStore()
    ) -> AppState {
        AppState(
            gateway: client, sessionStore: store, agents: agents, sessions: sessions,
            selectedSessionID: sessions.first?.id, connectionState: client.currentState, screen: .chat
        )
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while !predicate() {
            try #require(clock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class StubGateway: @preconcurrency GatewayClient {
    var currentState: GatewayConnectionState = .connected(GatewayInfo())
    var replayEpoch: String? { nil }
    var rejectApproval = false
    var rejectPrompt = false
    var holdPromptResponse = false
    private(set) var pendingPromptResponse: CheckedContinuation<JSONValue, Never>?
    var interruptResult: JSONValue = .object(["status": .string("interrupted")])
    var historyRPC: ((String, JSONValue?) throws -> JSONValue?)?
    private(set) var submittedSessionIDs: [String] = []
    private(set) var createdSessions = 0
    private(set) var approvalIDs: [JSONRPCID] = []
    private(set) var interruptedSessionIDs: [String] = []
    private(set) var connectedConfigurations: [GatewayConfiguration] = []
    private var eventHandler: (@Sendable (GatewayEventEnvelope) -> Void)?
    private var requestHandler: (@Sendable (ServerRequest) -> Void)?

    func connect(to configuration: GatewayConfiguration) async throws {
        connectedConfigurations.append(configuration)
    }
    func disconnect() async {}
    func send(_ payload: Data) async throws {}

    func observeState(_ handler: @escaping @Sendable (GatewayConnectionState) -> Void) -> any GatewayStateObservation {
        handler(currentState)
        return Observation()
    }

    func observeEvents(_ handler: @escaping @Sendable (GatewayEventEnvelope) -> Void) -> any GatewayStateObservation {
        eventHandler = handler
        return Observation()
    }

    func observeServerRequests(_ handler: @escaping @Sendable (ServerRequest) -> Void) -> any GatewayStateObservation {
        requestHandler = handler
        return Observation()
    }

    func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        if let result = try historyRPC?(method, params) { return result }
        if method == GatewayMethod.promptSubmit {
            if let id = params?["session_id"]?.stringValue { submittedSessionIDs.append(id) }
            if rejectPrompt { throw GatewayError.unreachable("Prompt rejected") }
            if holdPromptResponse {
                return await withCheckedContinuation { pendingPromptResponse = $0 }
            }
        }
        if method == GatewayMethod.sessionInterrupt, let id = params?["session_id"]?.stringValue {
            interruptedSessionIDs.append(id)
            return interruptResult
        }
        if method == GatewayMethod.sessionCreate {
            createdSessions += 1
            return .object(["session_id": .string("created-session")])
        }
        if method == GatewayMethod.sessionList { return .object(["sessions": .array([])]) }
        return .object([:])
    }

    func respond(to requestID: JSONRPCID, choice: ApprovalChoice) async throws {
        approvalIDs.append(requestID)
        if rejectApproval { throw GatewayError.unreachable("Unavailable") }
    }

    func emit(_ event: GatewayEventEnvelope) { eventHandler?(event) }
    func emit(_ request: ServerRequest) { requestHandler?(request) }

    func releasePromptResponse() {
        pendingPromptResponse?.resume(returning: .object([:]))
        pendingPromptResponse = nil
    }

    private final class Observation: GatewayStateObservation {
        func cancel() {}
    }
}

@MainActor
private final class StubCredentialStore: GatewayCredentialStore {
    private(set) var entries: [UUID: GatewayCredentials] = [:]
    private(set) var loadedAgentIDs: [UUID] = []

    func load(for agentID: UUID) throws -> GatewayCredentials? {
        loadedAgentIDs.append(agentID)
        return entries[agentID]
    }

    func save(_ credentials: GatewayCredentials, for agentID: UUID) throws {
        entries[agentID] = credentials
    }
}

private final class AuthenticationHTTPStub: GatewayHTTPPerforming {
    private let provider: String
    private(set) var requests: [URLRequest] = []

    init(provider: String) {
        self.provider = provider
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        requests.append(request)
        let body: Data
        let code: Int
        switch url.path {
        case "/api/status":
            body = try JSONEncoder().encode(GatewayStatus(authRequired: true, authProviders: [provider]))
            code = 200
        case "/api/auth/ws-ticket" where provider != "session-token":
            body = try JSONEncoder().encode(WsTicket(ticket: "one-time-ticket", ttlSeconds: 30))
            code = 200
        default:
            body = Data()
            code = 401
        }
        let response = try #require(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
        return (body, response)
    }
}

private final class ReadyWebSocket: GatewayWebSocketTasking {
    private var sentReady = false

    func resume() {}
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {}
    func send(_ message: URLSessionWebSocketTask.Message) async throws {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !sentReady {
            sentReady = true
            return .string(#"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}}"#)
        }
        try await Task.sleep(for: .seconds(30))
        throw GatewayError.timeout
    }
}
