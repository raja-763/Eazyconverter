import Foundation

/// Reads Word (.docx) files directly, keeping real headings, lists and tables.
/// Works the same on Mac and iPhone because it doesn't depend on AppKit.
enum DocxReader {
    enum DocxError: Error, LocalizedError {
        case missingBody
        var errorDescription: String? { "This Word document has no readable body." }
    }

    static func read(_ data: Data, fileName: String) throws -> DocumentModel {
        let zip = try ZipReader(data: data)
        guard let body = try zip.data(for: "word/document.xml") else { throw DocxError.missingBody }

        var styles = StyleMap()
        if let d = try? zip.data(for: "word/styles.xml") { styles = StyleMap(d) }
        var numbering = NumberingMap()
        if let d = try? zip.data(for: "word/numbering.xml") { numbering = NumberingMap(d) }

        let parser = BodyParser(styles: styles, numbering: numbering)
        let xml = XMLParser(data: body)
        xml.delegate = parser
        xml.parse()

        var title = (fileName as NSString).deletingPathExtension
        if let core = try? zip.data(for: "docProps/core.xml"),
           let found = SimpleTextGrabber.text(of: "dc:title", in: core), !found.isEmpty {
            title = found
        } else if let firstHeading = parser.blocks.first(where: \.isHeading) {
            title = firstHeading.text
        }
        return DocumentModel(title: title, sourceFileName: fileName, blocks: parser.blocks)
    }
}

/// Maps paragraph style ids to heading levels, using the style's name
/// ("heading 1", "Title") or its outline level, so translated Word templates work too.
struct StyleMap {
    var headingLevel: [String: Int] = [:]

    init() {}

    init(_ data: Data) {
        
        let d = StyleDelegate()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        headingLevel = d.map
    }
}

/// Knows which Word lists are numbered and which are bulleted.
struct NumberingMap {
    private var abstractFor: [String: String] = [:]          // numId -> abstractNumId
    private var formats: [String: [Int: String]] = [:]       // abstractNumId -> ilvl -> numFmt

    init() {}

    init(_ data: Data) {
        
        let d = NumberingDelegate()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        abstractFor = d.abstractFor
        formats = d.formats
    }

    func isOrdered(numId: String, level: Int) -> Bool {
        guard let abstract = abstractFor[numId], let fmt = formats[abstract]?[level] else { return false }
        return fmt != "bullet" && fmt != "none"
    }
}

private final class BodyParser: NSObject, XMLParserDelegate {
    let styles: StyleMap
    let numbering: NumberingMap
    var blocks: [Block] = []

    // Paragraph state
    private var text = ""
    private var inText = false
    private var styleLevel: Int?
    private var outlineLevel: Int?
    private var numId: String?
    private var ilvl = 0
    private var counters: [String: [Int: Int]] = [:]

    // Table state (nested tables are flattened into the outer cell)
    private var tableDepth = 0
    private var rows: [[String]] = []
    private var cell = ""
    private var firstRowIsHeader = false

    init(styles: StyleMap, numbering: NumberingMap) {
        self.styles = styles
        self.numbering = numbering
    }

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "w:p":
            text = ""; styleLevel = nil; outlineLevel = nil; numId = nil; ilvl = 0
        case "w:pStyle":
            if let id = a["w:val"] { styleLevel = styles.headingLevel[id] }
        case "w:outlineLvl":
            if let n = Int(a["w:val"] ?? ""), n < 6 { outlineLevel = n + 1 }
        case "w:numId":
            if let v = a["w:val"], v != "0" { numId = v }
        case "w:ilvl":
            ilvl = Int(a["w:val"] ?? "") ?? 0
        case "w:t":
            inText = true
        case "w:tab":
            text += "\t"
        case "w:br", "w:cr":
            text += " "
        case "w:tbl":
            tableDepth += 1
            if tableDepth == 1 { rows = []; firstRowIsHeader = false }
        case "w:tr":
            if tableDepth == 1 { rows.append([]) }
        case "w:tblHeader":
            if tableDepth == 1, rows.count == 1 { firstRowIsHeader = true }
        case "w:tc":
            if tableDepth == 1 { cell = "" }
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters string: String) {
        if inText { text += string }
    }

    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "w:t":
            inText = false
        case "w:p":
            let t = text.collapsedWhitespace
            if tableDepth > 0 {
                if !t.isEmpty { cell += (cell.isEmpty ? "" : " ") + t }
                return
            }
            guard !t.isEmpty else { return }
            if let level = styleLevel ?? outlineLevel {
                counters = [:]
                blocks.append(Block(kind: .heading(level: level), text: t))
            } else if let id = numId {
                let ordered = numbering.isOrdered(numId: id, level: ilvl)
                var levels = counters[id] ?? [:]
                levels[ilvl, default: 0] += 1
                for deeper in levels.keys where deeper > ilvl { levels[deeper] = 0 }
                counters[id] = levels
                blocks.append(Block(kind: .listItem(ordered: ordered, number: levels[ilvl] ?? 1, depth: min(ilvl, 5)),
                                    text: t))
            } else {
                blocks.append(Block(kind: .paragraph, text: t))
            }
        case "w:tc":
            if tableDepth == 1, !rows.isEmpty { rows[rows.count - 1].append(cell) }
        case "w:tbl":
            if tableDepth == 1 {
                let width = rows.map(\.count).max() ?? 0
                let padded = rows.filter { !$0.isEmpty }
                    .map { $0 + Array(repeating: "", count: width - $0.count) }
                if !padded.isEmpty {
                    // Most Word tables use the first row as headers even without the
                    // "repeat header row" setting, so treat it as a header row by default.
                    blocks.append(Block(kind: .table(rows: padded, hasHeaderRow: firstRowIsHeader || padded.count > 1),
                                        text: ""))
                }
            }
            tableDepth = max(0, tableDepth - 1)
        default: break
        }
    }
}

/// Pulls the text of one element out of a small XML file (used for the document title).
enum SimpleTextGrabber {
    static func text(of element: String, in data: Data) -> String? {
        
        let d = TitleDelegate(target: element)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - XML delegates

private final class StyleDelegate: NSObject, XMLParserDelegate {
            var map: [String: Int] = [:]
            var currentId: String?
            func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes a: [String: String] = [:]) {
                switch name {
                case "w:style":
                    currentId = a["w:type"] == "paragraph" ? a["w:styleId"] : nil
                case "w:name":
                    guard let id = currentId, let v = a["w:val"]?.lowercased() else { return }
                    if v == "title" { map[id] = 1 }
                    else if v.hasPrefix("heading "), let n = Int(v.dropFirst(8)), (1...6).contains(n) { map[id] = n }
                case "w:outlineLvl":
                    if let id = currentId, map[id] == nil, let n = Int(a["w:val"] ?? ""), n < 6 { map[id] = n + 1 }
                default: break
                }
            }
            func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                if name == "w:style" { currentId = nil }
            }
        }

private final class NumberingDelegate: NSObject, XMLParserDelegate {
            var abstractFor: [String: String] = [:]
            var formats: [String: [Int: String]] = [:]
            var abstractId: String?, level: Int?, numId: String?
            func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes a: [String: String] = [:]) {
                switch name {
                case "w:abstractNum": abstractId = a["w:abstractNumId"]
                case "w:lvl": level = Int(a["w:ilvl"] ?? "")
                case "w:numFmt":
                    if let id = abstractId, let lv = level, let fmt = a["w:val"] { formats[id, default: [:]][lv] = fmt }
                case "w:num": numId = a["w:numId"]
                case "w:abstractNumId":
                    if let n = numId, let v = a["w:val"] { abstractFor[n] = v }
                default: break
                }
            }
            func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                if name == "w:abstractNum" { abstractId = nil }
                if name == "w:num" { numId = nil }
                if name == "w:lvl" { level = nil }
            }
        }

private final class TitleDelegate: NSObject, XMLParserDelegate {
            let target: String
            var value: String?
            var inside = false
            init(target: String) { self.target = target }
            func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes a: [String: String] = [:]) {
                if name == target { inside = true; value = "" }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { if inside { value? += s } }
            func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                if name == target { inside = false; p.abortParsing() }
            }
        }
