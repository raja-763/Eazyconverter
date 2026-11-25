import SwiftUI
import UniformTypeIdentifiers
import NaturalLanguage

#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    var cgImageValue: CGImage? {
        #if os(iOS)
        return cgImage
        #else
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

enum Pasteboard {
    /// Write-only. The app never reads the clipboard.
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Speaks a status message through VoiceOver without moving focus
/// (the native equivalent of a web status message, WCAG 2.2 SC 4.1.3).
@MainActor
func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
}

extension UTType {
    static let docx = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx") ?? .data
    static let markdownText = UTType("net.daringfireball.markdown")
        ?? UTType(filenameExtension: "md") ?? .plainText
}

enum Language {
    /// BCP 47 code of the main language of some text, detected on device.
    static func detect(_ text: String) -> String {
        let sample = String(text.prefix(4000))
        guard !sample.isEmpty,
              let lang = NLLanguageRecognizer.dominantLanguage(for: sample) else { return "en" }
        return lang == .undetermined ? "en" : lang.rawValue
    }
}

extension AccessibilityHeadingLevel {
    init(level: Int) {
        switch level {
        case 1: self = .h1
        case 2: self = .h2
        case 3: self = .h3
        case 4: self = .h4
        case 5: self = .h5
        case 6: self = .h6
        default: self = .unspecified
        }
    }
}
