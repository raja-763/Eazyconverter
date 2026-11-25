import Foundation
import Vision

/// Describes a picture with Apple's on-device Vision framework: what it likely
/// shows, how many people, faces and pets it contains, and whether it has text.
/// Nothing leaves the device. Vision gives labels rather than full sentences,
/// so the description is a list of likely contents, not a caption.
enum ImageDescriber {
    static func describe(_ image: CGImage, hasText: Bool) -> String {
        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([classify, faces, people, animals])

        var sentences: [String] = []
        let shape = image.width == image.height ? "square"
            : (image.width > image.height ? "landscape" : "portrait")
        sentences.append("A \(shape) picture, \(image.width) by \(image.height) pixels.")

        // Keep labels Vision is confident about; fall back to the top few.
        let all = classify.results ?? []
        var labels = all.filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
        if labels.isEmpty { labels = Array(all.filter { $0.confidence > 0.15 }.prefix(3)) }
        let names = labels.prefix(8).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        if !names.isEmpty {
            sentences.append("It likely shows: " + list(names) + ".")
        }

        let personCount = people.results?.count ?? 0
        let faceCount = faces.results?.count ?? 0
        if personCount > 0 || faceCount > 0 {
            var p: [String] = []
            if personCount > 0 { p.append(count(personCount, "person", "people")) }
            if faceCount > 0 { p.append(count(faceCount, "face", "faces")) }
            sentences.append("Found " + list(p) + ".")
        }

        let animalNames = (animals.results ?? []).compactMap { $0.labels.first?.identifier.lowercased() }
        if !animalNames.isEmpty {
            let grouped = Dictionary(grouping: animalNames, by: { $0 }).map { count($0.value.count, $0.key, $0.key + "s") }
            sentences.append("Found " + list(grouped.sorted()) + ".")
        }

        sentences.append(hasText ? "It contains text, shown under Text in the picture."
                                 : "No text was found in it.")
        return sentences.joined(separator: " ")
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return items[0] + " and " + items[1]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
