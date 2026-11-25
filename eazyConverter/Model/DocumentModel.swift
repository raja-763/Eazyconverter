import Foundation

/// One structural piece of a document. Everything the app shows, reads aloud
/// and exports is built from this list, so structure survives every conversion.
enum BlockKind: Equatable {
    case heading(level: Int)              // 1...6
    case paragraph
    case listItem(ordered: Bool, number: Int, depth: Int)
    case table(rows: [[String]], hasHeaderRow: Bool)
    case code
    case pageMarker(page: Int)            // "Page 3" from a PDF
}

struct Block: Identifiable, Equatable {
    let id = UUID()
    var kind: BlockKind
    var text: String                       // empty for tables

    var isHeading: Bool {
        if case .heading = kind { return true }
        return false
    }

    var headingLevel: Int? {
        if case .heading(let level) = kind { return level }
        return nil
    }

    /// Text as it should be spoken or copied.
    var spokenText: String {
        switch kind {
        case .heading(let level):
            return "Heading level \(level). \(text)"
        case .listItem(let ordered, let number, _):
            return ordered ? "\(number). \(text)" : "Bullet. \(text)"
        case .table(let rows, _):
            let cols = rows.first?.count ?? 0
            var parts = ["Table with \(rows.count) rows and \(cols) columns."]
            for (i, row) in rows.enumerated() {
                parts.append("Row \(i + 1): " + row.joined(separator: ", ") + ".")
            }
            return parts.joined(separator: " ")
        case .pageMarker(let page):
            return "Page \(page)."
        case .paragraph, .code:
            return text
        }
    }
}

struct DocumentModel: Equatable {
    var title: String
    var sourceFileName: String
    var blocks: [Block]
    /// Notes shown to the user about how the file was read (for example OCR was used).
    var notes: [String] = []
    /// BCP 47 language code, detected on device. Written into every export.
    var language: String = "en"

    var headings: [Block] { blocks.filter(\.isHeading) }

    var wordCount: Int {
        blocks.reduce(0) { total, block in
            total + block.spokenText.split(whereSeparator: { $0.isWhitespace }).count
        }
    }

    /// Plain text with blank lines between blocks. Used for TXT export and OCR input.
    var plainText: String {
        blocks.compactMap { block -> String? in
            switch block.kind {
            case .pageMarker: return nil
            case .listItem(let ordered, let number, let depth):
                let indent = String(repeating: "  ", count: depth)
                return indent + (ordered ? "\(number). " : "- ") + block.text
            case .table(let rows, _):
                return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            default:
                return block.text
            }
        }
        .joined(separator: "\n\n")
    }

    static func fromPlainText(_ text: String, title: String, source: String) -> DocumentModel {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return DocumentModel(
            title: title,
            sourceFileName: source,
            blocks: paragraphs.map { Block(kind: .paragraph, text: $0) }
        )
    }
}

extension String {
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
