import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The whole document as one block of text, so VoiceOver users can read it with the
/// arrow keys (line, word, character), like any text area. Headings, tables and pages
/// are still reachable through custom rotors.
struct ReadingText {
    struct Mark { let range: NSRange; let label: String }

    let text: NSAttributedString
    /// Character range of each block, in block order.
    let ranges: [NSRange]
    let headings: [Mark]
    let tables: [Mark]
    let pages: [Mark]

    init(_ doc: DocumentModel) {
        let out = NSMutableAttributedString()
        var ranges: [NSRange] = []
        var headings: [Mark] = [], tables: [Mark] = [], pages: [Mark] = []

        for (i, block) in doc.blocks.enumerated() {
            let start = out.length
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 10
            var font = Fonts.body
            var line = block.text

            switch block.kind {
            case .heading(let level):
                font = Fonts.heading(level)
                style.paragraphSpacingBefore = level <= 2 ? 14 : 8
            case .paragraph:
                break
            case .listItem(let ordered, let number, let depth):
                let indent = CGFloat(depth) * 24
                style.firstLineHeadIndent = indent
                style.headIndent = indent + 24
                style.paragraphSpacing = 4
                line = (ordered ? "\(number). " : "• ") + block.text
            case .table(let rows, let header):
                line = block.tableLines(rows: rows, hasHeaderRow: header).joined(separator: "\n")
            case .code:
                font = Fonts.mono
            case .pageMarker(let page):
                line = "Page \(page)"
                font = Fonts.caption
            }

            if i < doc.blocks.count - 1 { line += "\n" }
            out.append(NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: Fonts.textColor,
                .paragraphStyle: style
            ]))
            let range = NSRange(location: start, length: (line as NSString).length)
            ranges.append(range)

            let visible = NSRange(location: start, length: max(0, range.length - (line.hasSuffix("\n") ? 1 : 0)))
            switch block.kind {
            case .heading(let level): headings.append(Mark(range: visible, label: "\(block.text), level \(level)"))
            case .table(let rows, _): tables.append(Mark(range: visible, label: "Table, \(rows.count) rows"))
            case .pageMarker(let page): pages.append(Mark(range: visible, label: "Page \(page)"))
            default: break
            }
        }
        text = out
        self.ranges = ranges
        self.headings = headings
        self.tables = tables
        self.pages = pages
    }

    /// The block that contains a character position (for "read aloud from the cursor").
    func blockIndex(at location: Int) -> Int? {
        guard !ranges.isEmpty else { return nil }
        return ranges.firstIndex { NSLocationInRange(location, $0) } ?? (location >= text.length ? ranges.count - 1 : nil)
    }
}

extension Block {
    /// One line per table row, each saying its column names with its values.
    func tableLines(rows: [[String]], hasHeaderRow: Bool) -> [String] {
        let cols = rows.first?.count ?? 0
        var lines = ["Table, \(rows.count) rows, \(cols) columns."]
        for (r, cells) in rows.enumerated() {
            if hasHeaderRow {
                if r == 0 { lines.append("Column headers: " + cells.joined(separator: ", ")); continue }
                let headers = rows[0]
                let pairs = cells.enumerated().map { i, value in
                    let name = i < headers.count && !headers[i].isEmpty ? headers[i] : "Column \(i + 1)"
                    return "\(name): \(value.isEmpty ? "blank" : value)"
                }
                lines.append("Row \(r) of \(rows.count - 1). " + pairs.joined(separator: ", "))
            } else {
                lines.append("Row \(r + 1) of \(rows.count). " + cells.map { $0.isEmpty ? "blank" : $0 }.joined(separator: ", "))
            }
        }
        lines.append("End of table.")
        return lines
    }
}

private enum Fonts {
    #if os(iOS)
    static var body: UIFont { .preferredFont(forTextStyle: .body) }
    static var caption: UIFont { .preferredFont(forTextStyle: .footnote) }
    static var mono: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
    }
    static var textColor: UIColor { .label }
    static func heading(_ level: Int) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style(level))
        guard let bold = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: bold, size: 0)
    }
    private static func style(_ level: Int) -> UIFont.TextStyle {
        [.largeTitle, .title1, .title2, .title3, .headline, .headline][max(0, min(level, 6) - 1)]
    }
    #else
    static var body: NSFont { .preferredFont(forTextStyle: .body) }
    static var caption: NSFont { .preferredFont(forTextStyle: .footnote) }
    static var mono: NSFont { .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
    static var textColor: NSColor { .labelColor }
    static func heading(_ level: Int) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style(level))
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.bold), size: 0) ?? base
    }
    private static func style(_ level: Int) -> NSFont.TextStyle {
        [.largeTitle, .title1, .title2, .title3, .headline, .headline][max(0, min(level, 6) - 1)]
    }
    #endif
}

// MARK: - Mac

#if os(macOS)
struct ReadingTextView: NSViewRepresentable {
    let reading: ReadingText
    @Binding var caret: Int
    @Binding var jump: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        // Editable so the arrow keys move a text cursor that VoiceOver follows;
        // every change is refused in the delegate, so the text can't be altered.
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true
        tv.allowsUndo = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 20, height: 16)
        tv.setAccessibilityLabel("Document text, read only")
        tv.setAccessibilityHelp("Use the arrow keys to read by line, word or character. Use the rotor for headings, tables and pages.")
        context.coordinator.load(reading, into: tv)
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if context.coordinator.loaded != reading.text.string {
            context.coordinator.load(reading, into: tv)
        }
        if let location = jump {
            let r = NSRange(location: min(location, tv.string.utf16.count), length: 0)
            tv.setSelectedRange(r)
            tv.scrollRangeToVisible(r)
            tv.window?.makeFirstResponder(tv)
            DispatchQueue.main.async { jump = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReadingTextView
        var loaded = ""
        private var sources: [RotorSource] = []

        init(_ parent: ReadingTextView) { self.parent = parent }

        func load(_ reading: ReadingText, into tv: NSTextView) {
            tv.textStorage?.setAttributedString(reading.text)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            loaded = reading.text.string
            sources = [("Headings", reading.headings), ("Tables", reading.tables), ("Pages", reading.pages)]
                .filter { !$0.1.isEmpty }
                .map { RotorSource(name: $0.0, marks: $0.1, textView: tv) }
            tv.setAccessibilityCustomRotors(sources.map { NSAccessibilityCustomRotor(label: $0.name, itemSearchDelegate: $0) })
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            announce("Read only")
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let location = tv.selectedRange().location
            DispatchQueue.main.async { self.parent.caret = location }
        }
    }

    /// Feeds one VoiceOver custom rotor (Headings, Tables or Pages).
    final class RotorSource: NSObject, NSAccessibilityCustomRotorItemSearchDelegate {
        let name: String
        let marks: [ReadingText.Mark]
        weak var textView: NSTextView?

        init(name: String, marks: [ReadingText.Mark], textView: NSTextView) {
            self.name = name
            self.marks = marks
            self.textView = textView
        }

        func rotor(_ rotor: NSAccessibilityCustomRotor,
                   resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters) -> NSAccessibilityCustomRotor.ItemResult? {
            guard let tv = textView else { return nil }
            let forward = searchParameters.searchDirection == .next
            let current = searchParameters.currentItem?.targetRange.location ?? (forward ? -1 : Int.max)
            let filter = searchParameters.filterString.lowercased()
            let candidates = filter.isEmpty ? marks : marks.filter { $0.label.lowercased().contains(filter) }
            guard let mark = forward ? candidates.first(where: { $0.range.location > current })
                                     : candidates.last(where: { $0.range.location < current }) else { return nil }
            let result = NSAccessibilityCustomRotor.ItemResult(targetElement: tv)
            result.targetRange = mark.range
            result.customLabel = mark.label
            return result
        }
    }
}
#endif

// MARK: - iPhone and iPad

#if os(iOS)
struct ReadingTextView: UIViewRepresentable {
    let reading: ReadingText
    @Binding var caret: Int
    @Binding var jump: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .systemBackground
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        tv.delegate = context.coordinator
        tv.accessibilityLabel = "Document text"
        tv.accessibilityHint = "Swipe up or down to read by line, word or character, or use the arrow keys. Use the rotor for headings, tables and pages."
        context.coordinator.load(reading, into: tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loaded != reading.text.string {
            context.coordinator.load(reading, into: tv)
        }
        if let location = jump {
            let r = NSRange(location: min(location, tv.text.utf16.count), length: 0)
            tv.selectedRange = r
            tv.scrollRangeToVisible(r)
            UIAccessibility.post(notification: .layoutChanged, argument: tv)
            DispatchQueue.main.async { jump = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReadingTextView
        var loaded = ""

        init(_ parent: ReadingTextView) { self.parent = parent }

        func load(_ reading: ReadingText, into tv: UITextView) {
            tv.attributedText = reading.text
            loaded = reading.text.string
            tv.accessibilityCustomRotors = [("Headings", reading.headings), ("Tables", reading.tables), ("Pages", reading.pages)]
                .filter { !$0.1.isEmpty }
                .map { name, marks in rotor(name, marks, tv) }
        }

        private func rotor(_ name: String, _ marks: [ReadingText.Mark], _ tv: UITextView) -> UIAccessibilityCustomRotor {
            UIAccessibilityCustomRotor(name: name) { [weak tv] predicate in
                guard let tv else { return nil }
                let forward = predicate.searchDirection == .next
                var current = forward ? -1 : Int.max
                if let range = predicate.currentItem.targetRange {
                    current = tv.offset(from: tv.beginningOfDocument, to: range.start)
                }
                guard let mark = forward ? marks.first(where: { $0.range.location > current })
                                         : marks.last(where: { $0.range.location < current }),
                      let start = tv.position(from: tv.beginningOfDocument, offset: mark.range.location),
                      let end = tv.position(from: start, offset: mark.range.length),
                      let textRange = tv.textRange(from: start, to: end) else { return nil }
                tv.selectedRange = NSRange(location: mark.range.location, length: 0)
                tv.scrollRangeToVisible(mark.range)
                return UIAccessibilityCustomRotorItemResult(targetElement: tv, targetRange: textRange)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let location = textView.selectedRange.location
            DispatchQueue.main.async { self.parent.caret = location }
        }
    }
}
#endif
