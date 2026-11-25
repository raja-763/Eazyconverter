import SwiftUI
import UniformTypeIdentifiers

/// The bytes of one export, handed straight to the system save panel.
/// The app writes no copy of its own: the file only exists where the person saves it.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.pdf, .docx, .html, .plainText, .markdownText, .png, .data] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
