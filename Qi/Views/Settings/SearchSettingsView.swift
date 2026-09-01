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
