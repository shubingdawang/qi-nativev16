import SwiftUI

/// 联网搜用哪家。
struct SearchSettingsView: View {

    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            Section {
                ForEach(SearchEngine.allCases) { engine in
                    Button {
                        app.settings.searchEngine = engine
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: app.settings.searchEngine == engine
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(app.settings.accentColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(engine.title).foregroundStyle(.primary)
                                Text(engine.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("搜索源")
            }

            if app.settings.searchEngine == .tavily {
                Section {
                    SecureField("Tavily API Key", text: $app.settings.tavilyKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("密钥")
                } footer: {
                    Text("去 tavily.com 注册就能拿到，每月一千次免费，够用很久了。密钥只存在这台手机上。")
                }
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
        }
        .navigationTitle("联网搜索")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 语音输入走哪条路
struct VoiceInputSettingsView: View {

    @EnvironmentObject var app: AppState

    var body: some View {
        List {
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
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
        }
        .navigationTitle("语音输入")
        .navigationBarTitleDisplayMode(.inline)
    }
}
