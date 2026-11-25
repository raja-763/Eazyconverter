import Foundation

/// Reads Markdown and plain text. Plain text without Markdown marks simply
/// becomes paragraphs split at blank lines.
enum MarkdownReader {
    static func read(_ data: Data, fileName: String) -> DocumentModel {
        let text = String(decoding: data, as: UTF8.self)
        var model = read(text: text, fileName: fileName)
        if model.blocks.isEmpty { model.notes.append("This file has no text.") }
        return model
    }

    static func read(text: String, fileName: String) -> DocumentModel {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [Block] = []
        var para: [String] = []
        var code: [String]?
        var table: [[String]] = []
        var counters: [Int: Int] = [:]

        func flushPara() {
            let t = para.joined(separator: " ").collapsedWhitespace
            if !t.isEmpty { blocks.append(Block(kind: .paragraph, text: stripInline(t))) }
            para = []
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let width = table.map(\.count).max() ?? 0
            let rows = table.map { $0 + Array(repeating: "", count: width - $0.count) }
            blocks.append(Block(kind: .table(rows: rows, hasHeaderRow: rows.count > 1), text: ""))
            table = []
        }

        for line in lines {
            if code != nil {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(Block(kind: .code, text: code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(line)
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") { flushPara(); flushTable(); code = []; continue }

            if trimmed.hasPrefix("|") {
                flushPara()
                let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { stripInline($0.trimmingCharacters(in: .whitespaces)) }
                // Skip the |---|---| divider row.
                let isDivider = cells.allSatisfy { cell in
                    !cell.isEmpty && cell.allSatisfy { ch in "-:".contains(ch) }
                }
                if !isDivider { table.append(cells) }
                continue
            }
            flushTable()

            if trimmed.isEmpty { flushPara(); counters = [:]; continue }

            if let r = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushPara()
                let level = trimmed[r].filter { $0 == "#" }.count
                let heading = String(trimmed[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                blocks.append(Block(kind: .heading(level: level), text: stripInline(heading)))
                continue
            }

            let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let depth = min(indent / 2, 5)
            if let r = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushPara()
                blocks.append(Block(kind: .listItem(ordered: false, number: 0, depth: depth),
                                    text: stripInline(String(trimmed[r.upperBound...]))))
                continue
            }
            if let r = trimmed.range(of: #"^\d{1,4}[.)]\s+"#, options: .regularExpression) {
                flushPara()
                counters[depth, default: 0] += 1
                for d in counters.keys where d > depth { counters[d] = 0 }
                blocks.append(Block(kind: .listItem(ordered: true, number: counters[depth] ?? 1, depth: depth),
                                    text: stripInline(String(trimmed[r.upperBound...]))))
                continue
            }
            para.append(trimmed)
        }
        if let c = code { blocks.append(Block(kind: .code, text: c.joined(separator: "\n"))) }
        flushPara()
        flushTable()

        let title = blocks.first(where: \.isHeading)?.text ?? (fileName as NSString).deletingPathExtension
        return DocumentModel(title: title, sourceFileName: fileName, blocks: blocks)
    }

    /// Removes **bold**, _italic_, `code` and [link](url) marks so they aren't read aloud.
    static func stripInline(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "[Image: $1]", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\*\*|__)(.+?)\1"#, with: "$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<![\w*])[*_](?!\s)(.+?)(?<!\s)[*_](?![\w*])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        return t
    }
}
