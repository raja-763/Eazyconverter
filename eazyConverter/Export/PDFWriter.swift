import Foundation
import CoreGraphics
import CoreText

/// Writes a tagged PDF with Core Graphics' structure-tag API
/// (CGPDFContextBeginTag), so headings, paragraphs, lists and tables
/// carry real PDF tags (H1–H6, P, L/LI/Lbl/LBody, Table/TR/TH/TD) and a language.
/// Always check an exported PDF with a PDF accessibility checker before you publish it.
enum PDFWriter {
    static let pageSize = CGSize(width: 612, height: 792)      // US Letter, in points
    static let margin: CGFloat = 72

    static func pdf(_ doc: DocumentModel) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var media = CGRect(origin: .zero, size: pageSize)
        // Title only; no author or other personal metadata.
        let info = [kCGPDFContextTitle: doc.title, kCGPDFContextCreator: "eazyConverter"] as CFDictionary
        guard let ctx = CGContext(consumer: consumer, mediaBox: &media, info) else { return Data() }

        let renderer = Renderer(ctx: ctx, language: doc.language)
        renderer.startPage()
        for block in doc.blocks { renderer.draw(block) }
        renderer.finish()
        ctx.closePDF()
        return data as Data
    }

    static func font(_ size: CGFloat, bold: Bool = false, mono: Bool = false) -> CTFont {
        let name = mono ? (bold ? "Courier-Bold" : "Courier") : (bold ? "Helvetica-Bold" : "Helvetica")
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    /// Breaks text into lines that fit `width`. Core Text substitutes fonts for
    /// characters Helvetica lacks, so any language prints.
    static func layout(_ text: String, font: CTFont, width: CGFloat, color: CGColor? = nil) -> [CTLine] {
        guard !text.isEmpty else { return [] }
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let color { attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1_000_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as? [CTLine]) ?? []
    }

    static func metrics(_ line: CTLine) -> (ascent: CGFloat, height: CGFloat) {
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &a, &d, &l)
        return (a, (a + d) * 1.3)
    }
}

private final class Renderer {
    let ctx: CGContext
    let language: String
    var y: CGFloat = 0
    var openTags: [CGPDFTagType] = []
    var listOpen = false
    let left = PDFWriter.margin
    let width = PDFWriter.pageSize.width - PDFWriter.margin * 2

    init(ctx: CGContext, language: String) {
        self.ctx = ctx
        self.language = language
    }

    // MARK: Pages and tags

    func startPage() {
        ctx.beginPDFPage(nil)
        ctx.textMatrix = .identity
        y = PDFWriter.pageSize.height - PDFWriter.margin
        // Elements cut by a page break continue on the new page.
        for tag in openTags { begin(tag) }
    }

    func endPage() {
        for _ in openTags { CGPDFContextEndTag(ctx) }
        ctx.endPDFPage()
    }

    func finish() {
        closeList()
        while !openTags.isEmpty { pop() }
        ctx.endPDFPage()
    }

    private func begin(_ tag: CGPDFTagType) {
        let props = [CGPDFTagProperty.languageText.rawValue as String: language] as CFDictionary
        CGPDFContextBeginTag(ctx, tag, props)
    }

    func push(_ tag: CGPDFTagType) { openTags.append(tag); begin(tag) }
    func pop() { CGPDFContextEndTag(ctx); openTags.removeLast() }

    func ensureRoom(_ height: CGFloat) {
        if y - height < PDFWriter.margin {
            endPage()
            startPage()
        }
    }

    func closeList() {
        if listOpen { pop(); listOpen = false }
    }

    // MARK: Blocks

    func draw(_ block: Block) {
        switch block.kind {
        case .heading(let level):
            closeList()
            let sizes: [CGFloat] = [24, 20, 17, 15, 13, 12]
            let tags: [CGPDFTagType] = [.header1, .header2, .header3, .header4, .header5, .header6]
            y -= level <= 2 ? 14 : 8
            text(block.text, font: PDFWriter.font(sizes[level - 1], bold: true), tag: tags[level - 1], after: 6)
        case .paragraph:
            closeList()
            text(block.text, font: PDFWriter.font(12), tag: .paragraph, after: 9)
        case .code:
            closeList()
            text(block.text, font: PDFWriter.font(10.5, mono: true), tag: .paragraph, after: 9)
        case .listItem(let ordered, let number, let depth):
            if !listOpen { push(.list); listOpen = true }
            listItem(block.text, label: ordered ? "\(number)." : "•", depth: depth)
        case .table(let rows, let header):
            closeList()
            table(rows, header: header)
        case .pageMarker:
            break
        }
    }

    private func text(_ string: String, font: CTFont, tag: CGPDFTagType, x: CGFloat? = nil,
                      width: CGFloat? = nil, after: CGFloat) {
        let lines = PDFWriter.layout(string, font: font, width: width ?? self.width)
        guard let first = lines.first else { return }
        ensureRoom(PDFWriter.metrics(first).height)   // never leave an empty tag at a page bottom
        push(tag)
        for line in lines {
            let m = PDFWriter.metrics(line)
            ensureRoom(m.height)
            ctx.textPosition = CGPoint(x: x ?? left, y: y - m.ascent)
            CTLineDraw(line, ctx)
            y -= m.height
        }
        pop()
        y -= after
    }

    private func listItem(_ string: String, label: String, depth: Int) {
        let indent = left + 22 + CGFloat(depth) * 20
        let font = PDFWriter.font(12)
        let lines = PDFWriter.layout(string, font: font, width: PDFWriter.pageSize.width - PDFWriter.margin - indent)
        guard let first = lines.first else { return }
        ensureRoom(PDFWriter.metrics(first).height)
        push(.listItem)

        if let labelLine = PDFWriter.layout(label, font: font, width: 40).first {
            push(.label)
            ctx.textPosition = CGPoint(x: indent - 18, y: y - PDFWriter.metrics(labelLine).ascent)
            CTLineDraw(labelLine, ctx)
            pop()
        }
        push(.listBody)
        for line in lines {
            let m = PDFWriter.metrics(line)
            ensureRoom(m.height)
            ctx.textPosition = CGPoint(x: indent, y: y - m.ascent)
            CTLineDraw(line, ctx)
            y -= m.height
        }
        pop()
        pop()
        y -= 3
    }

    private func table(_ rows: [[String]], header: Bool) {
        let cols = max(rows.map(\.count).max() ?? 1, 1)
        let colWidth = width / CGFloat(cols)
        y -= 4
        push(.table)
        for (index, row) in rows.enumerated() {
            let isHeader = header && index == 0
            let height = rowHeight(row, bold: isHeader, colWidth: colWidth)
            if y - height < PDFWriter.margin {
                endPage()
                startPage()
                // Repeat the header row at the top of the next page.
                if header, index > 0 { drawRow(rows[0], header: true, colWidth: colWidth) }
            }
            drawRow(row, header: isHeader, colWidth: colWidth)
        }
        pop()
        y -= 12
    }

    private func rowHeight(_ row: [String], bold: Bool, colWidth: CGFloat) -> CGFloat {
        let font = PDFWriter.font(11, bold: bold)
        let tallest = row.map { cell in
            PDFWriter.layout(cell, font: font, width: colWidth - 8).reduce(0) { $0 + PDFWriter.metrics($1).height }
        }.max() ?? 0
        return max(tallest, 14) + 8
    }

    private func drawRow(_ row: [String], header: Bool, colWidth: CGFloat) {
        let font = PDFWriter.font(11, bold: header)
        let height = rowHeight(row, bold: header, colWidth: colWidth)
        push(.tableRow)
        for (i, cell) in row.enumerated() {
            push(header ? .tableHeaderCell : .tableDataCell)
            var cy = y - 4
            for line in PDFWriter.layout(cell, font: font, width: colWidth - 8) {
                let m = PDFWriter.metrics(line)
                ctx.textPosition = CGPoint(x: left + CGFloat(i) * colWidth + 4, y: cy - m.ascent)
                CTLineDraw(line, ctx)
                cy -= m.height
            }
            pop()
        }
        pop()
        y -= height
    }
}
