import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case docx, pdf, html, txt, md

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docx: return "Word document"
        case .pdf: return "PDF"
        case .html: return "Web page (HTML)"
        case .txt: return "Plain text"
        case .md: return "Markdown"
        }
    }

    var contentType: UTType {
        switch self {
        case .docx: return .docx
        case .pdf: return .pdf
        case .html: return .html
        case .txt: return .plainText
        case .md: return .markdownText
        }
    }

    var fileExtension: String { rawValue }

    func data(for doc: DocumentModel) throws -> Data {
        switch self {
        case .txt: return Data(TextExporter.plain(doc).utf8)
        case .md: return Data(TextExporter.markdown(doc).utf8)
        case .html: return Data(HTMLExporter.html(doc).utf8)
        case .docx: return DocxWriter.docx(doc)
        case .pdf: return PDFWriter.pdf(doc)
        }
    }
}

enum TextExporter {
    static func plain(_ doc: DocumentModel) -> String {
        var out: [String] = []
        for b in doc.blocks {
            switch b.kind {
            case .heading(let level):
                // Underline top-level headings so structure survives in plain text.
                let rule = level == 1 ? "=" : (level == 2 ? "-" : "")
                out.append(rule.isEmpty ? b.text : b.text + "\n" + String(repeating: rule, count: min(b.text.count, 60)))
            case .pageMarker(let page):
                out.append("[Page \(page)]")
            default:
                if let line = doc.plainLine(for: b) { out.append(line) }
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    static func markdown(_ doc: DocumentModel) -> String {
        var out: [String] = []
        var previousWasList = false
        for b in doc.blocks {
            var piece: String
            var isList = false
            switch b.kind {
            case .heading(let level):
                piece = String(repeating: "#", count: level) + " " + b.text
            case .paragraph:
                piece = escapeMarkdown(b.text)
            case .listItem(let ordered, let number, let depth):
                piece = String(repeating: "  ", count: depth) + (ordered ? "\(number). " : "- ") + escapeMarkdown(b.text)
                isList = true
            case .table(let rows, let header):
                var lines: [String] = []
                let width = rows.first?.count ?? 0
                let body = header ? Array(rows.dropFirst()) : rows
                let head = header ? rows[0] : (1...max(width, 1)).map { "Column \($0)" }
                lines.append("| " + head.map(cellMD).joined(separator: " | ") + " |")
                lines.append("|" + Array(repeating: " --- |", count: head.count).joined())
                for r in body { lines.append("| " + r.map(cellMD).joined(separator: " | ") + " |") }
                piece = lines.joined(separator: "\n")
            case .code:
                piece = "```\n" + b.text + "\n```"
            case .pageMarker(let page):
                piece = "<!-- Page \(page) -->"
            }
            // Keep list items together so they form one list.
            if isList && previousWasList, let last = out.popLast() {
                out.append(last + "\n" + piece)
            } else {
                out.append(piece)
            }
            previousWasList = isList
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    private static func cellMD(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }

    private static func escapeMarkdown(_ s: String) -> String {
        // Stop text that starts like a heading or list from changing meaning.
        if let f = s.first, "#>".contains(f) { return "\\" + s }
        if s.range(of: #"^(\d+)[.)]\s"#, options: .regularExpression) != nil {
            return s.replacingOccurrences(of: #"^(\d+)([.)])"#, with: "$1\\\\$2", options: .regularExpression)
        }
        return s
    }
}

extension DocumentModel {
    func plainLine(for b: Block) -> String? {
        switch b.kind {
        case .pageMarker: return nil
        case .listItem(let ordered, let number, let depth):
            return String(repeating: "  ", count: depth) + (ordered ? "\(number). " : "• ") + b.text
        case .table(let rows, _):
            return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        default:
            return b.text
        }
    }
}

enum HTMLExporter {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func html(_ doc: DocumentModel) -> String {
        var body: [String] = []
        // Open lists, innermost last: (ordered, depth)
        var openLists: [(ordered: Bool, depth: Int)] = []
        var liOpen: [Bool] = []

        func closeLists(downTo depth: Int) {
            while let last = openLists.last, last.depth > depth {
                if liOpen.popLast() == true { body.append("</li>") }
                body.append(last.ordered ? "</ol>" : "</ul>")
                openLists.removeLast()
            }
        }

        for b in doc.blocks {
            if case .listItem(let ordered, let number, let depth) = b.kind {
                closeLists(downTo: depth)
                if let last = openLists.last, last.depth == depth, last.ordered != ordered {
                    closeLists(downTo: depth - 1)
                }
                if openLists.last?.depth == depth {
                    if liOpen.last == true { body.append("</li>"); liOpen[liOpen.count - 1] = false }
                } else {
                    while (openLists.last?.depth ?? -1) < depth {
                        let d = (openLists.last?.depth ?? -1) + 1
                        let start = ordered && d == depth && number > 1 ? " start=\"\(number)\"" : ""
                        body.append(ordered && d == depth ? "<ol\(start)>" : "<ul>")
                        openLists.append((ordered && d == depth, d))
                        if d < depth {
                            // Skipped a level: give the deeper list a parent item so the HTML stays valid.
                            body.append("<li>")
                            liOpen.append(true)
                        } else {
                            liOpen.append(false)
                        }
                    }
                }
                body.append("<li>" + esc(b.text))
                liOpen[liOpen.count - 1] = true
                continue
            }
            closeLists(downTo: -1)

            switch b.kind {
            case .heading(let level):
                body.append("<h\(level)>\(esc(b.text))</h\(level)>")
            case .paragraph:
                body.append("<p>\(esc(b.text))</p>")
            case .code:
                body.append("<pre><code>\(esc(b.text))</code></pre>")
            case .pageMarker(let page):
                body.append("<p class=\"page\">Page \(page)</p>")
            case .table(let rows, let header):
                var t = ["<table>"]
                var bodyRows = rows[...]
                if header, let first = rows.first {
                    t.append("<thead><tr>" + first.map { "<th scope=\"col\">\(esc($0))</th>" }.joined() + "</tr></thead>")
                    bodyRows = rows.dropFirst()
                }
                t.append("<tbody>")
                for r in bodyRows { t.append("<tr>" + r.map { "<td>\(esc($0))</td>" }.joined() + "</tr>") }
                t.append("</tbody></table>")
                body.append(t.joined(separator: "\n"))
            case .listItem:
                break
            }
        }
        closeLists(downTo: -1)

        return """
        <!DOCTYPE html>
        <html lang="\(esc(doc.language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(doc.title))</title>
        <style>
        body{font:1.125rem/1.6 system-ui,sans-serif;max-width:44rem;margin:2rem auto;padding:0 1rem;color:#111;background:#fff}
        table{border-collapse:collapse;margin:1rem 0}th,td{border:1px solid #555;padding:.4rem .6rem;text-align:start;vertical-align:top}
        pre{white-space:pre-wrap;background:#f3f3f3;padding:.75rem}.page{color:#444;border-top:1px solid #999;padding-top:.5rem}
        @media (prefers-color-scheme:dark){body{color:#eee;background:#111}pre{background:#222}th,td{border-color:#aaa}.page{color:#bbb}}
        </style>
        </head>
        <body>
        <main>
        \(body.joined(separator: "\n"))
        </main>
        </body>
        </html>

        """
    }
}
