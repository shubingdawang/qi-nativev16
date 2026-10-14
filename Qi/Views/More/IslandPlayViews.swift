import SwiftUI

// 各岛玩法的几个小页：扎花束、赶集、种子店、写一句话（许愿 / 明信片），还有星丘夜里的流星。

/// 花岛花店：挑几朵扎一束
struct BouquetSheet: View {
    let done: (String) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var play = IslandPlay.shared
    @ObservedObject private var world = WorldStore.shared
    @State private var picks: [String: Int] = [:]

    private var total: Int { picks.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let flowers = play.flowersInBasket
                    if flowers.isEmpty {
                        EmptyNote(icon: "camera.macro", title: "篮子里还没有花",
                                  hint: "在花岛点一丛花「采一朵」，攒几朵再来扎。")
                            .padding(.top, 30)
                    }
                    ForEach(flowers, id: \.0) { f in
                        HStack {
                            Text(f.0).font(.app(14))
                            Text("篮子里 \(f.1) 朵").font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                            Stepper(value: Binding(get: { picks[f.0] ?? 0 }, set: { picks[f.0] = $0 }),
                                    in: 0...min(f.1, 5)) {
                                Text("\(picks[f.0] ?? 0)").font(.app(14, weight: .medium))
                            }
                            .fixedSize()
                        }
                        .padding(12)
                        .glassCard(padding: 0)
                    }
                    if !flowers.isEmpty {
                        Text("挑 2～5 朵扎成一束。扎好的花束可以送给他，也能拿去小镇的集市卖。")
                            .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .safeAreaInset(edge: .bottom) {
                let ok = (2...5).contains(total)
                Button {
                    let list = picks.flatMap { Array(repeating: $0.key, count: $0.value) }
                    if let desc = play.makeBouquet(list) {
                        dismiss()
                        done(desc)
                    }
                } label: {
                    Text(ok ? "扎起来（\(total) 朵）" : "挑 2～5 朵")
                        .font(.app(15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(ok ? app.settings.accentColor : Color.gray.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(!ok)
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .navigationTitle("扎一束花")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        }
    }
}

/// 小镇集市：把篮子里的东西卖掉换币
struct MarketSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var play = IslandPlay.shared
    @ObservedObject private var world = WorldStore.shared
    @ObservedObject private var store = ClawdStore.shared
    @State private var last: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(Color(hexString: "F2B33D")!)
                        Text("\(store.coins) 币").font(.app(14, weight: .medium))
                        Spacer()
                        if let last { Text(last).font(.app(11.5)).foregroundStyle(app.settings.accentColor) }
                    }
                    let items = play.sellable
                    if items.isEmpty {
                        EmptyNote(icon: "basket", title: "篮子是空的",
                                  hint: "去各个岛上采花、捡贝壳、采蘑菇、摘果子、钓鱼，攒了东西再来卖。")
                            .padding(.top, 30)
                    }
                    ForEach(items, id: \.name) { it in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(it.name) ×\(it.n)").font(.app(14))
                                Text("一个 \(it.price) 币").font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                            }
                            Spacer()
                            Button("卖 1 个") { last = play.sell(it.name) }
                                .font(.app(12.5)).buttonStyle(.bordered)
                            if it.n > 1 {
                                Button("全卖") { last = play.sell(it.name, it.n) }
                                    .font(.app(12.5)).buttonStyle(.bordered)
                            }
                        }
                        .tint(app.settings.accentColor)
                        .padding(12)
                        .glassCard(padding: 0)
                    }
                    Text("卖来的币在小屋的商店里用。漂流瓶要留着走剧情，集市不收。")
                        .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("集市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        }
    }
}

/// 小镇种子店：买稀有的种子，回栖岛的田里种
struct SeedShopSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = ClawdStore.shared
    @ObservedObject private var world = WorldStore.shared
    @State private var last: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(store.coins) 币").font(.app(14, weight: .medium))
                        Spacer()
                        if let last { Text(last).font(.app(11.5)).foregroundStyle(app.settings.accentColor) }
                    }
                    ForEach(WorldFarm.rareSeeds) { s in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hexString: s.color) ?? .green).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name + "种子").font(.app(14))
                                Text("约 \(Int(s.hours)) 小时熟 · 手上 \(world.save.basket[s.name + "种子"] ?? 0) 包")
                                    .font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                            }
                            Spacer()
                            let price = WorldFarm.price(of: s)
                            Button("\(price) 币") {
                                guard store.coins >= price else { last = "币不够"; return }
                                store.coins -= price
                                world.addBasket(s.name + "种子", 1)
                                last = "买了一包\(s.name)种子"
                            }
                            .font(.app(12.5)).buttonStyle(.bordered).tint(app.settings.accentColor)
                        }
                        .padding(12)
                        .glassCard(padding: 0)
                    }
                    Text("买来的种子在栖岛的田里点一下就能种，一包种一格。")
                        .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("种子店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        }
    }
}

/// 写一句话：对着流星许愿、给他寄明信片
struct LineSheet: View {
    let title: String
    let placeholder: String
    let action: String
    let done: (String) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.app(15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                .focused($focused)
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("算了").font(.app(14)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                .foregroundStyle(Theme.textMain(scheme))
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    dismiss()
                    done(t)
                } label: {
                    Text(action).font(.app(14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(app.settings.accentColor))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WallpaperBackground())
        .onAppear { focused = true }
    }
}

/// 星丘夜里，天上隔一会儿划过一颗流星；点它许个愿
struct MeteorLayer: View {
    let tapped: () -> Void

    /// 隔多久来一颗（秒）、每颗划多久
    private let every = 26.0
    private let lasts = 2.6

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let n = Int(t / every)
                let ph = (t - Double(n) * every) / lasts
                if ph < 1 {
                    // 每一颗从哪儿开始、往哪儿划，按它是第几颗定（每次都不一样）
                    let h = abs(sin(Double(n) * 12.9898) * 43758.5453)
                    let fx = 0.15 + (h - h.rounded(.down)) * 0.6
                    let fy = 0.12 + abs(sin(Double(n) * 7.13)) * 0.25
                    let start = CGPoint(x: g.size.width * fx, y: g.size.height * fy)
                    let p = CGPoint(x: start.x + CGFloat(ph) * 150, y: start.y + CGFloat(ph) * 70)
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: p.x - 70, y: p.y - 33))
                            path.addLine(to: p)
                        }
                        .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.9)],
                                               startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        Circle().fill(.white).frame(width: 6, height: 6).position(p)
                            .shadow(color: .white, radius: 6)
                        // 点得到的那一块比星星大一圈
                        Button(action: tapped) {
                            Color.clear.frame(width: 70, height: 70).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .position(p)
                    }
                    .opacity(ph < 0.15 ? ph / 0.15 : (ph > 0.8 ? (1 - ph) / 0.2 : 1))
                }
            }
        }
    }
}
