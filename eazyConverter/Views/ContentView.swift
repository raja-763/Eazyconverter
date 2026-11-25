import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @StateObject private var reader = SpeechReader()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showImporter = false
    @State private var showPasteSheet = false
    @State private var showImageSheet = false

    @State private var exportFile: ExportFile?
    @State private var exportType: UTType = .data
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView("Opening and reading the file…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let doc = store.document {
                    DocumentView(doc: doc, reader: reader)
                } else {
                    WelcomeView(
                        open: { showImporter = true },
                        paste: { showPasteSheet = true },
                        makeImage: { showImageSheet = true }
                    )
                }
            }
            .navigationTitle(store.document?.title ?? "eazyConverter")
            .toolbar { toolbarContent }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Importer.openableTypes) { result in
            switch result {
            case .success(let url):
                Task { await store.open(url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: exportType,
                      defaultFilename: exportName) { result in
            switch result {
            case .success(let url): announce("Saved \(url.lastPathComponent)")
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
            exportFile = nil   // drop the exported bytes from memory
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTextSheet { text, title in store.openText(text, title: title) }
        }
        .sheet(isPresented: $showImageSheet) {
            TextToImageSheet(initialText: store.document?.plainText ?? "",
                             title: store.document?.title ?? "Text image")
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.document) { _, newDoc in reader.load(newDoc) }
        #if os(iOS)
        // Hide the document from the app switcher snapshot.
        .overlay {
            if scenePhase != .active { PrivacyCover() }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showImporter = true
            } label: {
                Label("Upload file to convert", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("o", modifiers: .command)

            if store.document != nil {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button("Save as \(format.title)…") { export(format) }
                    }
                    Divider()
                    Button("Save as picture (PNG)…") { showImageSheet = true }
                } label: {
                    Label("Convert and save", systemImage: "square.and.arrow.down")
                }
                .disabled(isExporting)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                showPasteSheet = true
            } label: {
                Label("Type or paste text", systemImage: "doc.text")
            }
            Button {
                showImageSheet = true
            } label: {
                Label("Make picture from text", systemImage: "photo")
            }
            if store.document != nil {
                Button {
                    if let text = store.document?.plainText {
                        Pasteboard.copy(text)
                        announce("All text copied")
                    }
                } label: {
                    Label("Copy all text", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    reader.stop()
                    store.clear()
                } label: {
                    Label("Clear document", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func export(_ format: ExportFormat) {
        guard let doc = store.document else { return }
        isExporting = true
        announce("Preparing \(format.title)")
        Task {
            defer { isExporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) { try format.data(for: doc) }.value
                exportFile = ExportFile(data: data)
                exportType = format.contentType
                exportName = safeFileName(doc.title)
                showExporter = true
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

func safeFileName(_ title: String) -> String {
    let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let cleaned = title.components(separatedBy: bad).joined(separator: " ").collapsedWhitespace
    return cleaned.isEmpty ? "Document" : String(cleaned.prefix(80))
}

private struct WelcomeView: View {
    let open: () -> Void
    let paste: () -> Void
    let makeImage: () -> Void

    static let steps = [
        "Choose Upload file to convert, or press Command-O, and pick a PDF, Word document, web page, text file or picture.",
        "Read it with the arrow keys. Up and Down move by line. Use the VoiceOver rotor, or Command-Shift-H, to jump to a heading.",
        "To hear it read aloud, press Command-Shift-R. Press it again to pause.",
        "To convert, choose Convert and save, or press Command-Shift-S, then pick Word, PDF, web page, plain text or Markdown.",
        "When you're done, choose Clear document. Nothing is kept after that."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to use eazyConverter")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    Button(action: open) {
                        Label("Upload file to convert", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: paste) {
                        Label("Type or paste text", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: makeImage) {
                        Label("Make a picture from text", systemImage: "photo")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Opens")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
                Text("PDF, Word (.docx), web pages (.html), plain text, Markdown, RTF, and pictures such as photos and screenshots. Text in pictures and scanned PDFs is read on your device.")

                Text("Saves as")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
                Text("Word, PDF, web page, plain text, Markdown, and PNG picture.")

                Text("Privacy")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
                Text("Everything happens on this device. The app has no internet access, collects nothing, and keeps nothing: files are held in memory only while open and are erased when you clear them or close the app.")
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Label("eazyConverter", systemImage: "lock.doc")
                .font(.title)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
