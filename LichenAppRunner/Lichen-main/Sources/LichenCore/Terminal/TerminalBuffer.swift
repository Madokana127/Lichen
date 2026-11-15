import Foundation

/// 终端输出缓冲区接口。
public protocol TerminalBuffer: Sendable {
    /// 当前输出快照，行之间以 `\n` 连接。
    var snapshot: String { get }

    /// 当前保留的全部行。
    var lines: [String] { get }

    /// 最大保留行数。
    var capacity: Int { get }

    /// 追加一段普通文本。
    func append(_ chunk: String)

    /// 追加一段原始输出字节。
    func append(_ data: Data) async

    /// 清空缓冲与未完成的转义/UTF-8 状态。
    func clear() async
}

/// 按行数限制容量的终端缓冲区，带基础 ANSI CSI 解析。
///
/// 解析规则：
/// - SGR（`m`）只记录颜色/粗体状态，不把颜色码写入输出；
/// - `K` / `J` 清行/清屏，`A`/`B`/`C`/`D` 移动光标，`H` / `f` 定位；
/// - `\r` 回到行首覆盖，`\n` 换行，`\u{08}` 退格；
/// - 不完整的转义序列与 UTF-8 多字节序列跨 `append` 保留。
public actor BoundedTerminalBuffer: TerminalBuffer {
    private nonisolated let state: TerminalBufferState

    public init(capacity: Int = 2_000) {
        state = TerminalBufferState(capacity: capacity)
    }

    public nonisolated var snapshot: String {
        state.snapshot
    }

    public nonisolated var lines: [String] {
        state.lines
    }

    public nonisolated var capacity: Int {
        state.capacity
    }

    public nonisolated func append(_ chunk: String) {
        state.append(Array(chunk.utf8))
    }

    public func append(_ data: Data) async {
        state.append([UInt8](data))
    }

    public func clear() async {
        state.clear()
    }
}

// MARK: - 字节流状态机

/// 由锁保护的终端状态。
///
/// `BoundedTerminalBuffer` 是 actor，但 `snapshot` / `lines` 等只读接口需要同步访问；
/// 因此实际状态放在线程安全的引用类型里，actor 负责线程模型，锁负责状态一致性。
private final class TerminalBufferState: @unchecked Sendable {
    let capacity: Int

    private let lock = NSLock()
    private var rows: [[Character]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var pendingUTF8: [UInt8] = []
    private var escapeState: EscapeState = .text
    private var csiBuffer: [UInt8] = []
    private var sgr = SGRState()

    private enum EscapeState {
        case text
        case escape
        case escapeIntermediate
        case csi
        case stringControl
        case stringEscape
    }

    private struct SGRState {
        var bold = false
        var dim = false
        var italic = false
        var underline = false
        var foreground: Int?
        var background: Int?
    }

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var snapshot: String {
        withLock {
            rows.map { String($0) }.joined(separator: "\n")
        }
    }

    var lines: [String] {
        withLock {
            rows.map { String($0) }
        }
    }

    func append(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        withLock {
            ingest(bytes)
        }
    }

    func clear() {
        withLock {
            rows = [[]]
            cursorRow = 0
            cursorColumn = 0
            pendingUTF8.removeAll(keepingCapacity: true)
            escapeState = .text
            csiBuffer.removeAll(keepingCapacity: true)
            sgr = SGRState()
        }
    }
}

// MARK: - 解析

private extension TerminalBufferState {
    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func ingest(_ newBytes: [UInt8]) {
        var bytes = newBytes
        if !pendingUTF8.isEmpty {
            bytes = pendingUTF8 + bytes
            pendingUTF8.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]

            switch escapeState {
            case .text:
                if byte == 0x1B {
                    escapeState = .escape
                    index += 1
                } else if byte < 0x80 {
                    handleASCII(byte)
                    index += 1
                } else {
                    let (text, consumed) = consumeUTF8(bytes, at: index)
                    guard let text = text else {
                        pendingUTF8 = Array(bytes[index...])
                        return
                    }
                    write(text)
                    index += consumed
                }

            case .escape:
                if byte == 0x1B {
                    // 连续 ESC：保持等待新序列。
                    escapeState = .escape
                } else if byte == 0x5B {
                    csiBuffer.removeAll(keepingCapacity: true)
                    escapeState = .csi
                } else if byte == 0x5D || byte == 0x50 || byte == 0x58
                    || byte == 0x5E || byte == 0x5F {
                    escapeState = .stringControl
                } else if (0x20...0x2F).contains(byte) {
                    escapeState = .escapeIntermediate
                } else {
                    escapeState = .text
                }
                index += 1

            case .escapeIntermediate:
                if (0x30...0x7E).contains(byte) {
                    escapeState = .text
                }
                index += 1

            case .csi:
                if (0x40...0x7E).contains(byte) {
                    csiBuffer.append(byte)
                    handleCSI()
                    csiBuffer.removeAll(keepingCapacity: true)
                    escapeState = .text
                } else if byte == 0x1B {
                    csiBuffer.removeAll(keepingCapacity: true)
                    escapeState = .escape
                } else {
                    csiBuffer.append(byte)
                    if csiBuffer.count > 512 {
                        csiBuffer.removeAll(keepingCapacity: true)
                        escapeState = .text
                    }
                }
                index += 1

            case .stringControl:
                if byte == 0x07 {
                    escapeState = .text
                } else if byte == 0x1B {
                    escapeState = .stringEscape
                }
                index += 1

            case .stringEscape:
                if byte == 0x5C {
                    escapeState = .text
                } else if byte != 0x1B {
                    escapeState = .stringControl
                }
                index += 1
            }
        }
    }

    func handleASCII(_ byte: UInt8) {
        switch byte {
        case 0x0A:
            lineFeed()
        case 0x0D:
            cursorColumn = 0
        case 0x08:
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            cursorColumn = ((cursorColumn / 8) + 1) * 8
        case 0x20...0x7E:
            write(String(decoding: [byte], as: UTF8.self))
        default:
            break
        }
    }

    /// 解码一个 UTF-8 标量；字节不足时返回 `(nil, 0)` 交由调用方保留。
    func consumeUTF8(_ bytes: [UInt8], at index: Int) -> (String?, Int) {
        let lead = bytes[index]
        let length: Int
        if lead & 0x80 == 0 {
            length = 1
        } else if lead & 0xE0 == 0xC0 {
            length = 2
        } else if lead & 0xF0 == 0xE0 {
            length = 3
        } else if lead & 0xF8 == 0xF0 {
            length = 4
        } else {
            return ("\u{FFFD}", 1)
        }

        if length == 1 {
            return (String(decoding: [lead], as: UTF8.self), 1)
        }

        let availableLength = min(length, bytes.count - index)
        let available = bytes[index..<(index + availableLength)]
        guard available.dropFirst().allSatisfy({ $0 & 0xC0 == 0x80 }) else {
            // 后续字节不是续字节，立即以替换字符兜底，避免永久等待更多输入。
            return ("\u{FFFD}", 1)
        }
        guard index + length <= bytes.count else {
            return (nil, 0)
        }

        let slice = bytes[index..<(index + length)]
        guard let decoded = String(bytes: slice, encoding: .utf8) else {
            return ("\u{FFFD}", 1)
        }
        return (decoded, length)
    }

    func write(_ text: String) {
        for character in text {
            ensureRow(cursorRow)
            var line = rows[cursorRow]
            if cursorColumn > line.count {
                line.append(contentsOf: Array(repeating: Character(" "), count: cursorColumn - line.count))
            }
            if cursorColumn < line.count {
                line[cursorColumn] = character
            } else {
                line.append(character)
            }
            rows[cursorRow] = line
            cursorColumn += 1
        }
    }

    func lineFeed() {
        if cursorRow + 1 < rows.count {
            cursorRow += 1
        } else {
            rows.append([])
            cursorRow = rows.count - 1
        }
        cursorColumn = 0
        trimToCapacity()
    }

    func ensureRow(_ index: Int) {
        while rows.count <= index {
            rows.append([])
        }
    }

    func trimToCapacity() {
        let excess = rows.count - capacity
        guard excess > 0 else { return }
        rows.removeFirst(excess)
        cursorRow = max(0, cursorRow - excess)
    }

    // MARK: CSI

    func handleCSI() {
        guard let finalByte = csiBuffer.last else { return }
        let numericBytes = csiBuffer.dropLast().filter {
            ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x3B
        }
        let spec = String(decoding: numericBytes, as: UTF8.self)
        let parameters = spec.isEmpty
            ? []
            : spec.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }

        switch finalByte {
        case 0x6D: // m — SGR
            applySGR(parameters)
        case 0x4B: // K — erase in line
            eraseInLine(parameters.first ?? 0)
        case 0x4A: // J — erase in display
            eraseInDisplay(parameters.first ?? 0)
        case 0x41: // A — cursor up
            moveRow(by: -(clampedCount(parameters.first)))
        case 0x42: // B — cursor down
            moveRow(by: clampedCount(parameters.first))
        case 0x43: // C — cursor right
            cursorColumn = min(cursorColumn + clampedCount(parameters.first), 10_000)
        case 0x44: // D — cursor left
            cursorColumn = max(0, cursorColumn - clampedCount(parameters.first))
        case 0x48, 0x66: // H / f — 定位
            moveRowTo(parameters.first ?? 1)
            let column = parameters.count > 1 ? parameters[1] : 1
            cursorColumn = min(max(column - 1, 0), 10_000)
        default:
            break
        }
    }

    func clampedCount(_ value: Int?) -> Int {
        min(max(value ?? 1, 1), 10_000)
    }

    func moveRow(by delta: Int) {
        let target = min(max(cursorRow + delta, 0), capacity - 1)
        ensureRow(target)
        cursorRow = target
    }

    func moveRowTo(_ oneBasedRow: Int) {
        let target = min(max(oneBasedRow - 1, 0), capacity - 1)
        ensureRow(target)
        cursorRow = target
    }

    func eraseInLine(_ mode: Int) {
        ensureRow(cursorRow)
        var line = rows[cursorRow]
        switch mode {
        case 1:
            let upper = min(cursorColumn + 1, line.count)
            if upper > 0 {
                for index in 0..<upper {
                    line[index] = Character(" ")
                }
            }
        case 2:
            line = []
        default:
            if cursorColumn < line.count {
                line.removeSubrange(cursorColumn..<line.count)
            }
        }
        rows[cursorRow] = line
    }

    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 1:
            let upper = min(cursorRow, rows.count)
            if upper > 0 {
                for index in 0..<upper {
                    rows[index] = []
                }
            }
            eraseInLine(1)
        case 2, 3:
            rows = [[]]
            cursorRow = 0
            cursorColumn = 0
        default:
            eraseInLine(0)
            if cursorRow + 1 < rows.count {
                rows.removeSubrange((cursorRow + 1)..<rows.count)
            }
        }
    }

    /// 记录 SGR 状态；颜色码不会写入输出。
    func applySGR(_ parameters: [Int]) {
        let values = parameters.isEmpty ? [0] : parameters
        var index = 0
        while index < values.count {
            let value = values[index]
            switch value {
            case 0:
                sgr = SGRState()
            case 1:
                sgr.bold = true
            case 2:
                sgr.dim = true
            case 3:
                sgr.italic = true
            case 4:
                sgr.underline = true
            case 22:
                sgr.bold = false
                sgr.dim = false
            case 23:
                sgr.italic = false
            case 24:
                sgr.underline = false
            case 30...37:
                sgr.foreground = value - 30
            case 90...97:
                sgr.foreground = value - 90 + 8
            case 39:
                sgr.foreground = nil
            case 40...47:
                sgr.background = value - 40
            case 100...107:
                sgr.background = value - 100 + 8
            case 49:
                sgr.background = nil
            case 38, 48:
                let isForeground = value == 38
                if index + 1 < values.count {
                    let mode = values[index + 1]
                    if mode == 5, index + 2 < values.count {
                        let color = values[index + 2]
                        if isForeground {
                            sgr.foreground = color
                        } else {
                            sgr.background = color
                        }
                        index += 2
                    } else if mode == 2, index + 4 < values.count {
                        if isForeground {
                            sgr.foreground = -1
                        } else {
                            sgr.background = -1
                        }
                        index += 4
                    } else {
                        index += 1
                    }
                }
            default:
                break
            }
            index += 1
        }
    }
}
