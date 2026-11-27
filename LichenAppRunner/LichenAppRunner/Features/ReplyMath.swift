import Foundation

enum ReplyMath {
    private static let namedOperator = try? NSRegularExpression(
        pattern: #"(?<!\\)\\operatorname\*?[ \t]*\{([A-Za-z]+(?: [A-Za-z]+)*)\}"#
    )

    private static let manualDelimiterSize = try? NSRegularExpression(
        pattern: #"(?<!\\)\\(?:big|Big|bigg|Bigg)[lmr]?[ \t]*(?=\\[{}|]|[()|\[\].])"#
    )
    private static let stackedCommands = try? NSRegularExpression(
        pattern: #"(?<!\\)\\(substack|xrightarrow|xleftarrow|overset)(?![A-Za-z])"#
    )
    private static let equation = try? NSRegularExpression(
        pattern: #"\A\s*\\begin\{equation(\*?)\}([\s\S]+)\\end\{equation\1\}\s*\z"#
    )
    private static let textFraction = try? NSRegularExpression(
        pattern: #"(?<!\\)\\tfrac(?![A-Za-z])"#
    )
    private static let nativeText = try? NSRegularExpression(
        pattern: #"(?<!\\)\\(?:text\{([^{}\\]*[^\x00-\x7F][^{}\\]*)\}|blacksquare(?![A-Za-z]))"#
    )

    // Match Markdown code before looking for formulas so that examples stay literal.
    private static let markdownRegions = try? NSRegularExpression(
        pattern: [
            #"(?ms:^[ \t]{0,3}(`{3,}|~{3,})[^\r\n]*(?:\r?\n.*?(?:^[ \t]{0,3}\1[`~]*[ \t]*(?=\r?$)|\z)|\z))"#,
            #"(?s:(?<!`)(`+)(?!`).*?(?<!`)\2(?!`))"#,
            #"(?<!\\)\$\$([\s\S]+?)(?<!\\)\$\$"#,
            #"(?<!\\)\\\[([\s\S]+?)(?<!\\)\\\]"#,
            #"(?<!\\)\\\(([^\r\n]+?)(?<!\\)\\\)"#,
            #"(?<![\\\d$])\$(?=\S)([^\r\n$\x60]+?)(?:(?<=\S)|(?<=\\ ))(?<!\\)\$(?![\d$])"#
        ].joined(separator: "|")
    )

    private static let standaloneMath = try? NSRegularExpression(
        pattern: #"\A\\[A-Za-z][A-Za-z0-9\\{}*_^=+.,;()\[\]/|<>-]*\z"#
    )

    static func compatibleMarkdown(_ markdown: String) -> String {
        guard let markdownRegions else { return markdown }
        guard markdown.contains("$") || markdown.contains(#"\("#)
            || markdown.contains(#"\["#) || markdown.contains(#"\operatorname"#) else { return markdown }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if standaloneMath?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            let formula = normalizeOperators(in: trimmed)
            if formula != trimmed { return #"\("# + formula + #"\)"# }
        }

        var result = markdown
        let regions = markdownRegions.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        for region in regions.reversed() {
            // The first two captures are code; the remaining captures hold formula bodies.
            guard let body = (3..<region.numberOfRanges).first(where: {
                region.range(at: $0).location != NSNotFound
            }), let range = Range(region.range(at: body), in: result) else { continue }
            let formula = compatibleFormula(String(result[range]))
            if let whole = Range(region.range, in: result),
               let text = formattedText(in: formula, display: body == 3 || body == 4) {
                result.replaceSubrange(whole, with: text)
            } else if body == 6, let whole = Range(region.range, in: result) {
                // Protect inline LaTeX from Markdown emphasis before the renderer parses it.
                result.replaceSubrange(whole, with: inline(formula))
            } else {
                result.replaceSubrange(range, with: formula)
            }
        }
        return result
    }

    private static func compatibleFormula(_ formula: String) -> String {
        // The Markdown delimiters already establish display math; SwiftMath
        // does not understand the outer equation environment.
        let bounds = NSRange(formula.startIndex..., in: formula)
        let body = equation?.firstMatch(in: formula, range: bounds)
            .flatMap { Range($0.range(at: 2), in: formula) }
        var result = normalizeOperators(in: body.map { String(formula[$0]) } ?? formula)
        if let manualDelimiterSize {
            let range = NSRange(result.startIndex..., in: result)
            result = manualDelimiterSize.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let textFraction {
            let range = NSRange(result.startIndex..., in: result)
            result = textFraction.stringByReplacingMatches(in: result, range: range, withTemplate: #"\\frac"#)
        }
        replaceStackedCommands(in: &result)
        return result
    }

    private static func replaceStackedCommands(in formula: inout String) {
        guard let stackedCommands else { return }
        let bounds = NSRange(formula.startIndex..., in: formula)
        for match in stackedCommands.matches(in: formula, range: bounds).reversed() {
            guard let command = Range(match.range(at: 1), in: formula),
                  let whole = Range(match.range, in: formula) else { continue }
            let name = formula[command]
            let isArrow = name == "xrightarrow" || name == "xleftarrow"
            let below = isArrow ? argument(in: formula, from: whole.upperBound, opening: "[") : nil
            guard let above = argument(in: formula, from: below?.end ?? whole.upperBound) else { continue }

            let rows: String
            var end = above.end
            if isArrow {
                let shaft = name == "xrightarrow" ? #"\longrightarrow"# : #"\longleftarrow"#
                rows = labeledRows(above: above.text, base: shaft, below: below?.text)
            } else if name == "overset" {
                guard let base = argument(in: formula, from: end) else { continue }
                rows = labeledRows(above: above.text, base: base.text)
                end = base.end
            } else {
                rows = String(above.text)
            }
            formula.replaceSubrange(whole.lowerBound..<end, with: #"\begin{matrix}"# + rows + #"\end{matrix}"#)
        }
    }

    private static func labeledRows(above: Substring, base: some StringProtocol, below: Substring? = nil) -> String {
        var rows = [#"\scriptstyle "# + above, String(base)]
        if let below { rows.append(#"\scriptstyle "# + below) }
        return rows.joined(separator: #"\\"#)
    }

    private static func argument(
        in text: String, from start: String.Index, opening: Character = "{"
    ) -> (text: Substring, end: String.Index)? {
        guard let opener = text[start...].firstIndex(where: { !$0.isWhitespace }),
              text[opener] == opening else { return nil }
        let bodyStart = text.index(after: opener)
        var delimiters: [Character] = [opening == "[" ? "]" : "}"]
        var escaped = false
        for index in text.indices[bodyStart...] {
            let character = text[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
            } else if character == "{" {
                delimiters.append("}")
            } else if character == "[", delimiters.last == "]" {
                delimiters.append("]")
            } else if character == delimiters.last {
                delimiters.removeLast()
                if delimiters.isEmpty { return (text[bodyStart..<index], text.index(after: index)) }
            }
        }
        return nil
    }

    private static func formattedText(in formula: String, display: Bool) -> String? {
        guard let nativeText else { return nil }
        let matches = nativeText.matches(in: formula, range: NSRange(formula.startIndex..., in: formula))
        var pieces: [String] = []
        var start = formula.startIndex
        for match in matches {
            guard let range = Range(match.range, in: formula),
                  isTopLevel(formula[start..<range.lowerBound]) else { continue }
            appendFormula(formula[start..<range.lowerBound], display: display, to: &pieces)
            if let body = Range(match.range(at: 1), in: formula) {
                pieces.append(String(formula[body]))
            } else {
                pieces.append("■")
            }
            start = range.upperBound
        }
        guard !pieces.isEmpty else { return nil }
        appendFormula(formula[start...], display: display, to: &pieces)
        return pieces.joined(separator: " ")
    }

    private static func isTopLevel(_ prefix: Substring) -> Bool {
        // Ignore escaped braces and avoid splitting an open group or sized delimiter.
        var depth = 0
        var escaped = false
        for character in prefix {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" { escaped = true }
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
        }
        let leftCount = prefix.components(separatedBy: #"\left"#).count
        let rightCount = prefix.components(separatedBy: #"\right"#).count
        return depth == 0 && leftCount == rightCount
    }

    private static func appendFormula(_ source: Substring, display: Bool, to pieces: inout [String]) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pieces.append(inline(display ? #"\displaystyle "# + trimmed : trimmed))
        }
    }

    private static func inline(_ formula: String) -> String {
        #"\("# + formula + #"\)"#
    }

    private static func normalizeOperators(in formula: String) -> String {
        guard let namedOperator else { return formula }
        var result = formula
        let matches = namedOperator.matches(in: formula, range: NSRange(formula.startIndex..., in: formula))
        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: result),
                  let range = Range(match.range, in: result) else { continue }
            // SwiftMath understands upright text (\\mathrm), but not \\operatorname.
            let name = result[nameRange].replacingOccurrences(of: " ", with: #"\ "#)
            result.replaceSubrange(range, with: #"\mathrm{"# + name + "}")
        }
        return result
    }
}
