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
    @Published var isHoldingSingle = false
    @Published var isLiveActive = false
    @Published var messages: [ChatMessage] = []

    // 模式：双按钮, 单按钮, 或 Live
    @Published var mode: ConversationMode = .dualButton

    // 控制语言选择弹窗
    @Published var showingPickerA = false
    @Published var showingPickerB = false

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
        setupCallbacks()
    }

    private func setupCallbacks() {
        streamer.onAudioBuffer = { [weak self] base64 in
            self?.wsClient.sendAudio(base64: base64)
        }

        wsClient.onPartialText = { [weak self] text in
            Task { @MainActor in self?.applyPartial(text) }
        }

        wsClient.onFinalEvent = { [weak self] event in
            Task { @MainActor in await self?.applyFinalEvent(event) }
        }

        wsClient.onError = { msg in
            print("WS error:", msg)
        }
    }

    // MARK: - UI events

    func pressAChanged(_ pressing: Bool) {
        guard mode == .dualButton else { return }
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
        guard mode == .dualButton else { return }
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

    func singlePressChanged(_ pressing: Bool) {
        guard mode == .singleButton else { return }
        isHoldingSingle = pressing
        if pressing {
            holdStartedAt = Date()
            log("Single button press down")
            startSingleButton()
        } else {
            let dur = holdStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            log(String(format: "Single button press up (held %.2fs)", dur))
            holdStartedAt = nil
            stopAndFinalize()
        }
    }

    func toggleLive() {
        guard mode == .live else { return }
        if isLiveActive {
            log("Stopping Live mode")
            isLiveActive = false
            stopAndFinalize()
        } else {
            log("Starting Live mode")
            isLiveActive = true
            startLive()
        }
    }

    func swapLanguages() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

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
        guard activeSide == nil, isFinalizing == false else { return }

        activeSide = side
        let msg = ChatMessage(side: side)
        messages.append(msg)
        activeMsgId = msg.id

        let wsMode = mode == .dualButton ? "dual_button" : (mode == .singleButton ? "single_button" : "live")
        let cfg = RealtimeConfig(mode: wsMode, leftLang: langA.id, rightLang: langB.id)
        
        log("WS connecting (\(wsMode)) left=\(langA.id) right=\(langB.id)")
        wsClient.connect(url: wsURL, config: cfg)

        do {
            try streamer.start()
            log("Streamer started")
        } catch {
            log("Audio start error: \(error)")
        }
    }

    private func startSingleButton() {
        start(side: .a)
    }

    private func startLive() {
        // Live 模式下，开启 VAD 或依赖服务端分句
        start(side: .a) 
    }

    private func stopAndFinalize() {
        log("Stopping streamer and finishing WS (wait final)")
        streamer.stop()
        isFinalizing = true
        wsClient.finish()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.isFinalizing {
                self.log("Final timeout, force disconnect")
                self.isFinalizing = false
                self.cleanupSession()
            }
        }
    }

    func cleanupSession() {
        wsClient.disconnect()
        activeSide = nil
        activeMsgId = nil
        isHoldingA = false
        isHoldingB = false
        isHoldingSingle = false
        // isLiveActive 不在 cleanup 里重置，由 toggleLive 控制
    }

    private func applyPartial(_ text: String) {
        guard !text.isEmpty else { return }
        // 寻找最后一个没有完成的消息，或者当前活动的消息
        if let id = activeMsgId, let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].originalPartial = text
        } else {
            // Live 模式下可能需要自动开启新消息
            let msg = ChatMessage(side: .a)
            messages.append(msg)
            activeMsgId = msg.id
            messages[messages.count-1].originalPartial = text
        }
    }

    private func applyFinalEvent(_ event: [String: Any]) async {
        log("ASR Event received: \(event)")
        
        // 如果是 legacy 模式（dualButton），走原来的 applyFinal 逻辑
        if mode == .dualButton {
            isFinalizing = false
            if let transcript = event["transcript"] as? String {
                await processFinalResult(transcript: transcript, side: activeSide ?? .a, source: (activeSide == .a ? langA.id : langB.id), target: (activeSide == .a ? langB.id : langA.id))
            }
            cleanupSession()
            return
        }

        // Single / Live 模式使用服务端提供的 ui_side
        guard let transcript = event["transcript"] as? String, !transcript.isEmpty else { return }
        
        let uiSideStr = event["ui_side"] as? String ?? "left"
        let source = event["ui_source_lang"] as? String ?? langA.id
        let target = event["ui_target_lang"] as? String ?? langB.id
        let side: Side = (uiSideStr == "right") ? .b : .a

        await processFinalResult(transcript: transcript, side: side, source: source, target: target)

        if mode == .singleButton {
            isFinalizing = false
            cleanupSession()
        } else if mode == .live {
            // Live 模式保持连接，准备下一句，开启新的活动消息 ID
            activeMsgId = nil 
        }
    }

    private func processFinalResult(transcript: String, side: Side, source: String, target: String) async {
        // 找到当前正在 partial 的消息并固定它，或者新建
        if let idx = messages.firstIndex(where: { $0.id == activeMsgId }) {
            messages[idx].side = side
            messages[idx].originalFinal = transcript
            messages[idx].originalPartial = ""
            await translateAndOptionallySpeak(index: idx, source: source, target: target)
        } else {
            let m = ChatMessage(side: side)
            messages.append(m)
            let lastIdx = messages.count - 1
            messages[lastIdx].originalFinal = transcript
            await translateAndOptionallySpeak(index: lastIdx, source: source, target: target)
        }
    }

    private func translateAndOptionallySpeak(index: Int, source: String, target: String) async {
        let text = messages[index].originalFinal ?? ""
        do {
            log("Translating (\(source) -> \(target))...")
            let translated = try await translate(text: text, source: source, target: target)
            messages[index].translated = translated
            
            // Live 模式默认不自动播放 TTS
            if autoSpeak && mode != .live {
                speak(text: translated, lang: target)
            }
        } catch {
            log("Translate error: \(error)")
            messages[index].translated = "[翻译失败]"
        }
    }

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
            throw NSError(domain: "Translate", code: 1)
        }

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["translation"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func speak(text: String, lang: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        let locale = (lang == "zh") ? "zh-CN" : (lang == "ja" ? "ja-JP" : (lang == "ko" ? "ko-KR" : "en-US"))
        u.voice = AVSpeechSynthesisVoice(language: locale)
        tts.speak(u)
    }
}
