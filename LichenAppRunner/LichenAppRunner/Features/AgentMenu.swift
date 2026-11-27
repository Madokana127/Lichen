import LichenCore
import SwiftUI

struct AgentMenu: View {
    @Environment(AppState.self) private var appState

    let source: ConnectSource
    let palette: ColorPalette

    var body: some View {
        Menu {
            ForEach(appState.agents) { agent in
                Button {
                    appState.selectAgent(agent)
                } label: {
                    if agent.id == appState.currentAgentID {
                        Label(agent.displayName, systemImage: "checkmark")
                    } else {
                        Text(agent.displayName)
                    }
                }
            }

            if appState.currentAgent != nil, !appState.isConnected {
                Button("连接当前 Agent", systemImage: "bolt") {
                    Task { await appState.connectSelectedAgent(from: source) }
                }
            }

            if appState.currentAgent != nil {
                Button("修改连接与令牌", systemImage: "key") {
                    appState.editConnection(from: source)
                }
            }

            Button("添加网关", systemImage: "plus") {
                appState.openConnect(from: source)
            }
        } label: {
            Image(systemName: appState.isConnected ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appState.isConnected ? palette.accent : palette.ink2)
                .frame(width: 36, height: 36)
                .conversationGlass(in: Circle(), fallback: palette.barGlass, border: palette.line)
        }
        .accessibilityLabel("Agent 与网关")
    }
}
