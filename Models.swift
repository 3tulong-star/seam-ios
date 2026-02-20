import Foundation

enum Side {
    case a
    case b
}

struct LangOption: Identifiable, Equatable, Hashable {
    let id: String      // 语言 code, 例如 "zh"
    let name: String    // 展示名, 例如 "中文"
}

let supportedLangs: [LangOption] = [
    .init(id: "zh", name: "中文"),
    .init(id: "en", name: "English"),
    .init(id: "ja", name: "日本語"),
    .init(id: "ko", name: "한국어")
]

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let side: Side
    var originalPartial: String
    var originalFinal: String?
    var translated: String?

    init(side: Side) {
        self.id = UUID()
        self.side = side
        self.originalPartial = ""
        self.originalFinal = nil
        self.translated = nil
    }
}
