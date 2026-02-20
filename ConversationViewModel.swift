import SwiftUI
import Combine
import AVFoundation

@MainActor
final class ConversationViewModel: ObservableObject {
    private let wsURL = URL(string: "wss://tulong.zeabur.app/api/v1/asr/realtime")!
    private let httpBase = URL(string: "https://tulong.zeabur.app")!

    @Published var langA: LangOption = supportedLangs.first(where: { $0.id == "zh" })!
    @Published var langB: LangOption = supportedLangs.first(where: { $0.id == "en" })!

    @Published var autoSpeak: Bool = true
    @Published var isHoldingA = false
    @Published var isHoldingB = false
    @Published var messages: [ChatMessage] = []

    private let wsClient = RealtimeWSClient()
    private let streamer = AudioStreamer()
    private let tts = AVSpeechSynthesizer()

    private var activeSide: Side? = nil
    private var activeMsgId: UUID? = nil

    // MARK: - Debug info
    private var holdStartedAt: Date? = nil

    private func log(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let ts = formatter.string(from: Date())
        print("[VM][\(ts)] \(msg)")
    }

    // MARK: - Finalize control
    private var isFinalizing: Bool = false

    init() {
        streamer.onAudioBuffer = { [weak self] base64 in
            self?.wsClient.sendAudio(base64: base64)
        }

        wsClient.onPartialText = { [weak self] text in
            Task { @MainActor in self?.applyPartial(text) }
        }

        wsClient.onFinalText = { [weak self] text in
            Task { @MainActor in await self?.applyFinal(text) }
        }

        wsClient.onError = { msg in
            print("WS error:", msg)
        }
    }

    // MARK: - UI events

    func pressAChanged(_ pressing: Bool) {
        isHoldingA = pressing
        if pressing {
            holdStartedAt = Date()
            log("A press down")
            start(side: .a)
        } else {
            let dur = holdStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            log(String(format: "A press up (held %.2fs)", dur))
            holdStartedAt = nil
            stopAndFinalize()
        }
    }

    func pressBChanged(_ pressing: Bool) {
        isHoldingB = pressing
        if pressing {
            holdStartedAt = Date()
            log("B press down")
            start(side: .b)
        } else {
            let dur = holdStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            log(String(format: "B press up (held %.2fs)", dur))
            holdStartedAt = nil
            stopAndFinalize()
        }
    }

    func swapLanguages() {
        log("Swapping languages: \(langA.name) <-> \(langB.name)")
        let temp = langA
        langA = langB
        langB = temp
    }

    func swapLanguages() {
        log("Swapping languages: \(langA.name) <-> \(langB.name)")
        let temp = langA
        langA = langB
        langB = temp
    }

    func speakMessage(_ m: ChatMessage) {
        guard let text = m.translated, !text.isEmpty else { return }
        let target = (m.side == .a) ? langB.id : langA.id
        speak(text: text, lang: target)
    }

    // MARK: - ASR core

    private func start(side: Side) {
        // Avoid starting a new utterance while we are waiting for the previous final.
        guard activeSide == nil, isFinalizing == false else {
            log("Start ignored (activeSide=\(String(describing: activeSide)), isFinalizing=\(isFinalizing))")
            return
        }

        activeSide = side
        let msg = ChatMessage(side: side)
        messages.append(msg)
        activeMsgId = msg.id

        let sourceLang = (side == .a) ? langA.id : langB.id
        log("WS connecting to: \(wsURL.absoluteString) lang: \(sourceLang)")
        wsClient.connect(url: wsURL, lang: sourceLang)

        do {
            try streamer.start()
            log("Streamer started")
        } catch {
            log("Audio start error: \(error)")
        }
    }

    /// Stop recording and ask server to finalize, but keep WS open until final arrives.
    private func stopAndFinalize() {
        log("Stopping streamer and finishing WS (wait final)")
        streamer.stop()

        isFinalizing = true
        wsClient.finish()

        // Fallback: if final doesn't arrive soon, force cleanup to avoid hanging.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.isFinalizing {
                self.log("Final timeout, force disconnect")
                self.isFinalizing = false
                self.cleanupSession()
            }
        }
    }

    private func cleanupSession() {
        wsClient.disconnect()
        activeSide = nil
        activeMsgId = nil
    }

    private func applyPartial(_ text: String) {
        guard let id = activeMsgId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].originalPartial = text
    }

    private func applyFinal(_ text: String) async {
        log("ASR Final received: \(text)")

        // Final received, we can leave finalizing state now.
        isFinalizing = false

        guard let idx = messages.indices.last else {
            cleanupSession()
            return
        }

        messages[idx].originalFinal = text
        messages[idx].originalPartial = ""

        let side = messages[idx].side
        let source = (side == .a) ? langA.id : langB.id
        let target = (side == .a) ? langB.id : langA.id

        do {
            log("Translating (\(source) -> \(target))...")
            let translated = try await translate(text: text, source: source, target: target)
            log("Translation result: \(translated)")
            messages[idx].translated = translated
            if autoSpeak {
                log("Auto-speaking...")
                speak(text: translated, lang: target)
            }
        } catch {
            log("Translate error: \(error)")
            messages[idx].translated = "[翻译失败]"
        }

        // Now safe to close the WS session.
        cleanupSession()
    }

    // MARK: - 翻译

    private func translate(text: String, source: String, target: String) async throws -> String {
        let endpoint = httpBase.appendingPathComponent("/api/v1/translate/text")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "source_lang": source,
            "target_lang": target,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Translate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "bad status: \(s)"])
        }

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["translation"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 系统 TTS

    private func speak(text: String, lang: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5

        if lang == "zh" {
            // 尝试指定 Tingting 普通话
            if let v = AVSpeechSynthesisVoice(identifier: "com.apple.voice.super-compact.zh-CN.Tingting") {
                u.voice = v
            } else {
                u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            }
        } else {
            let locale: String
            switch lang {
            case "ja": locale = "ja-JP"
            case "ko": locale = "ko-KR"
            default:   locale = "en-US"
            }
            u.voice = AVSpeechSynthesisVoice(language: locale)
        }

        log("Speaking (lang: \(lang), voice: \(u.voice?.name ?? "default"))")
        tts.speak(u)
    }
}
