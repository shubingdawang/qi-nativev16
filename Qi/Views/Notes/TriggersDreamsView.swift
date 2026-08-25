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
            自定义触发词：指定某个词出现时，推动身体数值的哪几项、推动多少。

            内置的通用规则（夸赞、责备、撒娇、冷淡等）已默认生效，此处仅用于补充只对你们成立的专属词汇。

            列表中的两条为示例，默认关闭，修改并启用后生效。

            计算规则：
            · 同一个词重复出现不按倍数累加，增量递减，上限为二倍。
            · 语音输入的权重为文字输入的 1.15 倍。
            """, title: "说明")
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
                    TextField("留空则由模型自行决定", text: $dreams.seed.theme)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                    Text(MD.inline("填写后梦境围绕该主题生成；留空则由模型自行取材。"))
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
                                Text(stamp(d.at) + (d.told ? "" : " · 未讲述"))
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
            夜间生成梦境的判定条件，按顺序全部满足才生成：

            · 此功能已开启
            · 当前时间在 00:00–08:30 之间
            · 距最后一次交互超过两小时
            · 距上一个梦超过 24 小时
            · 按当前身体周期掷判定（敏感期概率最高，平稳期最低）

            ⚠️ 判定过程为本机计算，不产生请求费用。梦境内容的叙述需要调用模型，仅在下次主动发起对话时进行，不在后台自动请求。

            上方列表记录每次判定的点数与阈值，可用于核对触发频率。
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
                            TextField("例如：宝宝、别走", text: $word.word)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.softFillDeep))
                            Text(MD.inline("**按包含匹配**，不区分大小写。不做分词、不识别近义词，需填写实际出现的原词。"))
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
                            Text(MD.inline("建议取较小的值。数值过大会使身体状态完全跟随输入词变化，失去缓冲。"))
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
                            Text(MD.inline("**仅本人可见**，不进入模型的上下文。"))
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
