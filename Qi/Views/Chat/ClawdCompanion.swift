import SwiftUI

/// 蹲在输入框上方的那只 clawd。
///
/// **它不接模型，一分钱不花。** 它只是看着阿晏在干嘛，然后做对应的动作：
/// 他在想 → 头顶冒小方块；他在调工具 → 埋头干活；他在说话 → 笑；
/// 都没在忙 → 站着呼吸、偶尔眨眼。
///
/// 说到底它就是个状态指示器，只不过长得可爱一点。
struct ClawdCompanion: View {

    /// 他现在在干嘛，由外面传进来
    var busy: Bool = false
    var activity: String = ""
    /// 想说的一句话，会冒在头顶
    var line: String?

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var mood: ClawdMood = .idle
    @State private var poked = false

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                if let line, !line.isEmpty {
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(scheme == .dark
                                      ? Color.white.opacity(0.12)
                                      : Color.white.opacity(0.88))
                        )
                        .fixedSize()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                ClawdView(mood: mood, scale: 2.2)
                    .onTapGesture {
                        poked = true
                        mood = .happy
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            poked = false
                            sync()
                        }
                    }
            }
        }
        .padding(.trailing, 22)
        .animation(.easeInOut(duration: 0.25), value: line)
        .onChange(of: busy) { _, _ in sync() }
        .onChange(of: activity) { _, _ in sync() }
        .onAppear { sync() }
    }

    /// 把他的状态翻成 clawd 的动作
    private func sync() {
        guard !poked else { return }
        guard busy else {
            mood = .idle
            return
        }
        // 活动那句话里带什么词，就做什么动作
        if activity.contains("想") {
            mood = .thinking
        } else if activity.contains("说") {
            mood = .talking
        } else if activity.isEmpty {
            mood = .thinking
        } else {
            // 翻记忆、写日记、博弈、动手做事，都算在干活
            mood = .working
        }
    }
}
