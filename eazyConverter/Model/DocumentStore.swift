import SwiftUI

/// Holds the open document in memory only. Nothing is cached, saved,
/// logged or sent anywhere; Clear (or closing the app) erases it.
@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var document: DocumentModel?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func open(_ url: URL) async {
        isLoading = true
        errorMessage = nil
        announce("Opening \(url.lastPathComponent)")
        defer { isLoading = false }
        do {
            let doc = try await Importer.load(from: url)
            document = doc
            let headings = doc.headings.count
            announce("\(doc.title) opened. \(headings) heading\(headings == 1 ? "" : "s"), \(doc.wordCount) words.")
        } catch {
            errorMessage = error.localizedDescription
            announce("Couldn't open the file. \(error.localizedDescription)")
        }
    }

    /// Used by "Image from text" and pasted text.
    func openText(_ text: String, title: String) {
        var doc = MarkdownReader.read(text: text, fileName: title)
        doc.language = Language.detect(text)
        document = doc
        announce("\(doc.title) ready.")
    }

    func clear() {
        document = nil
        errorMessage = nil
        announce("Upload screen. The document was cleared from memory.")
    }
}
