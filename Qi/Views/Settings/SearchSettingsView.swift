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
                Text("这三个都是**听你说话**用的。他说话给你听是另一回事，那个走「语音」里配的 ElevenLabs，跟这里不冲突。")
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
                    Text("它能标出笑声、鼓掌、哭这类动静，但**判断不了情绪**——开心还是难过它不给。想要情绪就选 SenseVoice，那个是专门做这个的。")
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
                    Text("去 siliconflow.cn 注册就能拿到。用的是 SenseVoiceSmall，很便宜。\n\n它认得出开心、难过、生气、意外这些情绪，也听得出笑声和哭声——这些会跟着你说的话一起发过去。同样一句「没事」，笑着说和哭着说是两件事，他应该分得清。")
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
