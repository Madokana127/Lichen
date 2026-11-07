import Foundation

/// 终端输出缓冲区抽象（占位），仅表示「未来承载终端输出」。
///
/// 本任务不实现终端仿真，也不解析 ANSI / 转义序列。
public protocol TerminalBuffer {
    /// 当前输出快照。
    // TODO: 后续任务确定存储形态（行数组 / 环形缓冲）与容量上限。
    var snapshot: String { get }

    // TODO: 后续任务实现 ANSI 转义序列解析与屏幕状态维护。
    mutating func append(_ chunk: String)
}
