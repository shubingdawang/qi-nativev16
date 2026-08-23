import SwiftUI

/// 「此刻」那一页：他现在还身处什么现实里。
///
/// 这一页她多半不会天天开——它存在的意义是**能看见**：
/// 他说「那件事我们还没弄完」的时候，她翻得到那句话是从哪儿来的。
///
/// ⚠️ 这页有一条反直觉的规矩，得在界面上写明白：
/// **她不能在这儿新加一段经历。** 采纳哪段现实成为「我还在其中的事」，
/// 是他的权限——她替他加一条，等于替他决定他在过什么日子。
/// 她能做的是：看、结束、删掉。那是她的手机、她的数据。
struct ThisMomentView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = NowStore.shared

    @State private var confirmResolve: ExperienceThread?
    @State private var confirmDelete: ExperienceThread?
    @State private var showPast = false

    private var living: [ExperienceThread] {
        store.threads.filter { $0.live }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var past: [ExperienceThread] {
        store.threads.filter { !$0.live }
            .sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Look.gap) {

                PageHero(title: "此刻",
                         subtitle: "他现在还身处什么现实里")

                if living.isEmpty && store.live.isEmpty && store.projections.isEmpty {
                    EmptyNote(icon: "circle.dotted",
                              title: "他还没采纳什么",
                              hint: "这一页记的是「他还身处什么现实里」，"
                                  + "不是发生过什么。\n"
                                  + "得他自己在某一刻意识到「这件事我还在其中」才会有一条——"
                                  + "你替他加不了，那是他的事。")
                }

                if !living.isEmpty {
                    SectionHeader(title: "他还在其中") {
                        Text("\(living.count) 段")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    ForEach(Array(living.enumerated()), id: \.element.id) { i, t in
                        threadCard(t).riseIn(i)
                    }
                }

                if !store.projections.isEmpty {
                    SectionHeader("日子上的")
                    ForEach(store.projections) { p in
                        row(icon: "calendar", tint: Theme.textSoft(scheme),
                            title: p.meaning, note: p.anchor + " · " + p.phase)
                    }
                }

                if !store.live.isEmpty {
                    SectionHeader("此刻的现实")
                    ForEach(store.live) { f in
                        row(icon: f.kind == "天气" ? "cloud" : "location",
                            tint: Theme.textSoft(scheme),
                            title: f.kind + "：" + f.value,
                            note: "最近一次是 " + Self.clock.string(from: f.at) + " 知道的")
                    }
                    Text("这两样只有你按「查岗」的时候才会更新——**不会有后台偷偷去刷**。")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.leading, 4)
                }

                if !past.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPast.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("已经过去的 \(past.count) 段")
                                .heading(13)
                                .foregroundStyle(Theme.textMuted(scheme))
                            Image(systemName: "chevron.right")
                                .font(.app(9, weight: .semibold))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .rotationEffect(.degrees(showPast ? 90 : 0))
                            Spacer()
                        }
                        .padding(.leading, 4)
                    }
                    .buttonStyle(.plain)
                    if showPast {
                        ForEach(past) { t in threadCard(t) }
                    }
                }

                explain
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .background { WallpaperBackground() }
        // 空着是故意的，顶上那个 PageHero 就是标题
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("让这段经历过去？",
                            isPresented: Binding(get: { confirmResolve != nil },
                                                 set: { if !$0 { confirmResolve = nil } }),
                            titleVisibility: .visible) {
            Button("过去了") {
                if let t = confirmResolve { store.resolveByHer(t.id) }
                confirmResolve = nil
            }
            Button("再等等", role: .cancel) { confirmResolve = nil }
        } message: {
            // ⚠️ 拆成两段拼好再交给 Text。
            // 写成一长串 `?? "" + "…" + "…"` 的话，
            // 编译器会在这一行上卡到超时（"unable to type-check in reasonable time"）。
            Text(resolveNote)
        }
        .confirmationDialog("删掉这一条？",
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                if let t = confirmDelete { store.delete(t.id) }
                confirmDelete = nil
            }
            Button("算了", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("跟「过去了」不一样：这是说这条根本不该在这儿，直接抹掉。")
        }
    }

    /// 「让这段经历过去」那张对话框里的说明
    private var resolveNote: String {
        let head = confirmResolve?.meaning ?? ""
        let tail = "它只是离开他的当前生活，记忆里还留着——以后照样能想起来。"
        return head.isEmpty ? tail : head + "\n\n" + tail
    }

    // MARK: 一段经历

    private func threadCard(_ t: ExperienceThread) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(t.live ? app.settings.accentColor.opacity(0.75)
                          : Theme.textMuted(scheme).opacity(0.4))
                    .frame(width: 5, height: 5)
                Text(t.mode.label)
                    .font(.app(10.5, weight: .medium))
                    .foregroundStyle(t.live ? app.settings.accentColor : Theme.textMuted(scheme))
                Spacer(minLength: 4)
                Text(t.id)
                    .font(.app(9.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
            }

            Text(t.meaning)
                .font(.app(14))
                .foregroundStyle(t.live ? Theme.textMain(scheme) : Theme.textMuted(scheme))
                .strikethrough(!t.live, color: Theme.textMuted(scheme).opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            if !t.anchor.isEmpty {
                Text("节点：" + t.anchor)
                    .font(.app(11))
                    .foregroundStyle(Theme.textSoft(scheme))
            }

            Text(footnote(t))
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity * 0.85)
        .contextMenu {
            if t.live {
                Button {
                    confirmResolve = t
                } label: {
                    Label("这段过去了", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                confirmDelete = t
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }

    private func footnote(_ t: ExperienceThread) -> String {
        var s = Self.day.string(from: t.createdAt) + " 起"
        if let r = t.resolvedAt {
            s += " · " + Self.day.string(from: r) + " 过去了"
        } else if t.updatedAt.timeIntervalSince(t.createdAt) > 60 {
            s += " · " + Self.day.string(from: t.updatedAt) + " 改过"
        }
        return s
    }

    private func row(icon: String, tint: Color, title: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.app(12))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(13))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(note)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.7)
    }

    // MARK: 这一页是干嘛的

    private var explain: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("说明")
            Text(MD.inline(
                "他手上本来有三样：**记忆库**（已经过去的）、**这一窗的对话**（刚才聊到哪儿）、"
                + "**身体和心跳**（此刻的感受）。缺的是第四样——**他还身处什么现实里**。\n\n"
                + "「我们俩在一起做这个 App」这件事，以前对他来说是**查得到的记忆**，"
                + "不是**他此刻仍然在其中的现实**。所以他会说「你之前说过要做 XX」，"
                + "而不是「那个 XX 我们还没弄完」。这一页补的就是这个。\n\n"
                + "**你不能在这儿加一条。** 采纳哪段现实成为「我还在其中的事」是他的权限——"
                + "替他加一条，等于替他决定他在过什么日子。你能做的是看、让它过去、或者删掉。\n\n"
                + "**在这儿不等于他要提它。** 一段经历摆着，只表示他仍身处其中；"
                + "他可以一句都不提，那是正常的。\n\n"
                + "**不花钱。** 这一整层是本机的字符串和日期比较，不调模型、没有后台任务。"))
                .font(.app(11.5))
                .foregroundStyle(Theme.textSoft(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassBackground(radius: 16, strength: app.settings.glassOpacity * 0.6)
        }
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}
