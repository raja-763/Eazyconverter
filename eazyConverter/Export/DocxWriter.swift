import Foundation

/// Writes a real Word document: built-in Heading 1–6 styles (so headings show in
/// Word's Navigation pane and screen-reader heading lists), true numbered and
/// bulleted lists, tables with a repeating header row, a document title and language.
enum DocxWriter {
    static func docx(_ doc: DocumentModel) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRels)
        zip.add("docProps/core.xml", core(doc))
        zip.add("word/_rels/document.xml.rels", documentRels)
        zip.add("word/styles.xml", styles(lang: doc.language))
        let (body, orderedLists) = bodyXML(doc)
        zip.add("word/numbering.xml", numbering(orderedListCount: orderedLists))
        zip.add("word/settings.xml", settings(lang: doc.language))
        zip.add("word/document.xml", body)
        return zip.finish()
    }

    // MARK: Body

    private static func bodyXML(_ doc: DocumentModel) -> (String, Int) {
        var parts: [String] = []
        var orderedListIds = 0          // each ordered list gets its own numbering instance (restarts at 1)
        var currentOrderedNumId: Int?
        var previousWasOrdered = false

        for b in doc.blocks {
            switch b.kind {
            case .heading(let level):
                parts.append(paragraph(b.text, style: "Heading\(level)"))
            case .paragraph:
                parts.append(paragraph(b.text, style: nil))
            case .code:
                parts.append(paragraph(b.text, style: "SourceCode"))
            case .pageMarker:
                break
            case .listItem(let ordered, _, let depth):
                let numId: Int
                if ordered {
                    if !previousWasOrdered || currentOrderedNumId == nil {
                        orderedListIds += 1
                        currentOrderedNumId = 2 + orderedListIds   // ids 3, 4, 5…
                    }
                    numId = currentOrderedNumId!
                } else {
                    numId = 1
                }
                parts.append(paragraph(b.text, style: "ListParagraph",
                                       extra: "<w:numPr><w:ilvl w:val=\"\(depth)\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"))
            case .table(let rows, let header):
                parts.append(table(rows, header: header))
            }
            switch b.kind {
            case .listItem(let ordered, _, let depth):
                // A bulleted item at the top level ends a numbered list;
                // nested bullets inside a numbered list don't.
                if ordered { previousWasOrdered = true }
                else if depth == 0 { previousWasOrdered = false; currentOrderedNumId = nil }
            case .pageMarker:
                break   // A page break inside a list doesn't end the list.
            default:
                previousWasOrdered = false
                currentOrderedNumId = nil
            }
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
        \(parts.joined(separator: "\n"))
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
        </w:body>
        </w:document>
        """
        return (document, orderedListIds)
    }

    private static func paragraph(_ text: String, style: String?, extra: String = "") -> String {
        var pPr = ""
        if style != nil || !extra.isEmpty {
            pPr = "<w:pPr>" + (style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? "") + extra + "</w:pPr>"
        }
        return "<w:p>\(pPr)\(runs(text))</w:p>"
    }

    /// Line breaks and tabs become Word's own break and tab elements.
    private static func runs(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out = "<w:r>"
        for (i, line) in lines.enumerated() {
            if i > 0 { out += "<w:br/>" }
            let tabbed = line.components(separatedBy: "\t")
            for (j, piece) in tabbed.enumerated() {
                if j > 0 { out += "<w:tab/>" }
                if !piece.isEmpty { out += "<w:t xml:space=\"preserve\">\(xml(piece))</w:t>" }
            }
        }
        return out + "</w:r>"
    }

    private static func table(_ rows: [[String]], header: Bool) -> String {
        let cols = rows.map(\.count).max() ?? 1
        let colWidth = 9360 / max(cols, 1)     // 6.5 inches of text width in twentieths of a point
        var t = """
        <w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/>\
        <w:tblLook w:val="04A0" w:firstRow="\(header ? 1 : 0)" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>
        <w:tblGrid>\(String(repeating: "<w:gridCol w:w=\"\(colWidth)\"/>", count: cols))</w:tblGrid>
        """
        for (i, row) in rows.enumerated() {
            let isHeader = header && i == 0
            t += "<w:tr>" + (isHeader ? "<w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>" : "")
            for cell in row {
                let run = isHeader
                    ? "<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">\(xml(cell))</w:t></w:r>"
                    : runs(cell)
                t += "<w:tc><w:tcPr><w:tcW w:w=\"\(colWidth)\" w:type=\"dxa\"/></w:tcPr><w:p>\(run)</w:p></w:tc>"
            }
            t += "</w:tr>\n"
        }
        return t + "</w:tbl><w:p/>"
    }

    /// Escapes text for XML and drops control characters Word refuses to open.
    static func xml(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                let v = scalar.value
                if v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000 {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // MARK: Package parts

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
    <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
    </Relationships>
    """

    /// Only the title and language. No author name, no edit times: the export carries no personal data.
    private static func core(_ doc: DocumentModel) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(xml(doc.title))</dc:title>
        <dc:language>\(xml(doc.language))</dc:language>
        </cp:coreProperties>
        """
    }

    private static func settings(lang: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:defaultTabStop w:val="720"/>
        <w:themeFontLang w:val="\(xml(lang))"/>
        </w:settings>
        """
    }

    private static func styles(lang: String) -> String {
        let sizes = [1: 40, 2: 32, 3: 28, 4: 26, 5: 24, 6: 24]   // half-points
        let headings = (1...6).map { level in
            """
            <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>\
            <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="\(level <= 2 ? 360 : 240)" w:after="120"/><w:outlineLvl w:val="\(level - 1)"/></w:pPr>\
            <w:rPr><w:b/><w:sz w:val="\(sizes[level]!)"/><w:szCs w:val="\(sizes[level]!)"/></w:rPr></w:style>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="\(xml(lang))"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
        \(headings)
        <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:uiPriority w:val="34"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:contextualSpacing/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="SourceCode"><w:name w:val="Source Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="21"/></w:rPr></w:style>
        <w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
        <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:tblPr><w:tblBorders>\
        <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>\
        <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>\
        </w:tblBorders></w:tblPr></w:style>
        </w:styles>
        """
    }

    /// numId 1 = bullets; numId 3+ = one numbered list each, all restarting at 1.
    private static func numbering(orderedListCount: Int) -> String {
        let bulletChars = ["•", "◦", "▪"]
        let bulletLevels = (0...8).map { i in
            """
            <w:lvl w:ilvl="\(i)"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="\(bulletChars[i % 3])"/><w:lvlJc w:val="left"/>\
            <w:pPr><w:ind w:left="\(720 * (i + 1))" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        let formats = ["decimal", "lowerLetter", "lowerRoman"]
        let decimalLevels = (0...8).map { i in
            """
            <w:lvl w:ilvl="\(i)"><w:start w:val="1"/><w:numFmt w:val="\(formats[i % 3])"/><w:lvlText w:val="%\(i + 1)."/><w:lvlJc w:val="left"/>\
            <w:pPr><w:ind w:left="\(720 * (i + 1))" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        var nums = "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>"
        nums += "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num>"
        if orderedListCount > 0 {
            for n in 1...orderedListCount {
                nums += "<w:num w:numId=\"\(2 + n)\"><w:abstractNumId w:val=\"1\"/>"
                    + "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bulletLevels)</w:abstractNum>
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(decimalLevels)</w:abstractNum>
        \(nums)
        </w:numbering>
        """
    }
}
