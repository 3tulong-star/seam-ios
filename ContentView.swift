import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ConversationViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()

                messagesView

                Divider()

                bottomMicBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Image(systemName: vm.autoSpeak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(.secondary)
                        Toggle("Auto", isOn: $vm.autoSpeak)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            langChip(title: "A", value: vm.langA.name)
                .overlay {
                    Picker("A", selection: $vm.langA) {
                        ForEach(supportedLangs) { opt in
                            Text(opt.name).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .opacity(0.02)
                }

            Button {
                let tmp = vm.langA
                vm.langA = vm.langB
                vm.langB = tmp
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            langChip(title: "B", value: vm.langB.name)
                .overlay {
                    Picker("B", selection: $vm.langB) {
                        ForEach(supportedLangs) { opt in
                            Text(opt.name).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .opacity(0.02)
                }

            Spacer()
        }
    }

    private func langChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.messages) { m in
                        messageCard(m)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: vm.messages.count) { _, _ in
                guard let last = vm.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func messageCard(_ m: ChatMessage) -> some View {
        HStack {
            if m.side == .b { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 10) {
                Text(m.originalFinal ?? m.originalPartial)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(m.translated ?? "…")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Button {
                        vm.speakMessage(m)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(m.translated == nil)
                    .opacity(m.translated == nil ? 0.3 : 1.0)
                }
            }
            .padding(14)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }

            if m.side == .a { Spacer(minLength: 40) }
        }
    }

    private var bottomMicBar: some View {
        HStack(spacing: 12) {
            micButton(
                title: "A",
                subtitle: vm.langA.name,
                isHolding: vm.isHoldingA,
                tint: .blue
            ) { pressing in
                vm.pressAChanged(pressing)
            }

            micButton(
                title: "B",
                subtitle: vm.langB.name,
                isHolding: vm.isHoldingB,
                tint: .green
            ) { pressing in
                vm.pressBChanged(pressing)
            }
        }
    }

    private func micButton(
        title: String,
        subtitle: String,
        isHolding: Bool,
        tint: Color,
        onPressingChanged: @escaping (Bool) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(isHolding ? "Listening…" : "Hold to speak")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)

            Text("\(title) · \(subtitle)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(isHolding ? tint.opacity(0.88) : tint)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .scaleEffect(isHolding ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHolding)
        .onLongPressGesture(minimumDuration: 0.1, pressing: onPressingChanged, perform: {})
    }
}
