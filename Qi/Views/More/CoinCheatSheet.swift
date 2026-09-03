import SwiftUI

/// 金币作弊面板。
///
/// 她说的：「再来一个作弊系统，就是关于我的金币，
/// **点击目前的金币栏我可以随意增减我的金币数量。**」
///
/// ⚠️ **这是她自己的账，不用拦着。** 不加确认、不加上限、不记"作弊过"，
/// 想清零就清零，想给自己一万就一万——币是她给她自己发的，
/// 这个 App 里没有第二个人会因为这个吃亏。
struct CoinCheatSheet: View {

    @ObservedObject var store: ClawdStore
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 直接填一个数
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(HomePalette.amber).frame(width: 11, height: 11)
                Text("\(store.coins)")
                    .font(HomeType.number(30, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .contentTransition(.numericText())
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.coins)
            .padding(.top, 6)

            // 加减。⚠️ **减到 0 就停**，负数金币买不了东西也说不通。
            HStack(spacing: 8) {
                ForEach([-100, -10, 10, 100], id: \.self) { d in
                    Button {
                        bump(d)
                    } label: {
                        Text(d > 0 ? "+\(d)" : "\(d)")
                            .font(.app(13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(d > 0
                                          ? app.settings.accentColor.opacity(0.22)
                                          : Theme.softFillDeep)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textMain(scheme))
                }
            }

            HStack(spacing: 8) {
                TextField("直接填一个数", text: $typed)
                    .keyboardType(.numberPad)
                    .font(.app(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.softFillDeep)
                    )

                Button("改成这个") {
                    // 过滤掉贴进来的非数字，免得整串被判无效
                    let n = Int(typed.filter(\.isNumber)) ?? 0
                    store.coins = n
                    typed = ""
                    tick()
                }
                .font(.app(13, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(typed.isEmpty
                                 ? Theme.textMuted(scheme) : app.settings.accentColor)
                .disabled(typed.isEmpty)
            }

            Text("你自己的账，随便改。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func bump(_ d: Int) {
        store.coins = max(0, store.coins + d)
        tick()
    }

    private func tick() {
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
