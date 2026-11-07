import Foundation

/// 网关连接状态（占位）。
public enum GatewayConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error?)

    // TODO: 后续任务定义状态迁移规则、重连退避策略与错误分类。
}

extension GatewayConnectionState: Equatable {
    public static func == (lhs: GatewayConnectionState, rhs: GatewayConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case let (.failed(lhsError), .failed(rhsError)):
            // TODO: 后续任务定义错误等价语义；当前仅按描述文本比较以便占位测试。
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }
}
