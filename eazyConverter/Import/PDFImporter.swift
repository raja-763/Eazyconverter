import Foundation
import PDFKit

enum PDFImporter {
    enum PDFError: Error, LocalizedError {
        case unreadable, locked
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The app couldn't open this PDF."
            case .locked: return "This PDF is password protected. Open it in Preview, remove the password, then try again."
            }
        }
    }

    static func read(_ data: Data, fileName: String) throws -> DocumentModel {
        guard let pdf = PDFDocument(data: data) else { throw PDFError.unreadable }
        if pdf.isLocked { throw PDFError.locked }

        var blocks: [Block] = []
        var ocrPages: [Int] = []
        let multiPage = pdf.pageCount > 1

        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            if multiPage { blocks.append(Block(kind: .pageMarker(page: index + 1), text: "")) }

            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                // Scanned page: no text layer, so read the picture.
                if let image = renderedImage(of: page), let found = try? OCR.blocks(in: image), !found.isEmpty {
                    blocks += found
                    ocrPages.append(index + 1)
                }
                continue
            }
            blocks += StructureGuesser.blocks(from: styledLines(of: page))
        }

        let attrs = pdf.documentAttributes ?? [:]
        let embeddedTitle = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = embeddedTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? blocks.first(where: \.isHeading)?.text
            ?? (fileName as NSString).deletingPathExtension

        var notes = ["Headings and lists were worked out from text size and layout, because most PDFs don't store them reliably. Check the structure before you share an export."]
        if !ocrPages.isEmpty {
            let list = ocrPages.map(String.init).joined(separator: ", ")
            notes.append("Text on page \(list) was read from a scanned image on your device, so it may contain recognition errors.")
        }
        return DocumentModel(title: title, sourceFileName: fileName, blocks: blocks, notes: notes)
    }

    /// Splits a page into visual lines and records each line's font size and weight.
    private static func styledLines(of page: PDFPage) -> [StyledLine] {
        guard let attributed = page.attributedString else {
            return (page.string ?? "").components(separatedBy: .newlines).map { StyledLine(text: $0, size: 12) }
        }
        let full = attributed.string as NSString
        var lines: [StyledLine] = []
        var location = 0
        while location < full.length {
            let lineRange = full.lineRange(for: NSRange(location: location, length: 0))
            let text = full.substring(with: lineRange).trimmingCharacters(in: .newlines)
            var size: CGFloat = 12
            var bold = false
            // Use the font of the first visible character.
            if let firstVisible = text.firstIndex(where: { !$0.isWhitespace }) {
                let offset = text.utf16.distance(from: text.startIndex, to: firstVisible)
                let charIndex = min(lineRange.location + offset, attributed.length - 1)
                if let font = attributed.attribute(.font, at: charIndex, effectiveRange: nil) as? PlatformFont {
                    size = font.pointSize
                    bold = isBold(font)
                }
            }
            lines.append(StyledLine(text: text, size: size, bold: bold))
            location = NSMaxRange(lineRange)
        }
        return lines
    }

    private static func isBold(_ font: PlatformFont) -> Bool {
        let name = font.fontName.lowercased()
        if name.contains("bold") || name.contains("black") || name.contains("heavy") || name.contains("semibold") {
            return true
        }
        #if os(iOS)
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #else
        return font.fontDescriptor.symbolicTraits.contains(.bold)
        #endif
    }

    private static func renderedImage(of page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.5
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImageValue
    }
}
