import Foundation

/// A visual line of text with its font size, as found in a PDF, RTF file or photo.
struct StyledLine {
    var text: String
    var size: CGFloat
    var bold: Bool = false
    /// Extra vertical space above this line, in multiples of the line height (OCR only).
    var gapAbove: CGFloat = 0
}

/// Rebuilds headings, paragraphs and lists from visual lines.
/// Files like PDFs and photos carry no real structure, so this is a best guess:
/// bigger or bold short lines become headings, bullets become list items,
/// and lines are joined into paragraphs.
enum StructureGuesser {
    static func blocks(from lines: [StyledLine]) -> [Block] {
        let clean = lines
            .map { StyledLine(text: $0.text.trimmingCharacters(in: .whitespaces),
                              size: $0.size, bold: $0.bold, gapAbove: $0.gapAbove) }
        guard !clean.isEmpty else { return [] }

        // Body size = the size carrying the most characters.
        var weight: [Int: Int] = [:]
        for l in clean where !l.text.isEmpty { weight[Int(l.size.rounded()), default: 0] += l.text.count }
        let body = CGFloat(weight.max(by: { $0.value < $1.value })?.key ?? 12)

        func isHeading(_ l: StyledLine) -> Bool {
            let t = l.text
            guard !t.isEmpty, t.count <= 120, !t.hasSuffix(",") else { return false }
            if l.size >= body * 1.15 { return true }
            return l.bold && t.count <= 80 && !t.hasSuffix(".") && l.size >= body * 0.95
        }

        // Rank distinct heading sizes, largest = level 1.
        let headingSizes = Set(clean.filter(isHeading).map { Int($0.size.rounded()) }).sorted(by: >)
        func level(for l: StyledLine) -> Int {
            let index = headingSizes.firstIndex(of: Int(l.size.rounded())) ?? headingSizes.count
            // A heading at body size (bold only) sits below every larger heading.
            return min(6, index + 1 + (l.size < body * 1.15 && headingSizes.count > 1 ? 1 : 0))
        }

        let typicalLength: Int = {
            let lengths = clean.map(\.text.count).filter { $0 > 0 }.sorted()
            return lengths.isEmpty ? 60 : lengths[lengths.count * 3 / 4]
        }()

        var blocks: [Block] = []
        var para = ""
        var orderedCounter = 0

        func flushParagraph() {
            let t = para.collapsedWhitespace
            if !t.isEmpty { blocks.append(Block(kind: .paragraph, text: t)) }
            para = ""
        }

        for line in clean {
            let t = line.text
            if t.isEmpty || line.gapAbove > 0.9 { flushParagraph() }
            if t.isEmpty { continue }

            if let item = listItem(t) {
                flushParagraph()
                if item.ordered { orderedCounter += 1 } else { orderedCounter = 0 }
                blocks.append(Block(kind: .listItem(ordered: item.ordered,
                                                    number: item.ordered ? orderedCounter : 0,
                                                    depth: 0),
                                    text: item.text))
                continue
            }

            if isHeading(line) {
                flushParagraph()
                orderedCounter = 0
                // Join a heading that wrapped onto two lines.
                if case .heading(let lv)? = blocks.last?.kind, lv == level(for: line), para.isEmpty,
                   let last = blocks.last, last.text.count + t.count < 140, !last.text.hasSuffix(":") {
                    blocks[blocks.count - 1].text = last.text + " " + t
                } else {
                    blocks.append(Block(kind: .heading(level: level(for: line)), text: t))
                }
                continue
            }

            // Continue a list item that wrapped onto the next line.
            if para.isEmpty, case .listItem? = blocks.last?.kind, line.gapAbove < 0.5,
               let first = t.first, first.isLowercase {
                blocks[blocks.count - 1].text += " " + t
                continue
            }

            orderedCounter = 0
            if para.hasSuffix("-"), let first = t.first, first.isLowercase {
                para.removeLast()
                para += t
            } else {
                para += (para.isEmpty ? "" : " ") + t
            }
            // A clearly short line usually ends a paragraph.
            if t.count < Int(Double(typicalLength) * 0.65), t.last.map({ ".!?:".contains($0) }) == true {
                flushParagraph()
            }
        }
        flushParagraph()
        return blocks
    }

    /// Detects "• item", "- item", "1. item", "a) item".
    static func listItem(_ t: String) -> (ordered: Bool, text: String)? {
        let bullets: Set<Character> = ["•", "◦", "▪", "‣", "●", "○", "■", "-", "–", "*"]
        if let f = t.first, bullets.contains(f) {
            let rest = t.dropFirst().trimmingCharacters(in: .whitespaces)
            // "-" alone or "-5 degrees" is not a bullet.
            if !rest.isEmpty, t.dropFirst().first == " " || f != "-" && f != "*" && f != "–" {
                return (false, rest)
            }
        }
        if let r = t.range(of: #"^(\d{1,3}|[a-zA-Z])[.)]\s+"#, options: .regularExpression) {
            let rest = String(t[r.upperBound...])
            if !rest.isEmpty { return (true, rest) }
        }
        return nil
    }
}
