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
    @ViewBuilder
    private var inputSections: some View {

            Section {
                ForEach(VoiceInputMode.allCases) { mode in
                    Button {
                        app.settings.voiceInput = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: app.settings.voiceInput == mode
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(app.settings.accentColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).foregroundStyle(.primary)
                                Text(mode.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("按住说话时用哪个")
            } footer: {
                Text(MD.inline("以下三项用于语音识别（输入）。语音合成（输出）在「语音」中配置，两者互不影响。"))
            }

            if app.settings.voiceInput == .elevenLabs {
                Section {
                    Text(app.activeVoice == nil
                         ? "还没配 ElevenLabs。去「设置 → 语音」填一次密钥，这里就能直接用。"
                         : "用的是「语音」里那个密钥，不用另填。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("密钥")
                } footer: {
                    Text(MD.inline("可识别笑声、鼓掌、哭泣等声音事件，但不输出情绪判定。需要情绪识别请选择 SenseVoice。"))
                }
            }

            if app.settings.voiceInput == .senseVoice {
                Section {
                    SecureField("SiliconFlow API Key", text: $app.settings.siliconKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("密钥")
                } footer: {
                    Text("密钥在 siliconflow.cn 注册获取，使用 SenseVoiceSmall 模型，费用较低。\n\n可识别开心、难过、生气、意外等情绪，以及笑声与哭声。识别结果随语音文本一并发送，用于区分相同措辞的不同语气。")
                }
            }
    }

    var body: some View {
        List {
            // ⚠️⚠️ **「语音输入」并进来了，不再是单独一页。**
            //
            // 她定的：「语音输入和语音服务合并，都是语音功能。」
            // 一个是她说话转文字、一个是他说话出声——
            // 分成设置页上两行，看着像两件不相干的事，
            // 而她想调「语音」的时候得先猜是哪一个。
            //
            // 上半是**她这边**（识别），下半是**他那边**（合成）。
            inputSections

            if app.voices.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有语音服务")
                            .font(.headline)
                        Text("配置完成后，长按任意消息可朗读；模型也可主动发送语音消息。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(app.voices) { voice in
                Section {
                    Button {
                        editing = voice
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(voice.name.isEmpty ? "未命名" : voice.name)
                                    .foregroundStyle(.primary)
                                Text(voice.ready ? voice.voiceID : "还没填全")
                                    .font(.caption)
                                    .foregroundStyle(voice.ready ? Color.secondary : Color.orange)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: Icon.chevron)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Toggle("用这个", isOn: Binding(
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
                    ))

                    Button {
                        test(voice)
                    } label: {
                        HStack {
                            Label("试听", systemImage: "waveform")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!voice.ready || testing)
                }
            }
            .onDelete { offsets in
                app.voices.remove(atOffsets: offsets)
            }

            Section {
                Button {
                    creatingNew = true
                } label: {
                    Label("添加音色", systemImage: Icon.add)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("音色 ID 在 ElevenLabs 网站上每个声音的详情里能找到。同一个密钥下可以放好几个音色，随时切。")
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
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
