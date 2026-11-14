import XCTest
import Foundation
@testable import LichenCore

final class TerminalBufferTests: XCTestCase {
    func testPlainTextAndNewlines() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("hello\nworld")

        XCTAssertEqual(buffer.lines, ["hello", "world"])
        XCTAssertEqual(buffer.snapshot, "hello\nworld")
    }

    func testCarriageReturnOverwritesLine() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("abc\rX")
        XCTAssertEqual(buffer.snapshot, "Xbc")

        buffer.append("\rabcdef\rXY")
        XCTAssertEqual(buffer.lines.last, "XYcdef")
    }

    func testCRLFProducesCleanLines() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("a\r\nb\r\n")

        XCTAssertEqual(buffer.lines, ["a", "b", ""])
        XCTAssertEqual(buffer.snapshot, "a\nb\n")
    }

    func testBackspaceMovesCursorLeft() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("abc\u{08}d")

        XCTAssertEqual(buffer.snapshot, "abd")
    }

    func testSGRColorCodesAreStripped() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("\u{1B}[1;31mred\u{1B}[0m plain")

        XCTAssertEqual(buffer.snapshot, "red plain")
    }

    func testEraseInLine() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("hello\u{1B}[2K")

        XCTAssertEqual(buffer.lines, [""])
        XCTAssertEqual(buffer.snapshot, "")
    }

    func testEraseInDisplay() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("one\ntwo\u{1B}[2J")

        XCTAssertEqual(buffer.lines, [""])
        XCTAssertEqual(buffer.snapshot, "")
    }

    func testCursorMovementAndPositioning() {
        let buffer = BoundedTerminalBuffer()
        buffer.append("abc\u{1B}[2DX")
        XCTAssertEqual(buffer.snapshot, "aXc")

        let positioned = BoundedTerminalBuffer()
        positioned.append("\u{1B}[2;3HX")
        XCTAssertEqual(positioned.lines, ["", "  X"])
    }

    func testIncompleteEscapeSequenceAcrossAppends() async {
        let buffer = BoundedTerminalBuffer()
        await buffer.append(Data("\u{1B}[3".utf8))
        await buffer.append(Data("1mred".utf8))

        XCTAssertEqual(buffer.snapshot, "red")
    }

    func testUTF8SequenceSplitAcrossAppends() async {
        let buffer = BoundedTerminalBuffer()
        await buffer.append(Data([0xE4, 0xBD]))
        await buffer.append(Data([0xA0]))

        XCTAssertEqual(buffer.snapshot, "你")
    }

    func testInvalidUTF8UsesReplacementCharacter() async {
        let buffer = BoundedTerminalBuffer()
        await buffer.append(Data([0xFF, 0x41]))

        XCTAssertEqual(buffer.snapshot, "\u{FFFD}A")
    }

    func testCapacityDropsOldestLines() {
        let buffer = BoundedTerminalBuffer(capacity: 2)
        buffer.append("a\nb\nc")

        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.lines, ["b", "c"])
        XCTAssertEqual(buffer.snapshot, "b\nc")
    }

    func testClearResetsState() async {
        let buffer = BoundedTerminalBuffer()
        buffer.append("abc\u{1B}[3")
        await buffer.clear()

        XCTAssertEqual(buffer.lines, [""])
        XCTAssertEqual(buffer.snapshot, "")

        await buffer.append(Data("ok".utf8))
        XCTAssertEqual(buffer.snapshot, "ok")
    }
}
