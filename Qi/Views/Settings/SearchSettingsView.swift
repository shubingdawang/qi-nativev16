import SwiftUI

/// 联网搜用哪家。
///
/// ⚠️⚠️ **这一页原来是 `List`，换成了跟设置页一样的卡片。**
///
/// 她第二次报同一件事：「对话设定／供应商／编辑 MCP／联网搜索
/// 依旧不是玻璃气泡框。」
///
/// 玻璃**其实一直挂着**（`.listRowBackground(GlassRowBackground())`），
/// 可它盖不住：`List` 默认是 `insetGrouped`，那一层白圆角是
/// **分组容器自己画的**，行背景压在它上面，白底照样透出来。
///
/// 记一句：**`listRowBackground` 管的是「行」，管不了分组的底。**
/// 语音、MCP 那两页当初也是这个病，换成 `SettingsCard` 之后就对了。
struct SearchSettingsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WallpaperBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SettingsCard(title: "搜索源") {
                        ForEach(Array(SearchEngine.allCases.enumerated()),
                                id: \.element.id) { i, engine in
                            if i > 0 { SettingsDivider() }
                            engineRow(engine)
                        }
                    }

                    if app.settings.searchEngine.needsKey {
                        SettingsCard(title: "密钥") {
                            SecureField(app.settings.searchEngine.title + " API Key",
                                        text: $app.settings.tavilyKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.app(15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                            SettingsNote(app.settings.searchEngine.keyHint
                                         + "\n\n各搜索源共用这一个输入框，更换搜索源后需重新填写对应密钥。",
                                         title: "说明")
                        }
                    }

                    if app.settings.searchEngine == .searx {
                        SettingsCard(title: "实例地址") {
                            TextField(WebSearch.defaultSearxHost, text: $app.settings.searxHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.app(15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                            SettingsNote("留空则使用 " + WebSearch.defaultSearxHost
                                         + "。可填写其他公共实例或自建实例地址；"
                                         + "实例未开放 JSON 接口时，自动改用必应网页结果。",
                                         title: "说明")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("联网搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func engineRow(_ engine: SearchEngine) -> some View {
        Button {
            app.settings.searchEngine = engine
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: app.settings.searchEngine == engine
                      ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(app.settings.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.title)
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(engine.note)
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
