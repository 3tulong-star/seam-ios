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
        pressing ? start(side: .a) : stop()
    }

    func pressBChanged(_ pressing: Bool) {
        isHoldingB = pressing
        pressing ? start(side: .b) : stop()
    }

    func speakMessage(_ m: ChatMessage) {
        guard let text = m.translated, !text.isEmpty else { return }
        let target = (m.side == .a) ? langB.id : langA.id
        speak(text: text, lang: target)
    }

    // MARK: - ASR core

    private func start(side: Side) {
        guard activeSide == nil else { return }    // 防止 A/B 同时按

        activeSide = side
        let msg = ChatMessage(side: side)
        messages.append(msg)
        activeMsgId = msg.id

        let sourceLang = (side == .a) ? langA.id : langB.id
        print("WS connecting to:", wsURL.absoluteString, "lang:", sourceLang)
        wsClient.connect(url: wsURL, lang: sourceLang)

        do { try streamer.start() }
        catch { print("Audio start error:", error) }
    }

    private func stop() {
        streamer.stop()
        wsClient.finish()
        wsClient.disconnect() // 清理干净，避免下次 connect 报 socket not connected
        activeSide = nil
        activeMsgId = nil
    }

    private func applyPartial(_ text: String) {
        guard let id = activeMsgId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].originalPartial = text
    }

    private func applyFinal(_ text: String) async {
        guard let idx = messages.indices.last else { return }
        messages[idx].originalFinal = text
        messages[idx].originalPartial = ""

        let side = messages[idx].side
        let source = (side == .a) ? langA.id : langB.id
        let target = (side == .a) ? langB.id : langA.id

        do {
            let translated = try await translate(text: text, source: source, target: target)
            messages[idx].translated = translated
            if autoSpeak {
                speak(text: translated, lang: target)
            }
        } catch {
            print("translate error:", error)
            messages[idx].translated = "[翻译失败]"
        }
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

        tts.speak(u)
    }
}
