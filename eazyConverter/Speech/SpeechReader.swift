import Foundation
import AVFoundation

/// Reads the document aloud one block at a time with the system's on-device voices.
/// It only speaks when asked, and can follow your VoiceOver voice and rate.
@MainActor
final class SpeechReader: NSObject, ObservableObject {
    enum State { case idle, speaking, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentIndex: Int?
    /// 0.5 = slow, 1 = normal, 2 = fast.
    @Published var speed: Double = 1.0
    /// Use the voice and rate chosen in VoiceOver settings.
    @Published var useVoiceOverVoice = true

    private let synth = AVSpeechSynthesizer()
    private var blocks: [Block] = []
    private var language = "en"

    override init() {
        super.init()
        synth.delegate = self
    }

    func load(_ doc: DocumentModel?) {
        stop()
        blocks = doc?.blocks ?? []
        language = doc?.language ?? "en"
    }

    func play(from index: Int? = nil) {
        guard !blocks.isEmpty else { return }
        if state == .paused, index == nil {
            synth.continueSpeaking()
            state = .speaking
            return
        }
        synth.stopSpeaking(at: .immediate)
        speak(at: index ?? currentIndex ?? 0)
    }

    func pause() {
        guard state == .speaking else { return }
        synth.pauseSpeaking(at: .word)
        state = .paused
    }

    func togglePlayPause() {
        state == .speaking ? pause() : play()
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        state = .idle
        currentIndex = nil
    }

    func nextSection() { jumpToHeading(forward: true) }
    func previousSection() { jumpToHeading(forward: false) }

    private func jumpToHeading(forward: Bool) {
        guard !blocks.isEmpty else { return }
        let start = currentIndex ?? (forward ? -1 : blocks.count)
        let range: [Int] = forward ? Array((start + 1)..<blocks.count).filter { $0 >= 0 }
                                   : Array((0..<max(start, 0)).reversed())
        if let target = range.first(where: { blocks[$0].isHeading }) {
            synth.stopSpeaking(at: .immediate)
            speak(at: target)
        } else {
            announce(forward ? "No more headings" : "No earlier headings")
        }
    }

    private func speak(at index: Int) {
        guard blocks.indices.contains(index) else { stop(); return }
        currentIndex = index
        let text = blocks[index].spokenText
        guard !text.isEmpty else { speakNext(); return }

        let utterance = AVSpeechUtterance(string: text)
        if useVoiceOverVoice {
            utterance.prefersAssistiveTechnologySettings = true
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            let base = Double(AVSpeechUtteranceDefaultSpeechRate)
            let rate = min(max(base * speed, Double(AVSpeechUtteranceMinimumSpeechRate)),
                           Double(AVSpeechUtteranceMaximumSpeechRate))
            utterance.rate = Float(rate)
        }
        utterance.postUtteranceDelay = blocks[index].isHeading ? 0.35 : 0.15
        #if os(iOS)
        // Speak even when the ring/silent switch is on silent, like an audiobook.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        state = .speaking
        synth.speak(utterance)
    }

    private func speakNext() {
        guard let i = currentIndex else { return }
        if i + 1 < blocks.count {
            speak(at: i + 1)
        } else {
            state = .idle
            currentIndex = nil
            announce("End of document")
        }
    }
}

extension SpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.state == .speaking else { return }
            self.speakNext()
        }
    }
}
