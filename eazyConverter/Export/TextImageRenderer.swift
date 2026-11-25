import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Turns text into a picture (PNG). The full text is also written into the
/// PNG's Description field so the picture carries its own alt text.
enum TextImageRenderer {
    enum Theme: String, CaseIterable, Identifiable {
        case blackOnWhite, whiteOnBlack, yellowOnBlack, blackOnCream
        var id: String { rawValue }
        var name: String {
            switch self {
            case .blackOnWhite: return "Black text on white"
            case .whiteOnBlack: return "White text on black"
            case .yellowOnBlack: return "Yellow text on black"
            case .blackOnCream: return "Black text on cream"
            }
        }
        var colors: (text: CGColor, background: CGColor) {
            switch self {
            case .blackOnWhite: return (CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1))
            case .whiteOnBlack: return (CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1))
            case .yellowOnBlack: return (CGColor(red: 1, green: 0.92, blue: 0.2, alpha: 1), CGColor(gray: 0, alpha: 1))
            case .blackOnCream: return (CGColor(gray: 0, alpha: 1), CGColor(red: 1, green: 0.98, blue: 0.9, alpha: 1))
            }
        }
    }

    static func image(text: String, fontSize: CGFloat, theme: Theme, width: Int = 1200) -> CGImage? {
        let padding: CGFloat = 60
        let colors = theme.colors
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lineWidth = CGFloat(width) - padding * 2

        var laid: [(line: CTLine?, ascent: CGFloat, height: CGFloat)] = []
        for p in paragraphs {
            let lines = PDFWriter.layout(p, font: font, width: lineWidth, color: colors.text)
            if lines.isEmpty {
                laid.append((nil, 0, fontSize * 1.3))      // blank line
            } else {
                for l in lines {
                    let m = PDFWriter.metrics(l)
                    laid.append((l, m.ascent, m.height))
                }
            }
        }
        let height = Int(ceil(laid.reduce(0) { $0 + $1.height } + padding * 2))
        guard height > 0, height < 30_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(colors.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.textMatrix = .identity
        var y = CGFloat(height) - padding
        for item in laid {
            if let line = item.line {
                ctx.textPosition = CGPoint(x: padding, y: y - item.ascent)
                CTLineDraw(line, ctx)
            }
            y -= item.height
        }
        return ctx.makeImage()
    }

    /// PNG bytes with the text stored as the image's description (alt text).
    static func png(_ image: CGImage, altText: String, title: String) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let props = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: altText,
                kCGImagePropertyPNGTitle: title
            ]
        ] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
