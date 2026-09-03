import SwiftUI

/// 户型图：整个家摆在一张图上，一格一间。
///
/// 她说的：
/// > 外面最大的小屋可以只是里面的**反应图**……外面最大的小屋只有各个房间的选项。
///
/// 所以这一页**不画家具**，只回答三件事：
/// 家里有哪几间、**他此刻在哪一间**、每间摆了几件东西。
/// 点一间就进去。
///
/// ⚠️ 他在的那一间**要一眼看得出来**——
/// 这一页存在的头号理由就是「他在哪儿」，
/// 那件事得比「厨房有 3 件东西」显眼得多。
struct FloorPlanView: View {

    @ObservedObject var store: ClawdStore
    /// 点了哪一间
    var onEnter: (HomeRoom) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private let cols = [GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "这个家") {
                Text("\(HomeRoom.allCases.count) 间")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            LazyVGrid(columns: cols, spacing: 10) {
                // 按户型图上的位置排：公共区在左一竖列，私人区在右
                ForEach(HomeRoom.allCases.sorted {
                    ($0.slot.col, $0.slot.row) < ($1.slot.col, $1.slot.row)
                }) { r in
                    cell(r)
                }
            }

            Text(MD.inline("点击房间进入查看。clawd 的所在房间由程序自动切换，打开小屋时默认进入其当前所在的房间。"))
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.leading, 4)
        }
    }

    private func cell(_ r: HomeRoom) -> some View {
        let here = store.clawdRoom == r
        let n = store.count(in: r)
        return Button {
            onEnter(r)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: r.icon)
                        .font(.app(15))
                        .foregroundStyle(here ? app.settings.accentColor
                                         : Theme.textSoft(scheme))
                    Text(r.rawValue)
                        .heading(14)
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer(minLength: 0)
                }

                // 他在这一间：**摆一只小 clawd 上去**。
                // 写一行「他在这儿」也行，但一眼扫过去认图比认字快得多。
                if here {
                    HStack(spacing: 6) {
                        ClawdView(mood: .idle, scale: 1.05)   // 0.7 × 1.5
                        Text(store.clawdDoing.line)
                            .font(.app(10.5))
                            .foregroundStyle(app.settings.accentColor)
                            .lineLimit(1)
                    }
                } else {
                    Text(n > 0 ? "\(n) 件东西" : "还空着")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(here
                          ? app.settings.accentColor.opacity(0.14)
                          : Theme.softFillDeep)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(here
                                  ? app.settings.accentColor.opacity(0.55)
                                  : Color.clear,
                                  lineWidth: 1.2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 屋子左上角那个头像 + 一行「他在干嘛」。
///
/// 她要的：「小屋左边有一个 clawd 的头像，下面写着他在干嘛，
/// 比如正在装修中、正在吃下午茶中。」
///
/// ⚠️ 那一行**是他真在做的事**，不是随机台词。
/// 随机台词会说谎——她看到「正在装修」结果屋里什么都没动，
/// 这一行从此就不值得看了。
struct ClawdBadge: View {

    @ObservedObject var store: ClawdStore
    /// 她此刻在看哪一间。跟他不在同一间的时候要说出来
    var viewing: HomeRoom?
    /// 点头像 = 跳到他那一间
    var onFollow: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var elsewhere: Bool {
        guard let viewing else { return false }
        return viewing != store.clawdRoom
    }

    var body: some View {
        Button(action: onFollow) {
            VStack(spacing: 3) {
                ClawdView(mood: .idle, scale: 1.35)   // 0.9 × 1.5
                    .frame(height: 26)
                Text(store.clawdDoing.line)
                    .font(.app(9.5))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .lineLimit(1)
                // 她看的不是他那一间的时候，**得说清楚他在哪儿**，
                // 不然她会以为他不见了
                if elsewhere {
                    Text("在" + store.clawdRoom.rawValue)
                        .font(.app(9))
                        .foregroundStyle(app.settings.accentColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(width: 74)
            .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.9)
        }
        .buttonStyle(.plain)
    }
}
