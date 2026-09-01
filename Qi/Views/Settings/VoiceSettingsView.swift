import SwiftUI

/// 语音服务。可以存好几套音色，同时只启用一个。
struct VoiceSettingsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var editing: VoiceService?
    @State private var creatingNew = false
    @State private var testing = false
    @State private var notice: String?

    /// 上半：她按住说话的时候，那段声音交给谁转成字。
    ///
    /// 这一段原来是独立的 `VoiceInputSettingsView`，
    /// 现在并到这一页来了（见 body 开头那段）。
    /// 上半：她按住说话的时候，那段声音交给谁转成字。
    ///
    /// 这一段原来是独立的 `VoiceInputSettingsView`，并进来了；
    /// 这一版又从 `Section` 换成了卡片（理由见 body 那段）。
    private var inputCard: some View {
        SettingsCard(title: "按住说话时用哪个") {
            ForEach(Array(VoiceInputMode.allCases.enumerated()), id: \.element) { i, mode in
                if i > 0 { SettingsDivider() }
                Button {
                    app.settings.voiceInput = mode
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: app.settings.voiceInput == mode
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(app.settings.accentColor)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title)
                                .font(.app(15))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(mode.note)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    // ⚠️ 整行都要能点，不只是那几个字（这病栽过六次）
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if app.settings.voiceInput == .elevenLabs {
                SettingsDivider()
                SettingsNote(app.activeVoice == nil
                             ? "还没配 ElevenLabs。下面填一次密钥，这里就能直接用。"
                             : "用的是下面那个密钥，不用另填。\n\n可识别笑声、鼓掌、哭泣等声音事件，但不输出情绪判定。需要情绪识别请选择 SenseVoice。",
                             title: "密钥")
            }

            if app.settings.voiceInput == .senseVoice {
                SettingsDivider()
                SecureField("SiliconFlow API Key", text: $app.settings.siliconKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.app(13))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                SettingsDivider()
                SettingsNote("密钥在 siliconflow.cn 注册获取，使用 SenseVoiceSmall 模型，费用较低。\n\n可识别开心、难过、生气、意外等情绪，以及笑声与哭声。识别结果随语音文本一并发送，用于区分相同措辞的不同语气。")
            }

            SettingsDivider()
            SettingsNote("以上三项用于语音识别（输入）。下面几张卡是语音合成（输出），两者互不影响。")
        }
    }

    /// 一把嗓子那几行。
    @ViewBuilder
    private func voiceRows(_ voice: VoiceService) -> some View {
        Button {
            editing = voice
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.name.isEmpty ? "未命名" : voice.name)
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(voice.ready ? voice.voiceID : "还没填全")
                        .font(.app(11))
                        .foregroundStyle(voice.ready ? Theme.textMuted(scheme) : .orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: Icon.chevron)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 换成卡片之后没有 swipeActions 了，删掉走长按
        .contextMenu {
            Button(role: .destructive) {
                app.voices.removeAll { $0.id == voice.id }
            } label: {
                Label("删掉这把嗓子", systemImage: Icon.trash)
            }
        }

        SettingsDivider()

        Toggle(isOn: Binding(
            get: { voice.enabled },
            set: { on in
                // 同一时刻只启用一个，免得不知道在用哪把嗓子
                if on {
                    for i in app.voices.indices { app.voices[i].enabled = false }
                }
                if let i = app.voices.firstIndex(where: { $0.id == voice.id }) {
                    app.voices[i].enabled = on
                }
            }
        )) {
            Text("用这个")
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
        }
        .tint(app.settings.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)

        SettingsDivider()

        Button { test(voice) } label: {
            HStack {
                SettingsRowLabel(title: "试听", icon: "waveform")
                if testing {
                    ProgressView().padding(.trailing, 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!voice.ready || testing)
        .opacity(voice.ready ? 1 : 0.5)
    }

    // ⚠️⚠️ **这一页原来是 `List`，换成了跟设置页一样的卡片。**
    //
    // 她报的：「我跟你说的设置白底你没弄成玻璃。」
    //
    // 玻璃**其实一直挂着**（`.listRowBackground(GlassRowBackground())`），
    // 可它盖不住：`List` 默认是 `insetGrouped`，那一层白圆角是
    // **分组容器自己画的**，行背景压在它上面，白底照样透出来。
    //
    // 记一句：**`listRowBackground` 管的是「行」，管不了分组的底。**
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WallpaperBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    // 上半是**她这边**（把话转成字）
                    inputCard

                    // 下半是**他那边**（把字读出声）
                    if app.voices.isEmpty {
                        SettingsCard(title: "他的嗓子") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("还没有语音服务")
                                    .font(.app(15, weight: .semibold))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text("配置完成后，长按任意消息可朗读；模型也可主动发送语音消息。")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    } else {
                        ForEach(app.voices) { voice in
                            SettingsCard { voiceRows(voice) }
                        }
                    }

                    SettingsCard {
                        Button { creatingNew = true } label: {
                            SettingsRowLabel(title: "添加音色", icon: Icon.add)
                        }
                        .buttonStyle(.plain)
                        if let notice {
                            SettingsDivider()
                            Text(notice)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                        }
                        SettingsDivider()
                        SettingsNote("音色 ID 在 ElevenLabs 网站上每个声音的详情里能找到。同一个密钥下可以放好几个音色，随时切。")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { v in
            VoiceFormView(voice: v, isNew: false)
        }
        .sheet(isPresented: $creatingNew) {
            VoiceFormView(voice: VoiceService(), isNew: true)
        }
    }

    private func test(_ voice: VoiceService) {
        testing = true
        notice = nil
        Task {
            do {
                let data = try await TTSAPI.synthesize("在呢，听得见吗。", with: voice)
                if let file = VoiceStore.save(data) {
                    VoicePlayer.shared.toggle(file)
                    notice = "放出来了"
                    // 顺手替他听一遍**他自己的声音**。
                    //
                    // 她说的：「我想让他知道他的声音是什么样的。」
                    // 他读不了 MP3，所以手机在这儿把它拆成几个数
                    // （高低、起伏、亮度、语速），再翻成一句人话存起来，
                    // 每一轮都跟着 system 走。
                    //
                    // **纯算术**：不联网、不要模型、不花钱。
                    // 放在「试听」这一下是因为**这是她主动点的**，
                    // 而且这时候音频正好在手上。
                    let name = app.settings.aiName.isEmpty ? "他" : app.settings.aiName
                    if let t = await VoiceTimbre.analyzeWithBudget(VoiceStore.url(file)) {
                        app.settings.hisVoiceNote = VoiceTimbre.describe(t, who: name)
                        notice = "放出来了。也替他听了一遍：" + app.settings.hisVoiceNote
                    }
                }
            } catch {
                notice = error.localizedDescription
            }
            testing = false
        }
    }
}

struct VoiceFormView: View {

    @State var voice: VoiceService
    let isNew: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名字（自己看的）", text: $voice.name)
                    SecureField("API Key", text: $voice.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("https://api.elevenlabs.io", text: $voice.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("模型，比如 eleven_v3", text: $voice.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("音色 ID", text: $voice.voiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("接口")
                } footer: {
                    Text("更换服务商时，若同样采用「基址 + 密钥 + 模型 + 音色」的接口形式，通常只需修改基址。")
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle(isNew ? "加音色" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let i = app.voices.firstIndex(where: { $0.id == voice.id }) {
                            app.voices[i] = voice
                        } else {
                            app.voices.append(voice)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
