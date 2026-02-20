import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ConversationViewModel()

    var body: some View {
        VStack(spacing: 12) {

            // 顶部：语言对 + Auto 开关
            HStack(spacing: 12) {
                Picker("A", selection: $vm.langA) {
                    ForEach(supportedLangs) { opt in
                        Text(opt.name).tag(opt)
                    }
                }
                .pickerStyle(.menu)

                Image(systemName: "arrow.left.arrow.right")

                Picker("B", selection: $vm.langB) {
                    ForEach(supportedLangs) { opt in
                        Text(opt.name).tag(opt)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: vm.autoSpeak ? "speaker.wave.2.fill"
                                                   : "speaker.slash.fill")
                    Toggle("", isOn: $vm.autoSpeak)
                        .labelsHidden()
                }
            }

            // 消息区 + 自动滚到底
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { m in
                            bubble(m)
                                .id(m.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    guard let last = vm.messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            // 底部两个按钮
            HStack(spacing: 12) {
                holdButton(title: "A 按住说", isHolding: vm.isHoldingA, color: .blue) {
                    vm.pressAChanged($0)
                }
                holdButton(title: "B 按住说", isHolding: vm.isHoldingB, color: .green) {
                    vm.pressBChanged($0)
                }
            }
            .frame(height: 56)
        }
        .padding()
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.side == .b { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                Text(m.originalFinal ?? m.originalPartial)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(m.translated ?? "…")
                        .font(.system(size: 17, weight: .semibold))

                    Spacer(minLength: 8)

                    Button {
                        vm.speakMessage(m)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(m.translated == nil)
                    .opacity(m.translated == nil ? 0.3 : 1.0)
                }
            }
            .padding(12)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .leading)
            .background(m.side == .a ? Color.blue.opacity(0.08) : Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if m.side == .a { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 2)
    }

    private func holdButton(
        title: String,
        isHolding: Bool,
        color: Color,
        onPressingChanged: @escaping (Bool) -> Void
    ) -> some View {
        Text(isHolding ? "正在听…" : title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHolding ? color.opacity(0.85) : color)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onLongPressGesture(minimumDuration: 0.1, pressing: onPressingChanged, perform: {})
    }
}
