import Foundation

/// 终端输出缓冲区接口。
public protocol TerminalBuffer: Sendable {
    /// 当前输出快照。
    var snapshot: String { get }

    /// 追加一段输出；实现方负责容量控制。
    mutating func append(_ chunk: String)
}

/// 按字符数限制容量的终端缓冲区。
///
/// 超出容量时从最早的内容开始裁剪，保证 `snapshot` 长度不超过 `capacity`。
public struct BoundedTerminalBuffer: TerminalBuffer, Sendable {
    public let capacity: Int
    private var chunks: [String] = []
    private var currentLength: Int = 0

    public init(capacity: Int = 64_000) {
        self.capacity = max(capacity, 1)
    }

    public var snapshot: String {
        chunks.joined()
    }

    public mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        chunks.append(chunk)
        currentLength += chunk.count

        while currentLength > capacity, !chunks.isEmpty {
            let overflow = currentLength - capacity
            let firstLength = chunks[0].count
            if firstLength <= overflow {
                currentLength -= firstLength
                chunks.removeFirst()
            } else {
                chunks[0] = String(chunks[0].dropFirst(overflow))
                currentLength -= overflow
            }
        }
    }
}
