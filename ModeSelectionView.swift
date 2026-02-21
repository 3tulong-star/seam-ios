import SwiftUI

struct ModeSelectionView: View {
    @Binding var selectedMode: ConversationMode?

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("Seam Translate")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("选择适合您的翻译模式")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)

                ScrollView {
                    VStack(spacing: 20) {
                        ModeCard(
                            title: "双按钮模式",
                            description: "人工控制左右说话时机，适合精准对话",
                            icon: "person.2.fill",
                            color: .blue
                        ) {
                            selectedMode = .dualButton
                        }

                        ModeCard(
                            title: "单按钮模式",
                            description: "轮流按下说话，自动识别语种分配左右",
                            icon: "mic.circle.fill",
                            color: .green
                        ) {
                            selectedMode = .singleButton
                        }

                        ModeCard(
                            title: "Live 模式",
                            description: "自由对话，持续识别分句，无须手动按键",
                            icon: "bolt.horizontal.circle.fill",
                            color: .orange
                        ) {
                            selectedMode = .live
                        }
                    }
                    .padding(20)
                }

                Spacer()
            }
        }
    }
}

struct ModeCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(color)
                    .cornerRadius(15)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
