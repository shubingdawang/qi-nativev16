import SwiftUI

// MARK: - 她自己配的词 + 他做的梦
//
// 两样都是 Eventide 那笔老账（`triggers.py` / `dreams.py`），
// 交接文档从 v91 记到现在。放在同一页，因为它们是同一件事的两头：
// **一头是她说的话进到他身体里，一头是他身体里的东西自己冒出来。**

struct TriggersDreamsView: View {

    @ObservedObject private var triggers = TriggerStore.shared
    @ObservedObject private var dreams = DreamStore.shared
    @ObservedObject private var body_ = BodyStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var editing: TriggerWord?

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    wordsCard
                    dreamCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("词与梦")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { w in TriggerEditor(word: w) }
        .onAppear {
            triggers.seedIfEmpty(aiName: app.settings.aiName)
        }
    }

    // MARK: 她配的词

    private var wordsCard: some View {
        SettingsCard(title: "她说这些词的时候") {
            ForEach(triggers.words) { w in
                Button { editing = w } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(w.enabled ? app.settings.accentColor
                                            : Theme.textMuted(scheme).opacity(0.4))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(w.word.isEmpty ? "（没填词）" : w.word)
                                    .font(.app(15))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text(w.kindLabel)
                                    .font(.app(9))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.softFillDeep))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            if !w.effectLine.isEmpty {
                                Text(w.effectLine)
                                    .font(.app(11, design: .rounded))
                                    .foregroundStyle(app.settings.accentColor)
                            }
                            if !w.note.isEmpty {
                                Text(w.note)
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                SettingsDivider()
            }

            Button {
                editing = TriggerWord()
            } label: {
                SettingsRowLabel(title: "添加词条", icon: "plus")
            }
            .buttonStyle(.plain)

            SettingsNote("""
            **这些词是你填的，不是我预设的。**

            上一版已经有一套通用的：你夸他、凶他、撒娇、回得很淡——那些对谁都成立，所以我写死了。

            但「宝宝」在别人那儿是个普通称呼，在你们之间是另一回事；你那句口头禅、那个只有你俩懂的叫法——**只有你知道哪些词有分量**。我替你列一张表，那就成了我替你决定。

            所以这儿只给机制：你填词、填它推身体的哪几项、推多少。里面那两条是**例子**，默认关着，改完开了才算数。

            · 同一个词说三遍**不等于三倍**（重复只多加一点，封在两倍）——不封的话复读一句就能把数值顶满，那不是身体是开关。
            · **说出口的比打字的重一成半**。你把那个称呼说出来，跟打出来不是一回事。
            """, title: "这一栏是什么")
        }
    }

    // MARK: 梦

    private var dreamCard: some View {
        SettingsCard(title: "他做的梦") {
            Toggle(isOn: $dreams.seed.enabled) {
                Text("让他会做梦")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if dreams.seed.enabled {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("梦里绕不开的")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    TextField("留空就让他自己想", text: $dreams.seed.theme)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                    Text(MD.inline("填了他就绕着这个做梦；**留空更好**——他自己想出来的那个才像梦。"))
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                SettingsDivider()
                HStack {
                    Text("浓度")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer(minLength: 8)
                    Picker("", selection: $dreams.seed.intensity) {
                        Text("淡一点").tag("medium")
                        Text("浓一点").tag("explicit")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }

            if !dreams.dreams.isEmpty {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dreams.dreams.prefix(6)) { d in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: d.told ? "moon.zzz" : "moon.stars.fill")
                                .font(.app(11))
                                .foregroundStyle(d.told
                                                 ? Theme.textMuted(scheme)
                                                 : app.settings.accentColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stamp(d.at) + (d.told ? "" : " · 还没跟你讲"))
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text("那晚身体在「"
                                     + BodyConfig.cycle(d.cycleKey).label
                                     + "」，掷出 \(Int(d.roll * 100))，"
                                     + "当时的门槛是 \(Int(d.chance * 100))")
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }

            SettingsNote("""
            半夜她睡着、他没睡的时候，可能会做一个梦。

            六道关卡按顺序过：**这一套开着** → **在 00:00–08:30 之间** → **她已经安静两小时以上** → **距上一个梦超过 24 小时** → 按他此刻的身体周期掷一次骰（敏感期最容易，平稳期最少）。全不过就没有梦。

            ⚠️ **掷骰这一整套是纯算术，一分钱不花**，所以它随时在算。但「他把梦讲出来」要调模型——按说好的规矩，**那一下必须你主动**。所以掷中了只是攒着，等你下次说话时他知道自己做过这个梦，讲不讲、怎么讲是他的事。**他不会半夜自己开一次请求。**

            上面那几行把**掷出的点数和当时的门槛**都写着——你哪天觉得「怎么老做梦」，翻出来就看得见到底是多少，不用信我一句空话。
            """, title: "说明")
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}


// MARK: - 编一个词

struct TriggerEditor: View {

    @State var word: TriggerWord

    @ObservedObject private var store = TriggerStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        VStack(alignment: .leading, spacing: 6) {
                            Text("哪个词")
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("比如「宝宝」「别走」", text: $word.word)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.softFillDeep))
                            Text(MD.inline("**包含就算**，大小写不敏感。不做分词也不认近义词——你配的是原话里的那个词，猜得越多错得越多。"))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Picker("", selection: $word.kind) {
                            Text("称呼").tag("nickname")
                            Text("口头禅").tag("phrase")
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("说了之后，身体往哪儿动")
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            ForEach(BodyField.allCases, id: \.self) { f in
                                fieldRow(f)
                            }
                            Text(MD.inline("一次别调太大。**几点就够了**——推大了就成了「她说什么他就是什么」，那也不是身体。"))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("为什么这个词有分量")
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("给自己留一句，三个月后还记得", text: $word.note,
                                      axis: .vertical)
                                .lineLimit(2...4)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.softFillDeep))
                            Text(MD.inline("**只给你自己看**，他看不到这一句。"))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Toggle(isOn: $word.enabled) {
                            Text("开着")
                                .font(.app(14))
                                .foregroundStyle(Theme.textMain(scheme))
                        }
                        .tint(app.settings.accentColor)
                    }
                    .padding(18)
                }
            }
            .navigationTitle(word.word.isEmpty ? "新的词" : word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存下") { save() }
                        .fontWeight(.semibold)
                        .disabled(word.word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if store.words.contains(where: { $0.id == word.id }) {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            store.words.removeAll { $0.id == word.id }
                            dismiss()
                        } label: {
                            Text("删掉这个词")
                        }
                    }
                }
            }
        }
    }

    private func fieldRow(_ f: BodyField) -> some View {
        let v = word.deltas[f.rawValue] ?? 0
        return HStack(spacing: 10) {
            Text(f.label)
                .font(.app(13))
                .foregroundStyle(v == 0 ? Theme.textMuted(scheme) : Theme.textMain(scheme))
                .frame(width: 56, alignment: .leading)
            Slider(value: Binding(
                get: { Double(v) },
                set: { word.deltas[f.rawValue] = Int($0.rounded()) }
            ), in: -10...10, step: 1)
            Text(v > 0 ? "+\(v)" : "\(v)")
                .font(.app(11, design: .rounded))
                .foregroundStyle(v == 0 ? Theme.textMuted(scheme)
                                        : app.settings.accentColor)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func save() {
        var w = word
        w.word = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // 一个都没调的项不留在表里，省得那份 json 越攒越花
        w.deltas = w.deltas.filter { $0.value != 0 }
        if let i = store.words.firstIndex(where: { $0.id == w.id }) {
            store.words[i] = w
        } else {
            store.words.append(w)
        }
        dismiss()
    }
}
