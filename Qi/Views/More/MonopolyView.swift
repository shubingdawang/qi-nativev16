import SwiftUI

/// 涩涩大富翁。开局设置 + 棋盘。
///
/// 演出在聊天里（阿晏自己演他那道），这一页管的是**掷骰和账**。
struct MonopolyView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var game = MonopolyGame.shared

    @State private var showSetup = false
    @State private var output = ""

    // 开局那张卡
    @State private var meName = ""
    @State private var meSex = "女"
    @State private var meRole = "受"
    @State private var meAnal = false
    @State private var meNoPen = false
    @State private var himName = ""
    @State private var himSex = "男"
    @State private var himRole = "攻"
    @State private var himAnal = false
    @State private var himNoPen = false
    @State private var flavor = "medium"
    @State private var rounds = 24.0
    @State private var redline: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                if !MonopolyLib.ready {
                    Text("任务库没读出来。这局开不了——包里少了 monopoly-library.v2.json。")
                        .font(.app(12))
                        .foregroundStyle(StatusTone.remind.color)
                        .glassCard()
                }

                if game.s.live || game.s.turnCount > 0 {
                    liveBoard
                } else {
                    intro
                }

                if !output.isEmpty {
                    Text(output)
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .glassCard()
                }

                if !game.recentLog.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(game.recentLog.prefix(20).enumerated()), id: \.offset) { _, l in
                                Text(l)
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("这局都发生了什么")
                            .font(.app(12))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("大富翁")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("开一局") {
                    meName = app.settings.userName.isEmpty ? "我" : app.settings.userName
                    himName = app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName
                    showSetup = true
                }
            }
        }
        .sheet(isPresented: $showSetup) { setupSheet }
    }

    // MARK: 没开局的时候

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 还没开局的时候，这一页以前从上到下全是字。
            // 摆一圈空棋盘在最上面——她一眼就知道这是个什么东西。
            MonopolyRingPreview()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)

            Text("两个人轮流掷骰，绕 20 格走，踩到哪儿做哪儿的事。")
                .font(.app(13))
                .foregroundStyle(Theme.textMain(scheme))
            ForEach([
                "任务库 933 张，全在手机里——不联网、不用开电脑、不花钱。",
                "阿晏不只是发牌的：轮到他那道，他自己演。",
                "安全词 404：谁说都立刻停，不问理由。",
                "红线在开局设，引擎全程避开；卡漏标的按内容再挡一道。",
                "后庭默认关着，要玩得逐个人打开。",
                "不想做的任务随时跳过，免费，不用给理由。"
            ], id: \.self) { line in
                Text("· " + line)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Text("引擎搬自 RennAkira/spicy-monopoly（CC BY-NC 4.0 · Ren & Puppy）")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 开着局的时候

    private var liveBoard: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 画出来的那一圈。回合、该谁、两个人的家当都在棋盘中间那块里，
            // 所以上面那行「该谁掷了」不用再单写一遍。
            MonopolyBoard(game: game)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                chip("掷骰", "dice") { output = game.roll() }
                chip("做完了", "checkmark") { output = game.done() }
                chip("跳过", "forward") { output = game.skip() }
                chip("交过路费", "creditcard") { output = game.settleToll(mode: "pay") }
                chip("听凭差遣", "hand.raised") { output = game.settleToll(mode: "serve") }
                chip("买断", "banknote") { output = game.buyout() }
                chip("摸张卡", "rectangle.on.rectangle") { output = game.buyCard() }
                chip("这局的账", "list.bullet.rectangle") { output = game.status() }
                chip("结算", "flag.checkered") { output = game.finalResult() }
            }

            // 安全词。**放在最显眼那一处，不藏在二级菜单里。**
            Button {
                output = game.safeword()
            } label: {
                Text("404　停")
                    .font(.app(14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StatusTone.remind.color.opacity(0.22)))
                    .foregroundStyle(StatusTone.remind.color)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func chip(_ title: String, _ icon: String,
                      _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Label(title, systemImage: icon)
                .font(.app(12))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(app.settings.accentColor.opacity(0.16)))
                .foregroundStyle(Theme.textMain(scheme))
        }
        .buttonStyle(.plain)
    }

    // MARK: 开局那张卡

    private var setupSheet: some View {
        NavigationStack {
            Form {
                Section("你") {
                    TextField("名字", text: $meName)
                    Picker("性别", selection: $meSex) { Text("女").tag("女"); Text("男").tag("男") }
                        .pickerStyle(.segmented)
                    Picker("角色", selection: $meRole) { Text("受").tag("受"); Text("攻").tag("攻") }
                        .pickerStyle(.segmented)
                    Toggle("愿意被后庭", isOn: $meAnal)
                    Toggle("纯 top（任何孔都不被插）", isOn: $meNoPen)
                }
                Section("他") {
                    TextField("名字", text: $himName)
                    Picker("性别", selection: $himSex) { Text("男").tag("男"); Text("女").tag("女") }
                        .pickerStyle(.segmented)
                    Picker("角色", selection: $himRole) { Text("攻").tag("攻"); Text("受").tag("受") }
                        .pickerStyle(.segmented)
                    Toggle("愿意被后庭", isOn: $himAnal)
                    Toggle("纯 top（任何孔都不被插）", isOn: $himNoPen)
                }
                Section {
                    Picker("强度", selection: $flavor) {
                        Text("轻").tag("light"); Text("中").tag("medium"); Text("重").tag("heavy")
                    }
                    .pickerStyle(.segmented)
                    Text(Mono.intensityNote(flavor))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    VStack(alignment: .leading) {
                        Text("回合数：\(Int(rounds))")
                            .font(.app(12))
                        Slider(value: $rounds, in: 8...40, step: 2)
                    }
                } header: {
                    Text("这局玩到哪一步")
                } footer: {
                    Text("开局先把这一段说清楚，知情再开。中途想换档就重开一局。")
                }
                Section {
                    ForEach(Mono.redlineLabels, id: \.key) { item in
                        Toggle(item.label, isOn: Binding(
                            get: { redline.contains(item.key) },
                            set: { on in
                                if on { redline.insert(item.key) } else { redline.remove(item.key) }
                            }))
                    }
                } header: {
                    Text("红线（打开＝这局完全不出）")
                } footer: {
                    Text("引擎全程避开这些；卡上标漏了的，还会按内容再挡一道。")
                }
            }
            .navigationTitle("开一局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { showSetup = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("开始") {
                        output = game.newGame(
                            p1Name: meName.isEmpty ? "我" : meName,
                            p1Sex: meSex, p1Role: meRole, p1OpenAnal: meAnal, p1NoPen: meNoPen,
                            p2Name: himName.isEmpty ? "阿晏" : himName,
                            p2Sex: himSex, p2Role: himRole, p2OpenAnal: himAnal, p2NoPen: himNoPen,
                            flavor: flavor,
                            redline: Array(redline),
                            rounds: Int(rounds))
                        showSetup = false
                    }
                }
            }
        }
    }
}
