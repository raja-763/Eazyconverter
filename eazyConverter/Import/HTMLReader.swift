import Foundation

/// A forgiving HTML reader that keeps headings, lists, tables, code and image alt text.
/// It never runs scripts, loads remote content or opens links.
enum HTMLReader {
    static func read(_ data: Data, fileName: String) -> DocumentModel {
        let html = String(decoding: data, as: UTF8.self)
        return read(html: html, fileName: fileName)
    }

    static func read(html raw: String, fileName: String) -> DocumentModel {
        var html = raw
        // Remove parts that are never content.
        for pattern in [#"<!--[\s\S]*?-->"#, #"<script\b[\s\S]*?</script\s*>"#,
                        #"<style\b[\s\S]*?</style\s*>"#, #"<noscript\b[\s\S]*?</noscript\s*>"#,
                        #"<template\b[\s\S]*?</template\s*>"#] {
            html = html.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        var title = (fileName as NSString).deletingPathExtension
        if let r = html.range(of: #"<title[^>]*>([\s\S]*?)</title\s*>"#, options: [.regularExpression, .caseInsensitive]) {
            let inner = html[r].replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let t = decodeEntities(inner).collapsedWhitespace
            if !t.isEmpty { title = t }
            html.removeSubrange(r)
        }

        var parser = State()
        let tag = try! NSRegularExpression(pattern: #"<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>"#)
        let ns = html as NSString
        var cursor = 0
        for match in tag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                parser.text(decodeEntities(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let closing = ns.substring(with: match.range(at: 1)) == "/"
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let attrs = ns.substring(with: match.range(at: 3))
            parser.tag(name, closing: closing, attributes: attrs)
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length {
            parser.text(decodeEntities(ns.substring(from: cursor)))
        }
        parser.flush()

        if title.isEmpty, let h = parser.blocks.first(where: \.isHeading) { title = h.text }
        return DocumentModel(title: title, sourceFileName: fileName, blocks: parser.blocks)
    }

    private struct State {
        var blocks: [Block] = []
        var buffer = ""
        var kind: BlockKind = .paragraph
        var lists: [(ordered: Bool, count: Int)] = []
        var inPre = false
        var tableDepth = 0
        var rows: [[String]] = []
        var cell: String?
        var sawHeaderCell = false

        mutating func text(_ s: String) {
            if tableDepth > 0 {
                if cell != nil { cell! += s }
                return
            }
            buffer += s
        }

        mutating func flush() {
            let t = inPre ? buffer.trimmingCharacters(in: .newlines) : buffer.collapsedWhitespace
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(Block(kind: kind, text: t))
            }
            buffer = ""
            kind = .paragraph
        }

        mutating func tag(_ name: String, closing: Bool, attributes: String) {
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                guard tableDepth == 0 else { return }
                flush()
                if !closing { kind = .heading(level: Int(String(name.last!)) ?? 2) }
            case "ul", "ol":
                guard tableDepth == 0 else { return }
                flush()
                if closing { _ = lists.popLast() } else { lists.append((name == "ol", 0)) }
            case "li":
                guard tableDepth == 0 else { return }
                flush()
                if !closing {
                    if lists.isEmpty { lists.append((false, 0)) }
                    lists[lists.count - 1].count += 1
                    let l = lists[lists.count - 1]
                    kind = .listItem(ordered: l.ordered, number: l.count, depth: min(lists.count - 1, 5))
                }
            case "pre":
                guard tableDepth == 0 else { return }
                flush()
                inPre = !closing
                if !closing { kind = .code }
            case "table":
                if closing {
                    tableDepth = max(0, tableDepth - 1)
                    if tableDepth == 0 {
                        let width = rows.map(\.count).max() ?? 0
                        let padded = rows.filter { !$0.isEmpty }.map { $0 + Array(repeating: "", count: width - $0.count) }
                        if !padded.isEmpty {
                            blocks.append(Block(kind: .table(rows: padded, hasHeaderRow: sawHeaderCell), text: ""))
                        }
                    }
                } else {
                    if tableDepth == 0 { flush(); rows = []; sawHeaderCell = false }
                    tableDepth += 1
                }
            case "tr":
                if tableDepth == 1, !closing { rows.append([]) }
            case "td", "th":
                guard tableDepth == 1 else { return }
                if closing {
                    if let c = cell, !rows.isEmpty { rows[rows.count - 1].append(c.collapsedWhitespace) }
                    cell = nil
                } else {
                    if name == "th", rows.count == 1 { sawHeaderCell = true }
                    cell = ""
                }
            case "br":
                text(inPre ? "\n" : " ")
            case "img":
                if let alt = attribute("alt", in: attributes), !alt.isEmpty {
                    text(" [Image: \(alt)] ")
                }
            case "p", "div", "section", "article", "header", "footer", "main", "aside", "nav",
                 "blockquote", "figure", "figcaption", "dt", "dd", "hr", "address", "body":
                if tableDepth > 0 { text(" ") } else { flush() }
            default:
                break
            }
        }

        private func attribute(_ name: String, in attrs: String) -> String? {
            let pattern = name + #"\s*=\s*("([^"]*)"|'([^']*)')"#
            guard let r = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = r.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)) else { return nil }
            for i in [2, 3] {
                if let range = Range(m.range(at: i), in: attrs) { return HTMLReader.decodeEntities(String(attrs[range])) }
            }
            return nil
        }
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
                                       "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…",
                                       "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
                                       "copy": "©", "reg": "®", "trade": "™", "bull": "•"]
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
        let ns = s as NSString
        var result = ""
        var cursor = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let code = ns.substring(with: m.range(at: 1))
            var replacement: String?
            if code.hasPrefix("#x") || code.hasPrefix("#X"), let v = UInt32(code.dropFirst(2), radix: 16) {
                replacement = Unicode.Scalar(v).map { String(Character($0)) }
            } else if code.hasPrefix("#"), let v = UInt32(code.dropFirst()) {
                replacement = Unicode.Scalar(v).map { String(Character($0)) }
            } else {
                replacement = named[code.lowercased()]
            }
            result += replacement ?? ns.substring(with: m.range)
            cursor = NSMaxRange(m.range)
        }
        result += ns.substring(from: cursor)
        return result
    }
}
