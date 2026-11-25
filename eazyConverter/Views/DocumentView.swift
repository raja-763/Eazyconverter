import SwiftUI

/// The document screen shows only the document. Everything else (read aloud,
/// headings list, view switch) lives in the toolbar and the Document menu.
/// - Text view: the whole document in one text area, read with the arrow keys.
/// - Structure view: each block is its own VoiceOver item.
struct DocumentView: View {
    enum Mode: Hashable { case text, structure }

    let doc: DocumentModel
    @ObservedObject var reader: SpeechReader
    var onBack: () -> Void = {}

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
        Group {
            switch mode {
            case .text:
                if let reading {
                    ReadingTextView(reading: reading, caret: $caret, jump: $jump)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) { readMenu }
        }
        .focusedSceneValue(\.docCommands, commands)
        .sheet(isPresented: $showOutline) {
            OutlineSheet(doc: doc) { id in
                showOutline = false
                go(to: id)
            }
        }
    }

    // MARK: Commands (toolbar menu and the Document menu in the menu bar)

    private var commands: DocCommands {
        DocCommands(
            isSpeaking: reader.state == .speaking,
            playPause: playPause,
            stop: { reader.stop() },
            nextHeading: { reader.nextSection() },
            previousHeading: { reader.previousSection() },
            showHeadings: { showOutline = true },
            toggleView: toggleView
        )
    }

    private var readMenu: some View {
        Menu {
            Button(playTitle, action: playPause)
            Button("Stop reading") { reader.stop() }
                .disabled(reader.state == .idle)
            Button("Next heading") { reader.nextSection() }
            Button("Previous heading") { reader.previousSection() }
            Divider()
            Button("Go to heading…") { showOutline = true }
            Button(mode == .text ? "Show one item at a time" : "Show as text", action: toggleView)
            Divider()
            Toggle("Use my VoiceOver voice and speed", isOn: $reader.useVoiceOverVoice)
            if !reader.useVoiceOverVoice {
                Picker("Speaking speed", selection: $reader.speed) {
                    Text("Slow").tag(0.75)
                    Text("Normal").tag(1.0)
                    Text("Fast").tag(1.35)
                    Text("Fastest").tag(1.7)
                }
            }
        } label: {
            Label("Read aloud and navigate", systemImage: "speaker.wave.2")
        }
    }

    private var playTitle: String {
        switch reader.state {
        case .speaking: return "Pause reading"
        case .paused: return "Resume reading"
        case .idle: return startIndex == nil ? "Read aloud from the start"
            : (mode == .text ? "Read aloud from the cursor" : "Read aloud from the selected item")
        }
    }

    private func playPause() {
        if reader.state == .idle { reader.play(from: startIndex) } else { reader.togglePlayPause() }
    }

    private func toggleView() {
        mode = mode == .text ? .structure : .text
        announce(mode == .text ? "Text view" : "One item at a time")
    }

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
            structureList
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
                .onChange(of: reader.currentIndex) { _, index in
                    guard let index, doc.blocks.indices.contains(index) else { return }
                    scroll(proxy, to: doc.blocks[index].id)
                }
                .onChange(of: scrollTarget) { _, id in
                    if let id { scroll(proxy, to: id) }
                }
        }
    }

    @ViewBuilder
    private var structureList: some View {
        #if os(macOS)
        // A plain column, not a table, so VoiceOver reads item by item with
        // VO-Right Arrow and never asks you to interact with a table or list.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(doc.blocks.enumerated()), id: \.element.id) { index, block in
                    if !isPageMarker(block) {
                        row(block, index).padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        #else
        List(selection: $selection) {
            ForEach(Array(doc.blocks.enumerated()), id: \.element.id) { index, block in
                if !isPageMarker(block) {
                    row(block, index).tag(block.id)
                }
            }
        }
        .listStyle(.plain)
        .onKeyPress(.return) {
            guard let id = selection, let i = doc.blocks.firstIndex(where: { $0.id == id }) else { return .ignored }
            reader.play(from: i)
            return .handled
        }
        #endif
    }

    private func isPageMarker(_ block: Block) -> Bool {
        if case .pageMarker = block.kind { return true }
        return false
    }

    private func row(_ block: Block, _ index: Int) -> some View {
        BlockRow(block: block, isBeingRead: reader.currentIndex == index)
            .id(block.id)
            .accessibilityFocused($focusedBlock, equals: block.id)
            .accessibilityAction(named: "Read aloud from here") { reader.play(from: index) }
            .accessibilityAction(named: "Copy text") { copy(block) }
            .contextMenu {
                Button("Read aloud from here") { reader.play(from: index) }
                Button("Copy text") { copy(block) }
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
        // Not wrapped in a group: VoiceOver moves straight from row to row
        // with no table to interact with. Each row says its column names.
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
                .accessibilityLabel(Block.tableRowLabel(rows: rows, row: r, hasHeaderRow: hasHeaderRow))
            }
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

// MARK: - Menu bar commands

/// What the Document menu can do for the window that's in front.
struct DocCommands {
    var isSpeaking: Bool
    var playPause: () -> Void
    var stop: () -> Void
    var nextHeading: () -> Void
    var previousHeading: () -> Void
    var showHeadings: () -> Void
    var toggleView: () -> Void
}

struct DocCommandsKey: FocusedValueKey {
    typealias Value = DocCommands
}

extension FocusedValues {
    var docCommands: DocCommands? {
        get { self[DocCommandsKey.self] }
        set { self[DocCommandsKey.self] = newValue }
    }
}

/// The Document menu. Every shortcut includes Command, so none clash with
/// typing or VoiceOver. Listed in the menu bar, so VO-M finds them all.
struct DocumentMenu: View {
    @FocusedValue(\.docCommands) private var commands

    var body: some View {
        Button(commands?.isSpeaking == true ? "Pause reading" : "Read aloud") { commands?.playPause() }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(commands == nil)
        Button("Stop reading") { commands?.stop() }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(commands == nil)
        Divider()
        Button("Next heading") { commands?.nextHeading() }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(commands == nil)
        Button("Previous heading") { commands?.previousHeading() }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(commands == nil)
        Button("Go to heading…") { commands?.showHeadings() }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(commands == nil)
        Divider()
        Button("Switch between text and one item at a time") { commands?.toggleView() }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(commands == nil)
    }
}
