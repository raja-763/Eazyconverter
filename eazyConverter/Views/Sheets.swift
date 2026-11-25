import SwiftUI
import UniformTypeIdentifiers

/// Type or paste text, then explore or convert it like any other document.
/// Markdown marks (# headings, - lists, | tables) become real structure.
struct PasteTextSheet: View {
    let onOpen: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @FocusState private var focus: Field?
    private enum Field { case title, text }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($focus, equals: .title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .focused($focus, equals: .text)
                        .accessibilityLabel("Text")
                        .accessibilityHint("Start a line with # for a heading or - for a list item.")
                } header: {
                    Text("Text")
                } footer: {
                    Text("Start a line with # for a heading, - for a bullet, or 1. for a numbered item.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Type or paste text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        onOpen(text, title.isEmpty ? "Untitled" : title)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear { focus = .title }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}

/// Makes a high-contrast PNG from text. The text is embedded in the file as its
/// description, and shown here as the preview's accessibility label.
struct TextToImageSheet: View {
    let initialText: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var fontSize: Double = 40
    @State private var theme: TextImageRenderer.Theme = .blackOnWhite
    @State private var exportFile: ExportFile?
    @State private var showExporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Text for the picture")
                }
                Section("Look") {
                    Stepper(value: $fontSize, in: 16...120, step: 4) {
                        Text("Text size: \(Int(fontSize)) points")
                    }
                    Picker("Colors", selection: $theme) {
                        ForEach(TextImageRenderer.Theme.allCases) { t in
                            Text(t.name).tag(t)
                        }
                    }
                }
                Section("Preview") {
                    preview
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Picture from text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save picture…") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
            .onAppear { if text.isEmpty { text = String(initialText.prefix(5000)) } }
            .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .png,
                          defaultFilename: safeFileName(title)) { result in
                switch result {
                case .success(let url): announce("Picture saved as \(url.lastPathComponent)")
                case .failure: announce("The picture wasn't saved")
                }
                exportFile = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private var preview: some View {
        if !text.isEmpty,
           let cg = TextImageRenderer.image(text: String(text.prefix(1500)), fontSize: CGFloat(fontSize), theme: theme, width: 1200) {
            Image(cg, scale: 1, label: Text("Preview picture. Its text reads: \(String(text.prefix(300)))"))
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
        } else {
            Text("Type some text to see a preview.")
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let cg = TextImageRenderer.image(text: text, fontSize: CGFloat(fontSize), theme: theme),
              let data = TextImageRenderer.png(cg, altText: text, title: title) else {
            announce("The text is too long for one picture. Shorten it and try again.")
            return
        }
        exportFile = ExportFile(data: data)
        showExporter = true
    }
}
