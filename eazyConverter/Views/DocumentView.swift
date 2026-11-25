import SwiftUI

/// The explorer. Two ways to read:
/// - Text: the whole document in one text area, read with the arrow keys
///   (VoiceOver follows the cursor), with Headings, Tables and Pages rotors.
/// - Structure: every block is its own VoiceOver element with real heading levels.
struct DocumentView: View {
    enum Mode: Hashable { case text, structure }

    let doc: DocumentModel
    @ObservedObject var reader: SpeechReader

    @State private var mode: Mode = .text
    @State private var reading: ReadingText?
    @State private var caret = 0
    @State private var jump: Int?
    @State private var selection: Block.ID?
    @State private var scrollTarget: Block.ID?
    @State private var showOutline = false
    @AccessibilityFocusState private var focusedBlock: Block.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch mode {
            case .text:
                if let reading {
                    ReadingTextView(reading: reading, caret: $caret, jump: $jump)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .structure:
                structureView
            }
        }
        .onAppear { if reading == nil { reading = ReadingText(doc) } }
        .onChange(of: doc) { _, newDoc in
            reading = ReadingText(newDoc)
            caret = 0
            selection = nil
        }
        .safeAreaInset(edge: .bottom) {
            ReaderBar(reader: reader, showOutline: $showOutline,
                      startIndex: startIndex,
                      startWord: mode == .text ? "cursor" : "selected item")
        }
        .sheet(isPresented: $showOutline) {
            OutlineSheet(doc: doc) { id in
                showOutline = false
                go(to: id)
            }
        }
    }

    // MARK: Instructions and view switch, at the top

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .text ? Self.textTip : Self.structureTip)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Reading view", selection: $mode) {
                Text("Text, read with arrow keys").tag(Mode.text)
                Text("Structure, one item at a time").tag(Mode.structure)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(doc.sourceFileName). \(doc.headings.count) headings, \(doc.wordCount) words.")
                    .foregroundStyle(.secondary)
                ForEach(doc.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
        .padding()
    }

    static let textTip = "To read, move into the document text and use the arrow keys: Up and Down for lines, Option with Left or Right for words. Use the VoiceOver rotor, or Command-Shift-H, to jump to a heading, table or page. Command-Shift-R reads aloud from the cursor."
    static let structureTip = "Each heading, paragraph, list item and table row is its own item. Use the Headings rotor to jump between headings. Select an item and press Return, or use the Read aloud from here action, to hear it read aloud."

    private var startIndex: Int? {
        switch mode {
        case .text:
            return caret > 0 ? reading?.blockIndex(at: caret) : nil
        case .structure:
            guard let selection else { return nil }
            return doc.blocks.firstIndex { $0.id == selection }
        }
    }

    private func go(to id: Block.ID) {
        switch mode {
        case .text:
            if let i = doc.blocks.firstIndex(where: { $0.id == id }), let r = reading?.ranges[i] {
                Task {
                    // Wait for the sheet to close, then move the cursor to the heading.
                    try? await Task.sleep(for: .milliseconds(500))
                    jump = r.location
                }
            }
        case .structure:
            selection = id
            scrollTarget = id
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                focusedBlock = id
            }
        }
    }

    // MARK: Structure view

    private var structureView: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(doc.blocks.enumerated()), id: \.element.id) { index, block in
                    BlockRow(block: block, isBeingRead: reader.currentIndex == index)
                        .id(block.id)
                        .tag(block.id)
                        .accessibilityFocused($focusedBlock, equals: block.id)
                        .accessibilityAction(named: "Read aloud from here") { reader.play(from: index) }
                        .accessibilityAction(named: "Copy text") { copy(block) }
                        .contextMenu {
                            Button("Read aloud from here") { reader.play(from: index) }
                            Button("Copy text") { copy(block) }
                        }
                }
            }
            .accessibilityRotor("Headings") {
                ForEach(doc.headings) { h in
                    AccessibilityRotorEntry(Text("\(h.text), level \(h.headingLevel ?? 1)"), id: h.id)
                }
            }
            .accessibilityRotor("Tables") {
                ForEach(doc.blocks.filter { if case .table = $0.kind { return true } else { return false } }) { t in
                    AccessibilityRotorEntry(Text(tableName(t)), id: t.id)
                }
            }
            .accessibilityRotor("Pages") {
                ForEach(doc.blocks.filter { if case .pageMarker = $0.kind { return true } else { return false } }) { p in
                    AccessibilityRotorEntry(Text(p.spokenText), id: p.id)
                }
            }
            .onKeyPress(.return) {
                guard let id = selection, let i = doc.blocks.firstIndex(where: { $0.id == id }) else { return .ignored }
                reader.play(from: i)
                return .handled
            }
            .onChange(of: reader.currentIndex) { _, index in
                guard let index, doc.blocks.indices.contains(index) else { return }
                scroll(proxy, to: doc.blocks[index].id)
            }
            .onChange(of: scrollTarget) { _, id in
                if let id { scroll(proxy, to: id) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: Block.ID) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .top)
        } else {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func copy(_ block: Block) {
        Pasteboard.copy(block.kind == .paragraph || block.isHeading ? block.text : block.spokenText)
        announce("Copied")
    }

    private func tableName(_ block: Block) -> String {
        if case .table(let rows, _) = block.kind {
            return "Table, \(rows.count) rows, \(rows.first?.count ?? 0) columns"
        }
        return "Table"
    }
}

// MARK: - Block rows

struct BlockRow: View {
    let block: Block
    let isBeingRead: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .listRowBackground(isBeingRead ? Color.accentColor.opacity(0.18) : nil)
            .accessibilityValue(isBeingRead ? "Being read aloud" : "")
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(headingFont(level))
                .bold()
                .padding(.top, level <= 2 ? 8 : 4)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(AccessibilityHeadingLevel(level: level))
        case .paragraph:
            Text(block.text)
                .textSelection(.enabled)
        case .listItem(let ordered, let number, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered ? "\(number)." : "•")
                    .monospacedDigit()
                Text(block.text)
            }
            .padding(.leading, CGFloat(depth) * 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((depth > 0 ? "Level \(depth + 1). " : "") + (ordered ? "\(number). " : "• ") + block.text)
        case .code:
            Text(block.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Code. " + block.text)
        case .pageMarker(let page):
            Text("Page \(page)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .table(let rows, let header):
            TableBlockView(rows: rows, hasHeaderRow: header)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        default: return .headline
        }
    }
}

/// Each row is one VoiceOver element that says its column names with its values,
/// so a table is understandable without a grid to navigate.
struct TableBlockView: View {
    let rows: [[String]]
    let hasHeaderRow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        Text(rows[r][c])
                            .bold(hasHeaderRow && r == 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(6)
                .background(hasHeaderRow && r == 0 ? Color.secondary.opacity(0.15) : Color.clear)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowLabel(r))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table, \(rows.count) rows, \(rows.first?.count ?? 0) columns")
    }

    private func rowLabel(_ r: Int) -> String {
        let cells = rows[r]
        if hasHeaderRow {
            if r == 0 { return "Column headers: " + cells.joined(separator: ", ") }
            let headers = rows[0]
            let pairs = cells.enumerated().map { i, value in
                let name = i < headers.count && !headers[i].isEmpty ? headers[i] : "Column \(i + 1)"
                return "\(name): \(value.isEmpty ? "blank" : value)"
            }
            return "Row \(r) of \(rows.count - 1). " + pairs.joined(separator: ", ")
        }
        return "Row \(r + 1) of \(rows.count). " + cells.map { $0.isEmpty ? "blank" : $0 }.joined(separator: ", ")
    }
}

// MARK: - Reader bar

struct ReaderBar: View {
    @ObservedObject var reader: SpeechReader
    @Binding var showOutline: Bool
    let startIndex: Int?
    var startWord = "selected item"

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { showOutline = true } label: {
                    Label("Headings", systemImage: "list.bullet.indent")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button { reader.previousSection() } label: {
                    Label("Previous heading", systemImage: "backward.end")
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button {
                    if reader.state == .idle { reader.play(from: startIndex) } else { reader.togglePlayPause() }
                } label: {
                    Label(playTitle, systemImage: reader.state == .speaking ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button { reader.stop() } label: {
                    Label("Stop reading", systemImage: "stop.fill")
                }
                .disabled(reader.state == .idle)
                .keyboardShortcut(".", modifiers: .command)

                Button { reader.nextSection() } label: {
                    Label("Next heading", systemImage: "forward.end")
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Toggle("Use my VoiceOver voice and speed", isOn: $reader.useVoiceOverVoice)
            if !reader.useVoiceOverVoice {
                Slider(value: $reader.speed, in: 0.5...2, step: 0.1) {
                    Text("Speaking speed")
                } minimumValueLabel: {
                    Text("Slow").font(.caption)
                } maximumValueLabel: {
                    Text("Fast").font(.caption)
                }
                .accessibilityValue("\(Int((reader.speed * 100).rounded())) percent")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read aloud controls")
    }

    private var playTitle: String {
        switch reader.state {
        case .speaking: return "Pause reading"
        case .paused: return "Resume reading"
        case .idle: return startIndex == nil ? "Read aloud from the start" : "Read aloud from \(startWord)"
        }
    }
}

// MARK: - Outline

struct OutlineSheet: View {
    let doc: DocumentModel
    let go: (Block.ID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(doc.headings) { h in
                Button {
                    go(h.id)
                } label: {
                    Text(h.text)
                        .padding(.leading, CGFloat((h.headingLevel ?? 1) - 1) * 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("\(h.text), heading level \(h.headingLevel ?? 1)")
            }
            .overlay {
                if doc.headings.isEmpty {
                    ContentUnavailableView("No headings", systemImage: "list.bullet.indent",
                                           description: Text("This document has no headings. Use the Pages rotor or read from the start."))
                }
            }
            .navigationTitle("Go to heading")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
