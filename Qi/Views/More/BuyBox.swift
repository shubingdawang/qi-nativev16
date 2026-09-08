import SwiftUI

/// 买家具之前挑一下：**几件、摆进哪一间。**
///
/// 她说的：「在添加家具的时候可以长按选择添加到哪里还有购买数量。」
///
/// ## 为什么房间要在这儿挑
///
/// 买下来会自动归到「它该在的那间」（床进卧室、锅进厨房），
/// 那只是个默认。她报的「家具分区太绝对了，桌子也可以摆在卧室，
/// 但现在只能摆在餐厅」——买完再一件件搬过去，
/// 买五张凳子就要搬五次。**在买的时候说一句就完了。**
struct BuyBox: View {

    let kind: FurnitureKind
    @ObservedObject var store: ClawdStore
    /// 买完了告诉外面：真买到几件、放进了哪一间
    var done: (Int, HomeRoom) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var count = 1
    @State private var room: HomeRoom = .living

    /// 手上的币最多买得起几件。**至少给 1**，
    /// 不然一件都买不起的时候步进器的范围会是空的，直接崩。
    private var most: Int {
        guard kind.price > 0 else { return 20 }
        return max(1, min(20, store.coins / kind.price))
    }

    private var total: Int { kind.price * count }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        FurnitureThumb(kind: kind, height: 44, scale: 1.5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.name)
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text("单价 " + String(kind.price) + " 币　已有 "
                                 + String(store.count(of: kind.id)) + " 件")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Spacer(minLength: 0)
                    }

                    Stepper(value: $count, in: 1...most) {
                        HStack {
                            Text("数量").font(.app(13))
                            Spacer()
                            Text(String(count))
                                .font(HomeType.number(15))
                                .foregroundStyle(app.settings.accentColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("放进哪一间").font(.app(13))
                        Picker("放进哪一间", selection: $room) {
                            ForEach(HomeRoom.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Spacer(minLength: 0)

                    Button {
                        let got = store.buy(kind, count: count, room: room)
                        done(got, room)
                        dismiss()
                    } label: {
                        Text("买下来　共 " + String(total) + " 币")
                            .font(.app(14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14,
                                                         style: .continuous)
                                .fill(app.settings.accentColor.opacity(0.18)))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.coins < kind.price)
                    .opacity(store.coins < kind.price ? 0.45 : 1)
                }
                .padding(18)
            }
            .navigationTitle("买点什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { dismiss() }
                }
            }
        }
        // 默认落在它该在的那间，她想换再换（见上面那段）
        .onAppear { room = HomeRoom.home(for: kind) }
    }
}
