import Foundation

/// 网关断线重连退避策略。
///
/// 采用「指数上限 + full jitter」：第 n 次连续失败后的等待上限为
/// `min(cap, base * 2^(n-1))`，实际等待取 `[0, 上限)` 内的随机值。
/// 手工连接或连接稳定超过 `stableConnectionInterval` 后调用
/// `recordSuccess()` 将阶梯重置回起点。
public struct GatewayReconnectPolicy: Sendable {
    /// 首次退避上限（秒）。
    public let baseDelay: TimeInterval
    /// 退避上限封顶（秒）。
    public let maximumDelay: TimeInterval
    /// 连接稳定多久（秒）后重置阶梯。
    public let stableConnectionInterval: TimeInterval

    private let randomUnit: @Sendable () -> Double
    private var consecutiveFailures: Int

    public init(
        baseDelay: TimeInterval = 0.3,
        maximumDelay: TimeInterval = 15,
        stableConnectionInterval: TimeInterval = 5,
        randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.stableConnectionInterval = stableConnectionInterval
        self.randomUnit = randomUnit
        self.consecutiveFailures = 0
    }

    /// 当前连续失败次数。
    public var failureCount: Int {
        consecutiveFailures
    }

    /// 纯函数：给定连续失败次数计算下一次退避时长。
    ///
    /// `afterFailureCount` 为 1 表示刚发生第一次失败；指数部分按
    /// `2^(afterFailureCount - 1)` 增长，并用注入的随机源做 full jitter。
    public func nextDelay(afterFailureCount failureCount: Int) -> TimeInterval {
        let attempt = max(0, failureCount - 1)
        // 防止指数在极端次数下溢出；cap 会在下面兜住结果。
        let exponent = min(attempt, 30)
        let ceiling = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let rawUnit = randomUnit()
        let unit = rawUnit.isFinite ? min(max(rawUnit, 0), 1) : 0
        return ceiling * unit
    }

    /// 记录一次连接失败，推进退避阶梯。
    public mutating func recordFailure() {
        consecutiveFailures = min(consecutiveFailures + 1, 31)
    }

    /// 记录一次稳定连接，重置退避阶梯。
    public mutating func recordSuccess() {
        consecutiveFailures = 0
    }

    /// 显式重置阶梯，用于新的手工连接。
    public mutating func reset() {
        consecutiveFailures = 0
    }
}
