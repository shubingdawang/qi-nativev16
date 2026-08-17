import SwiftUI

// MARK: - 记一个偏好

/// 加一条 / 改一条。
///
/// **原因是必填的**，这是她那张图上唯一标了「必填」的字段——
/// 说不出理由的喜欢不值得记，记了也没用。
struct HobbyEditor: View {

    let mine: Bool
    var existing: Hobby?
    var onSave: (Hobby) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var like = true
    @State private var category: HobbyCategory = .feel
    @State private var sub = ""
    @State private var reason = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
        && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        field("内容") {
                            TextField("比如：冰美式", text: $text)
                                .font(.app(15))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 11)
                                    .fill(Theme.softFillDeep))
                        }

                        field("喜欢还是讨厌？") {
                            HStack(spacing: 10) {
                                choice("喜欢", on: like,
                                       tint: HomePalette.bodyPink) { like = true }
                                choice("讨厌", on: !like,
                                       tint: HomePalette.sage) { like = false }
                            }
                        }

                        field("大类") {
                            flow(HobbyCategory.allCases.map(\.rawValue),
                                 selected: category.rawValue) { name in
                                if let c = HobbyCategory(rawValue: name) {
                                    category = c
                                    // 换了大类，原来那个小类多半不属于它了
                                    if !HobbySub.list(c).contains(sub) { sub = "" }
                                }
                            }
                        }

                        if !HobbySub.list(category).isEmpty {
                            field("小类") {
                                flow(HobbySub.list(category), selected: sub) { name in
                                    sub = (sub == name) ? "" : name
                                }
                            }
                        }

                        field("原因（必填）") {
                            TextEditor(text: $reason)
                                .scrollContentBackground(.hidden)
                                .font(.app(14))
                                .frame(height: 90)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 11)
                                    .fill(Theme.softFillDeep))
                                .overlay(alignment: .topLeading) {
                                    if reason.isEmpty {
                                        Text("为什么喜欢/讨厌它？")
                                            .font(.app(14))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }

                        HStack(spacing: 10) {
                            Button {
                                dismiss()
                            } label: {
                                Text("取消")
                                    .font(.app(15))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)

                            Button {
                                save()
                            } label: {
                                Text("存下")
                                    .font(.app(15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill((Color(hexString: "4A4038") ?? .black)
                                            .opacity(canSave ? 1 : 0.35)))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave)
                        }
                        .padding(.top, 4)
                    }
                    .padding(18)
                }
            }
            .navigationTitle(existing == nil ? "记一个偏好" : "改一改")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            guard let e = existing else { return }
            text = e.text; like = e.like; category = e.category
            sub = e.sub; reason = e.reason
        }
    }

    private func save() {
        var h = existing ?? Hobby()
        h.mine = existing?.mine ?? mine
        h.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        h.like = like
        h.category = category
        h.sub = sub
        h.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(h)
        dismiss()
    }

    // MARK: 零件

    @ViewBuilder
    private func field<C: View>(_ title: String,
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            content()
        }
    }

    private func choice(_ t: String, on: Bool, tint: Color,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t)
                .font(.app(14, weight: on ? .semibold : .regular))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11)
                    .fill(on ? tint.opacity(0.32) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 一排会自己换行的小标签
    private func flow(_ names: [String], selected: String,
                      pick: @escaping (String) -> Void) -> some View {
        // LazyVGrid 的自适应列就是最省事的流式布局，
        // 不用自己算换行
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 7)],
                  alignment: .leading, spacing: 7) {
            ForEach(names, id: \.self) { n in
                Button { pick(n) } label: {
                    Text(n)
                        .font(.app(12))
                        .foregroundStyle(selected == n
                                         ? Theme.textMain(scheme)
                                         : Theme.textSoft(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selected == n
                                                   ? HomePalette.sage.opacity(0.35)
                                                   : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 认证

/// 「已认领」不是"我喜欢它"，是**它坏在哪儿我也认**。
/// 所以这一页问两个问题，第二个才是重点。
struct HobbyClaimSheet: View {

    let hobby: Hobby
    var onClaim: (String, String) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var good = ""
    @State private var bad = ""

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        line("它好在哪里？", text: $good, hint: "一行一句")
                        line("它坏在哪里？（但你愿意接受）", text: $bad, hint: "一行一句")

                        HStack(spacing: 10) {
                            Button { dismiss() } label: {
                                Text("先放着")
                                    .font(.app(15))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)

                            Button {
                                onClaim(good.trimmingCharacters(in: .whitespacesAndNewlines),
                                        bad.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            } label: {
                                Text("认证为已认领")
                                    .font(.app(15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hexString: "4A4038") ?? .black))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("认证 · " + hobby.text)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { good = hobby.good; bad = hobby.bad }
    }

    private func line(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .font(.app(14))
                .frame(height: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.softFillDeep))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(hint)
                            .font(.app(14))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: - 变更史

struct HobbyHistorySheet: View {

    let hobby: Hobby
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if hobby.changes.isEmpty {
                            Text("还没有变动")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        ForEach(hobby.changes) { c in
                            HStack(alignment: .top, spacing: 8) {
                                Text(stamp(c.at))
                                    .font(HomeType.number(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                Text(c.text)
                                    .font(.app(13))
                                    .foregroundStyle(Theme.textSoft(scheme))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
            }
            .navigationTitle("变更史 · " + hobby.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关掉") { dismiss() }
                }
            }
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - 撞上啦那一页

struct HobbyMatchesSheet: View {

    @ObservedObject private var store = HobbyStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    /// 0 全部 · 1 喜欢 · 2 讨厌 · 3 分歧
    @State private var tab = 0

    private var me: String { app.settings.userName.isEmpty ? "你" : app.settings.userName }
    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("", selection: $tab) {
                            Text("全部").tag(0)
                            Text("喜欢").tag(1)
                            Text("讨厌").tag(2)
                            Text("分歧").tag(3)
                        }
                        .pickerStyle(.segmented)

                        if tab == 0 || tab == 1 {
                            group("一起喜欢的",
                                  store.matches.filter { $0.mine.like })
                        }
                        if tab == 0 || tab == 2 {
                            group("一起讨厌的",
                                  store.matches.filter { !$0.mine.like })
                        }
                        if tab == 0 || tab == 3 {
                            group("一个爱一个恨", store.clashes)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("撞上啦 きみと おなじ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [(mine: Hobby, hers: Hobby)]) -> some View {
        if !list.isEmpty {
            Text("· " + title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            ForEach(list, id: \.mine.id) { pair in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pair.mine.like == pair.hers.like
                          ? (pair.mine.like ? "heart.fill" : "leaf.fill")
                          : "circle.lefthalf.filled")
                        .font(.app(13))
                        .foregroundStyle(pair.mine.like == pair.hers.like
                                         ? (pair.mine.like
                                            ? HomePalette.bodyPink : HomePalette.sage)
                                         : HomePalette.amber)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pair.mine.text)
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text("\(me) · \(pair.mine.like ? "喜欢" : "讨厌") · \(pair.mine.stage.rawValue)")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text("\(him) · \(pair.hers.like ? "喜欢" : "讨厌") · \(pair.hers.stage.rawValue)")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassCard(padding: 0)
            }
        }
    }
}
