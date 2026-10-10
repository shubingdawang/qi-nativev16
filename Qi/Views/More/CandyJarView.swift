import SwiftUI

/// 糖罐页：开罐、吃糖、喂他、图鉴、商店。规则和账都在 `CandyStore`。
struct CandyJarView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = CandyStore.shared

    @State private var tab = 0
    @State private var picked: Picked?
    @State private var reveal: Revealed?
    @State private var choosing: Int?
    @State private var notice: String?

    struct Picked: Identifiable {
        let id = UUID()
        let item: CandyItem
    }

    struct Revealed: Identifiable {
        let id = UUID()
        let outcome: CandyOutcome
        let fed: Bool
    }

    private var him: String { app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("罐子").tag(0)
                Text("图鉴").tag(1)
                Text("商店").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    effectsCard
                    switch tab {
                    case 0: jarTab
                    case 1: dexTab
                    default: shopTab
                    }
                    if let notice {
                        Text(notice)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 12)
            }
        }
        .navigationTitle("糖罐")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refresh() }
        .sheet(item: $picked) { p in
            candySheet(p.item).presentationDetents([.medium])
        }
        .sheet(item: $reveal) { r in
            revealSheet(r).presentationDetents([.medium, .large])
        }
        .confirmationDialog(choosing.map { "今天开「\(store.jarName($0))」？" } ?? "",
                            isPresented: Binding(get: { choosing != nil },
                                                 set: { if !$0 { choosing = nil } }),
                            titleVisibility: .visible) {
            Button("开这一罐") {
                if let n = choosing { notice = store.choose(n) }
                choosing = nil
            }
            Button("再看看", role: .cancel) { choosing = nil }
        } message: {
            Text("一天只能开一罐，明天零点再选。")
        }
    }

    // MARK: 药效

    @ViewBuilder
    private var effectsCard: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let mine = store.effects(for: "user")
            let his = store.effects(for: "ai")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("勇气").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                    Text("你 \(store.save.courage["user"] ?? candyStartCourage)✦")
                        .font(.app(13, weight: .medium))
                    Text("\(him) \(store.save.courage["ai"] ?? candyStartCourage)✦")
                        .font(.app(13, weight: .medium))
                    Spacer()
                }
                ForEach(mine + his) { e in effectRow(e) }
                if mine.isEmpty, his.isEmpty {
                    Text("现在谁身上都没有药效。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func effectRow(_ e: CandyEffect) -> some View {
        let c = store.candy(e.candyID)
        let mins = max(0, Int(e.expires.timeIntervalSinceNow / 60))
        return HStack(spacing: 8) {
            if let c { CandyGlyph(scheme: c.scheme, shape: c.shape, size: 22) }
            VStack(alignment: .leading, spacing: 2) {
                Text((e.target == "ai" ? him : "你") + " · " + (c?.effect ?? ""))
                    .font(.app(13, weight: .medium))
                Text(mins > 0 ? "还剩约 \(mins) 分钟" : "快退了")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer()
        }
    }

    // MARK: 罐子

    @ViewBuilder
    private var jarTab: some View {
        if let jar = store.todayJar {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.jarName(jar.jar) + "之罐")
                    .font(.app(17, weight: .semibold))
                if let line = store.jarMeta[String(jar.jar)]?.line {
                    Text(line).font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                }
                Text("还剩 \(jar.candies.count) 颗")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if jar.candies.isEmpty {
                Text("今天这罐吃完了，明天零点再开新的。")
                    .font(.app(13))
                    .foregroundStyle(Theme.textSoft(scheme))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 12) {
                    ForEach(jar.candies, id: \.i) { item in
                        Button { picked = Picked(item: item) } label: {
                            CandyGlyph(scheme: store.disguise(item, jar: jar.jar),
                                       shape: store.candy(item.id)?.shape ?? "圆珠", size: 40)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassCard()
            }
            reserveSection
        } else {
            Text("每天从五罐里选一罐，选定后今天就是它，罐里的糖吃一颗少一颗。")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))
            ForEach(CandyStore.jarNumbers, id: \.self) { n in
                Button { choosing = n } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(store.jarName(n)).font(.app(15, weight: .semibold))
                            Text(store.jarMeta[String(n)]?.cat ?? "")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                        }
                        Text(store.jarMeta[String(n)]?.line ?? "")
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var reserveSection: some View {
        let mine = store.save.reserve["user"] ?? []
        if !mine.isEmpty {
            Text("我的储藏罐").heading(14)
            ForEach(Array(mine.enumerated()), id: \.offset) { _, id in
                if let c = store.candy(id) {
                    HStack(spacing: 10) {
                        CandyGlyph(scheme: c.scheme, shape: c.shape, size: 26)
                        Text(c.name).font(.app(13))
                        Spacer()
                        Button("吃") { eat(reserve: id, feed: false) }
                            .font(.app(13))
                        Button("喂\(him)") { eat(reserve: id, feed: true) }
                            .font(.app(13))
                    }
                    .glassCard()
                }
            }
        }
    }

    private func candySheet(_ item: CandyItem) -> some View {
        let c = store.candy(item.id)
        let jarNo = store.todayJar?.jar ?? 1
        return VStack(spacing: 16) {
            CandyGlyph(scheme: store.disguise(item, jar: jarNo), shape: c?.shape ?? "圆珠", size: 64)
                .padding(.top, 24)
            Text(c?.shop ?? "")
                .font(.app(14))
                .foregroundStyle(Theme.textSoft(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button { eat(item: item, feed: false) } label: {
                    Text("自己吃").font(.app(15, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                Button { eat(item: item, feed: true) } label: {
                    Text("喂给\(him)").font(.app(15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(app.settings.accentColor))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func eat(item: CandyItem? = nil, reserve: String? = nil, feed: Bool) {
        picked = nil
        let r = store.eat(index: item?.i, who: "user", target: feed ? "ai" : "user",
                          fromReserve: reserve)
        switch r {
        case .success(let o):
            notice = nil
            if feed { app.tellHim(o.text) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                reveal = Revealed(outcome: o, fed: feed)
            }
        case .failure(let e):
            notice = e.message
        }
    }

    private func revealSheet(_ r: Revealed) -> some View {
        let c = r.outcome.candy
        return ScrollView {
            VStack(spacing: 14) {
                CandyGlyph(scheme: c.scheme, shape: c.shape, size: 64).padding(.top, 24)
                Text(c.name).font(.app(18, weight: .semibold))
                Text(c.effect + (r.outcome.minutes > 0 ? " · \(r.outcome.minutes) 分钟" : ""))
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(r.outcome.blocked ? "护身符挡下了这一颗，效果没有落在身上。" : c.reveal)
                    .font(.app(15))
                    .multilineTextAlignment(.center)
                Text("口感：它尝起来" + c.taste)
                    .font(.app(13))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .multilineTextAlignment(.center)
                if !r.outcome.extra.isEmpty {
                    Text(r.outcome.extra.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.app(13))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .multilineTextAlignment(.center)
                }
                Text(c.lore)
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .multilineTextAlignment(.center)
                if r.fed {
                    Text("已经告诉\(him)了。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                } else {
                    Button {
                        app.tellHim("她自己吃了一颗糖：\n" + r.outcome.text)
                        reveal = nil
                    } label: {
                        Text("告诉\(him)").font(.app(14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28).padding(.vertical, 10)
                            .background(Capsule().fill(app.settings.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: 图鉴

    @ViewBuilder
    private var dexTab: some View {
        let got = store.candies.filter { (store.save.dex[$0.id] ?? 0) > 0 }.count
        Text("已收集 \(got) / \(store.candies.count)")
            .font(.app(12))
            .foregroundStyle(Theme.textMuted(scheme))
        ForEach(store.candies) { c in
            let n = store.save.dex[c.id] ?? 0
            HStack(alignment: .top, spacing: 10) {
                CandyGlyph(scheme: c.scheme, shape: c.shape, size: 30)
                    .opacity(n > 0 ? 1 : 0.25)
                VStack(alignment: .leading, spacing: 3) {
                    if n > 0 {
                        Text(c.name + "  ×\(n)").font(.app(13, weight: .medium))
                        Text(c.reveal).font(.app(12)).foregroundStyle(Theme.textSoft(scheme))
                        Text(c.lore).font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                    } else {
                        Text("？").font(.app(13, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                Spacer(minLength: 0)
            }
            .glassCard()
        }
        Text("糖果文案来自 mamo「因果律软糖罐」，CC BY-NC-SA 4.0。")
            .font(.app(10.5))
            .foregroundStyle(Theme.textMuted(scheme))
    }

    // MARK: 商店

    @ViewBuilder
    private var shopTab: some View {
        let courage = store.save.courage["user"] ?? candyStartCourage
        Text("自己吃一颗 +1✦；身上药效还剩 10 分钟以上时再吃，扣 2✦。")
            .font(.app(12))
            .foregroundStyle(Theme.textMuted(scheme))

        Text("新糖果 · \(store.mysteryPrice)✦ 起").heading(14)
        Text("没吃过的品种，买了混进它所属的那一罐。")
            .font(.app(11))
            .foregroundStyle(Theme.textMuted(scheme))
        let fresh = store.candies.filter { (store.save.dex[$0.id] ?? 0) == 0 && !$0.isMechanism }
        ForEach(fresh) { c in
            shopRow(c, price: store.mysteryPrice, courage: courage, toToday: true, title: c.shop)
        }

        Text("指名陈列 · \(CandyStore.reservePrice)✦").heading(14)
        Text("吃过的品种，买了放进你的储藏罐。")
            .font(.app(11))
            .foregroundStyle(Theme.textMuted(scheme))
        let known = store.candies.filter { (store.save.dex[$0.id] ?? 0) > 0 }
        if known.isEmpty {
            Text("还没吃过糖。").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
        }
        ForEach(known) { c in
            shopRow(c, price: CandyStore.reservePrice, courage: courage, toToday: false, title: c.name)
        }
    }

    private func shopRow(_ c: Candy, price: Int, courage: Int, toToday: Bool, title: String) -> some View {
        let soldOut = store.onceSoldOut(c.id)
        return HStack(spacing: 10) {
            CandyGlyph(scheme: c.scheme, shape: c.shape, size: 26)
            Text(title)
                .font(.app(12.5))
                .foregroundStyle(Theme.textSoft(scheme))
                .lineLimit(3)
            Spacer(minLength: 6)
            Button(soldOut ? "售罄" : "\(price)✦") {
                notice = store.buy(c.id, toToday: toToday) ?? "买好了。"
            }
            .font(.app(13, weight: .medium))
            .disabled(soldOut || courage < price)
        }
        .glassCard()
    }
}

/// 一颗糖的样子：颜色看配色，形状看造型
struct CandyGlyph: View {
    let scheme: String
    let shape: String
    var size: CGFloat = 32

    static func color(_ s: String) -> Color {
        let map: [String: String] = [
            "可乐": "6B2E1F", "青苹果": "9CCB5A", "焦糖咖啡": "B07444", "蜜桃": "F4A98C",
            "荔枝": "F3E3E6", "橘子汽水": "F59A3B", "柠檬": "F2D64B", "绵云": "DCE6F2",
            "葡萄": "7A4E9A", "草莓奶": "F5B5C8", "树莓红": "C7354F", "芭乐": "F08C8C",
            "紫藤": "B39DDB", "mm巧克力": "6A4430", "mm橙红": "E2552B", "mm黄": "F2C230",
            "mm蓝": "3C7BD9", "mm米白": "EFE6D2", "mm金": "D8A93A", "mm沙": "CDB38A",
            "mm双色": "8C6E5A"
        ]
        return Color(hexString: map[s] ?? "D9C2A7") ?? .brown
    }

    static func symbol(_ shape: String) -> String {
        switch shape {
        case "方糖": return "square.fill"
        case "三角": return "triangle.fill"
        case "五角星": return "star.fill"
        case "和果子": return "seal.fill"
        case "圆珠": return "circle.fill"
        case "小包子": return "drop.fill"
        case "弯豆": return "moon.fill"
        case "花果子": return "suit.club.fill"
        default: return "capsule.fill"
        }
    }

    var body: some View {
        Image(systemName: Self.symbol(shape))
            .font(.system(size: size * 0.8))
            .foregroundStyle(Self.color(scheme).gradient)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .frame(width: size, height: size)
    }
}
