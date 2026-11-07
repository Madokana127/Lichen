import SwiftUI
import LichenCore

/// 网关页（占位），只展示固定的未连接状态。
struct GatewayView: View {
    // TODO: 后续任务注入 GatewayClient，订阅 GatewayConnectionState 变化并展示真实状态。
    // TODO: 后续任务提供连接 / 断开操作。
    private let state: GatewayConnectionState = .disconnected

    var body: some View {
        NavigationStack {
            Form {
                Section("连接状态") {
                    LabeledContent("当前状态", value: stateDescription)
                }
            }
            .navigationTitle("网关")
        }
    }

    private var stateDescription: String {
        switch state {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .failed:
            return "连接失败"
        }
    }
}
