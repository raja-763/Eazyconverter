import Foundation
import Vision
import ImageIO

/// Reads text from pictures with Apple's Vision framework.
/// Recognition runs entirely on the device; nothing is uploaded.
enum OCR {
    enum OCRError: Error, LocalizedError {
        case unreadableImage
        var errorDescription: String? { "The app couldn't open this picture." }
    }

    static func cgImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary)
        else { throw OCRError.unreadableImage }
        return image
    }

    /// Returns visual lines, top to bottom, with relative sizes and gaps
    /// so StructureGuesser can rebuild headings and paragraphs.
    static func lines(in image: CGImage) throws -> [StyledLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
            .sorted {
                // Vision uses a bottom-left origin: higher Y is nearer the top.
                abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                    ? $0.boundingBox.midY > $1.boundingBox.midY
                    : $0.boundingBox.minX < $1.boundingBox.minX
            }

        let heights = observations.map(\.boundingBox.height).sorted()
        let median = heights.isEmpty ? 0.02 : max(heights[heights.count / 2], 0.001)

        var lines: [StyledLine] = []
        var previousBottom: CGFloat?
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let box = obs.boundingBox
            let gap = previousBottom.map { ($0 - box.maxY) / median } ?? 0
            lines.append(StyledLine(
                text: text,
                size: 12 * box.height / median,   // relative size; 12 = body text
                gapAbove: max(0, gap)
            ))
            previousBottom = box.minY
        }
        return lines
    }

    static func blocks(in image: CGImage) throws -> [Block] {
        StructureGuesser.blocks(from: try lines(in: image))
    }
}
