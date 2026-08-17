import SwiftUI

/// 爱好。
///
/// 照她给的那张设计图做的：两个人各记各的，系统去找重合。
/// 「撞上啦」是这一页的心脏——记东西只是手段，
/// 真正想看到的是「原来你也」和「原来你不」。
struct HobbyView: View {

    @ObservedObject private var store = HobbyStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 看谁的：true 是她，false 是他
    @State private var mine = true
    /// 看喜欢还是讨厌
    @State private var like = true
    @State private var category: HobbyCategory?
    @State private var keyword = ""

    @State private var adding = false
    @State private var editing: Hobby?
    @State private var claiming: Hobby?
    @State private var historyOf: Hobby?
    @State private var showingMatches = false
    /// 刚撞上的那一条，弹一下
    @State private var justMatched: (Hobby, Hobby)?

    private var me: String { app.settings.userName.isEmpty ? "你" : app.settings.userName }
    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }

    private var shown: [Hobby] {
        store.items.filter { h in
            h.mine == mine
            && h.like == like
            && (category == nil || h.category == category)
            && (keyword.isEmpty
                || h.text.localizedCaseInsensitiveContains(keyword)
                || h.reason.localizedCaseInsensitiveContains(keyword))
        }
    }

    /// 按小类分组，跟她那张图一样带个「· 小类」的小标题
    private var grouped: [(String, [Hobby])] {
        var order: [String] = []
        var buckets: [String: [Hobby]] = [:]
        for h in shown {
            let k = h.sub.isEmpty ? h.category.rawValue : h.sub
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(h)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    whoTabs
                    likeTabs
                    categoryChips
                    search

                    if shown.isEmpty {
                        Text(keyword.isEmpty
                             ? "这儿还空着。右下角加一个。"
                             : "没搜到")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(grouped, id: \.0) { group in
                        Text("· " + group.0)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.top, 4)
                        ForEach(group.1) { h in card(h) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, Layout.tabBarExpanded + 80)
            }

            matchBar
        }
        .navigationTitle("爱好")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            HobbyEditor(mine: mine) { h in
                store.add(h)
                if let m = store.freshMatch(for: h),
                   let other = store.items.first(where: {
                       $0.id == m.other.id
                   }) {
                    justMatched = (h, other)
                }
            }
        }
        .sheet(item: $editing) { h in
            HobbyEditor(mine: h.mine, existing: h) { store.update($0) }
        }
        .sheet(item: $claiming) { h in
            HobbyClaimSheet(hobby: h) { good, bad in
                store.claim(h.id, good: good, bad: bad)
            }
        }
        .sheet(item: $historyOf) { h in
            HobbyHistorySheet(hobby: h)
        }
        .sheet(isPresented: $showingMatches) {
            HobbyMatchesSheet()
        }
        // 撞上啦
        .overlay {
            if let pair = justMatched {
                matchPopup(pair.0, pair.1)
            }
        }
    }

    // MARK: 顶上那几排

    private var whoTabs: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { who in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { mine = who }
                } label: {
                    Text(who ? me : him)
                        .font(.system(size: 14, weight: mine == who ? .semibold : .regular))
                        .foregroundStyle(mine == who
                                         ? Theme.textMain(scheme)
                                         : Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if mine == who {
                                Capsule().fill(Theme.textMain(scheme).opacity(0.07))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassBackground(radius: 22, strength: app.settings.glassOpacity)
    }

    private var likeTabs: some View {
        HStack(spacing: 10) {
            pill("喜欢 すき", on: like, tint: HomePalette.bodyPink) { like = true }
            pill("讨厌 きらい", on: !like, tint: HomePalette.sage) { like = false }
        }
    }

    private func pill(_ title: String, on: Bool, tint: Color,
                      run: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { run() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: title.hasPrefix("喜欢") ? "heart.fill" : "leaf.fill")
                    .font(.system(size: 10))
                Text(title).font(.system(size: 12, weight: on ? .semibold : .regular))
            }
            .foregroundStyle(on ? Theme.textMain(scheme) : Theme.textMuted(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule().fill(on ? tint.opacity(0.30) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip("全部", on: category == nil) { category = nil }
                ForEach(HobbyCategory.allCases) { c in
                    chip(c.rawValue, on: category == c) {
                        category = (category == c) ? nil : c
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ t: String, on: Bool, run: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { run() }
        } label: {
            Text(t)
                .font(.system(size: 11, weight: on ? .medium : .regular))
                .foregroundStyle(on ? .white : Theme.textSoft(scheme))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(on
                                           ? Theme.textMain(scheme).opacity(0.75)
                                           : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted(scheme))
            TextField("搜一个爱好…", text: $keyword)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.softFillDeep))
    }

    // MARK: 一条

    private func card(_ h: Hobby) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: h.like ? "heart.fill" : "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(h.like ? HomePalette.bodyPink : HomePalette.sage)
                Text(h.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 4)
                Text(h.stage.rawValue)
                    .font(.system(size: 9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(h.stage == .claimed
                                               ? StatusTone.done.color.opacity(0.18)
                                               : HomePalette.amber.opacity(0.20)))
                    .foregroundStyle(Theme.textSoft(scheme))
            }

            Text(h.pathText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted(scheme))

            if !h.reason.isEmpty {
                Text(h.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 认证过的把好坏两面摆出来。**这才是「已认领」的意思**：
            // 不是"我喜欢它"，是"它坏在哪儿我也认"。
            if h.stage == .claimed, !(h.good.isEmpty && h.bad.isEmpty) {
                VStack(alignment: .leading, spacing: 3) {
                    if !h.good.isEmpty {
                        Text("它好的：").font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(h.good).font(.system(size: 11))
                            .foregroundStyle(Theme.textSoft(scheme))
                    }
                    if !h.bad.isEmpty {
                        Text("它坏的：").font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(h.bad + "（能接受）").font(.system(size: 11))
                            .foregroundStyle(Theme.textSoft(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.textMain(scheme).opacity(0.05)))
            }

            HStack(spacing: 12) {
                Text(stamp(h.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
                small("改") { editing = h }
                small("删") { store.remove(h.id) }
                if h.stage == .claimed {
                    small("撤销认证") { store.unclaim(h.id) }
                } else {
                    small("去认证") { claiming = h }
                }
                small("历史") { historyOf = h }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(padding: 0)
    }

    private func small(_ t: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    // MARK: 底下那条「撞上啦」+ 加号

    private var matchBar: some View {
        HStack(spacing: 10) {
            Button {
                showingMatches = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HomePalette.bodyPink)
                    Text("撞上啦：\(store.matches.count) 个（点我）")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassBackground(radius: 20, strength: app.settings.glassOpacity, extra: 0.2)
            }
            .buttonStyle(.plain)

            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(app.settings.primaryColor.opacity(0.9)))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 16)
        .padding(.bottom, Layout.tabBarExpanded + 14)
    }

    private func matchPopup(_ a: Hobby, _ b: Hobby) -> some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(HomePalette.bodyPink)
                Text("撞上啦！")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("你俩同时\(a.like ? "喜欢" : "讨厌")上了")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(a.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HomePalette.bodyPink)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { justMatched = nil }
                } label: {
                    Text("收下这份默契")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hexString: "4A4038") ?? .black))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark
                      ? Color(hexString: "2A2622")!
                      : Color(hexString: "FDF6F4")!))
            .padding(.horizontal, 40)
        }
        .transition(.opacity)
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
