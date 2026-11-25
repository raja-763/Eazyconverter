import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum ImportError: Error, LocalizedError {
    case unsupported(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            return "The app can't open .\(ext) files. Try a PDF, Word, HTML, text, Markdown, RTF or picture file."
        case .noText:
            return "No text was found in this file."
        }
    }
}

enum Importer {
    /// Every type the Open button accepts.
    static let openableTypes: [UTType] = [.pdf, .docx, .html, .plainText, .markdownText, .rtf, .image]

    /// Reads a file the person picked. The file's bytes are copied into memory,
    /// access to the file is released straight away, and nothing is written anywhere.
    static func load(from url: URL) async throws -> DocumentModel {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: [.uncached])
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        return try await Task.detached(priority: .userInitiated) {
            var model = try Importer.parse(data, fileName: name, type: type)
            model.language = Language.detect(model.plainText)
            if model.blocks.isEmpty { throw ImportError.noText }
            return model
        }.value
    }

    static func parse(_ data: Data, fileName: String, type: UTType?) throws -> DocumentModel {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let type else { throw ImportError.unsupported(ext) }

        if type.conforms(to: .pdf) { return try PDFImporter.read(data, fileName: fileName) }
        if type.conforms(to: .docx) || ext == "docx" { return try DocxReader.read(data, fileName: fileName) }
        if type.conforms(to: .html) { return HTMLReader.read(data, fileName: fileName) }
        if type.conforms(to: .rtf) { return try readRTF(data, fileName: fileName) }
        if type.conforms(to: .image) { return try readImage(data, fileName: fileName) }
        if type.conforms(to: .markdownText) || ext == "md" || ext == "markdown" {
            return MarkdownReader.read(data, fileName: fileName)
        }
        if type.conforms(to: .text) {
            var text = String(decoding: data, as: UTF8.self)
            // A text file with no blank lines usually means one paragraph per line.
            if !text.contains("\n\n") && !text.contains("\r\n\r\n") {
                text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\n\n")
            }
            return MarkdownReader.read(text: text, fileName: fileName)
        }
        throw ImportError.unsupported(ext)
    }

    static func readImage(_ data: Data, fileName: String) throws -> DocumentModel {
        let image = try OCR.cgImage(from: data)
        let textBlocks = (try? OCR.blocks(in: image)) ?? []
        let description = ImageDescriber.describe(image, hasText: !textBlocks.isEmpty)

        var blocks = [
            Block(kind: .heading(level: 2), text: "Image description"),
            Block(kind: .paragraph, text: description)
        ]
        if !textBlocks.isEmpty {
            blocks.append(Block(kind: .heading(level: 2), text: "Text in the picture"))
            // Keep the picture's own headings below the section heading.
            blocks += textBlocks.map { b in
                guard case .heading(let level) = b.kind else { return b }
                var copy = b
                copy.kind = .heading(level: min(6, level + 2))
                return copy
            }
        }
        return DocumentModel(
            title: (fileName as NSString).deletingPathExtension,
            sourceFileName: fileName,
            blocks: blocks,
            notes: ["The description and text were made on your device by Apple's Vision framework. It lists what the picture likely shows rather than writing a full caption, and recognition can make mistakes."]
        )
    }

    private static func readRTF(_ data: Data, fileName: String) throws -> DocumentModel {
        let attributed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let ns = attributed.string as NSString
        var lines: [StyledLine] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { text, range, _, _ in
            guard let text else { return }
            var size: CGFloat = 12
            var bold = false
            if range.length > 0, let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont {
                size = font.pointSize
                #if os(iOS)
                bold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                #else
                bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                #endif
            }
            // Each RTF paragraph is a real paragraph, so never merge them.
            lines.append(StyledLine(text: text, size: size, bold: bold, gapAbove: 1))
        }
        let blocks = StructureGuesser.blocks(from: lines)
        let title = blocks.first(where: \.isHeading)?.text ?? (fileName as NSString).deletingPathExtension
        return DocumentModel(title: title, sourceFileName: fileName, blocks: blocks)
    }
}
