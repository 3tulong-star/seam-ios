import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ConversationViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Language Selector
                languageHeader

                // Chat Area
                chatArea

                // Footer: Control Buttons
                controlDock
            }
        }
    }

    // MARK: - Header
    private var languageHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Seam Translate")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: vm.autoSpeak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Toggle("", isOn: $vm.autoSpeak)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack(spacing: 0) {
                Picker("Source", selection: $vm.langA) {
                    ForEach(supportedLangs) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                Picker("Target", selection: $vm.langB) {
                    ForEach(supportedLangs) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.89, green: 0.89, blue: 0.91))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(white: 1, opacity: 0.94).blur(radius: 0.5))
        .overlay(
            VStack {
                Spacer()
                Divider()
            }
        )
    }

    // MARK: - Chat Area
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(vm.messages) { m in
                        MessageBubble(m: m) {
                            vm.speakMessage(m)
                        }
                        .id(m.id)
                    }
                    
                    if vm.isHoldingA || vm.isHoldingB {
                        HStack {
                            if vm.isHoldingB { Spacer() }
                            Text(vm.partialText.isEmpty ? "..." : vm.partialText)
                                .font(.system(size: 14))
                                .italic()
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                            if vm.isHoldingA { Spacer() }
                        }
                        .id("bottom_partial")
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.messages.count) { newValue in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.partialText) { newValue in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if !vm.partialText.isEmpty {
                proxy.scrollTo("bottom_partial", anchor: .bottom)
            } else if let lastId = vm.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Footer
    private var controlDock: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                HoldToTalkButton(
                    title: "A 按住说",
                    isHolding: vm.isHoldingA,
                    color: Color(red: 0.56, green: 0.56, blue: 0.58)
                ) { pressing in
                    vm.pressAChanged(pressing)
                }

                HoldToTalkButton(
                    title: "B 按住说",
                    isHolding: vm.isHoldingB,
                    color: .blue
                ) { pressing in
                    vm.pressBChanged(pressing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 34) // For Home Indicator
            .background(Color(white: 1, opacity: 0.94))
        }
    }
}

// MARK: - Subviews

struct MessageBubble: View {
    let m: ChatMessage
    let onSpeak: () -> Void

    var body: some View {
        HStack {
            if m.side == .b { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                if let original = m.originalFinal {
                    Text(original)
                        .font(.system(size: 13))
                        .opacity(0.7)
                }
                
                HStack(alignment: .bottom, spacing: 8) {
                    Text(m.translated ?? "...")
                        .font(.system(size: 16))
                    
                    if m.translated != nil {
                        Button(action: onSpeak) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(m.side == .a ? .primary : .white)
                        .opacity(0.6)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(m.side == .a ? Color(red: 0.91, green: 0.91, blue: 0.92) : Color.blue)
            .foregroundColor(m.side == .a ? .black : .white)
            .clipShape(BubbleShape(side: m.side))
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

            if m.side == .a { Spacer(minLength: 40) }
        }
    }
}

struct BubbleShape: Shape {
    let side: Side
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, 
                               byRoundingCorners: [.topLeft, .topRight, side == .a ? .bottomRight : .bottomLeft], 
                               cornerRadii: CGSize(width: 18, height: 18))
        return Path(path.cgPath)
    }
}

struct HoldToTalkButton: View {
    let title: String
    let isHolding: Bool
    let color: Color
    let onPressingChanged: (Bool) -> Void

    var body: some View {
        Text(isHolding ? "正在听..." : title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isHolding ? color.opacity(0.8) : color)
            .cornerRadius(27)
            .scaleEffect(isHolding ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isHolding)
            .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
                onPressingChanged(pressing)
            }, perform: {})
    }
}
