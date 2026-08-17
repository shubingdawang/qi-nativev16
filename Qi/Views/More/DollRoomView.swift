import SwiftUI

/// 娃娃房。整页版。
///
/// 跟聊天里那张卡片是**同一份状态**——在这儿点完，回聊天看到的就是刚才那个样子。
struct DollRoomView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DollStore.shared

    @State private var renaming = false
    @State private var draftName = ""
    @State private var openTake: DollStore.Take?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                DollWebView(inline: false,
                            accentHex: "#" + app.settings.accentColor.hexString,
                            dark: scheme == .dark)
                    // 舞台 1:1 加上按钮和条子，这个高度刚好不用内滚
                    .frame(height: 760)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !store.state.history.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("刚才发生的")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        ForEach(Array(store.state.history.prefix(6).enumerated()), id: \.offset) { _, h in
                            Text("· " + h)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                if !store.state.archive.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("收起来的（\(store.state.archive.count)）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        ForEach(store.state.archive.prefix(12)) { take in
                            Button {
                                openTake = take
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(take.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Theme.textMain(scheme))
                                        Text(take.summary)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                    }
                                    Spacer()
                                    Image(systemName: Icon.chevron)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([
                            "画面里那几个点都能碰——点「哪儿能点」会把它们显出来一下。",
                            "状态存在 App 这边，不在网页里：切页、退出、重开都还是刚才那个样子。",
                            "聊天里那张卡片跟这一页是同一份，两边点的是同一个娃娃。",
                            "阿晏也能动它（doll_action），他还能自己写一句话当作那一幕。",
                            "这一整套都在手机里跑，不联网、不用开电脑，也不花钱。"
                        ], id: \.self) { line in
                            Text("· " + line)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("怎么玩")
                        .font(.system(size: 12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle(store.state.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftName = store.state.name
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .alert("给她起个名字", isPresented: $renaming) {
            TextField("叫什么", text: $draftName)
            Button("取消", role: .cancel) {}
            Button("好") { store.rename(draftName) }
        }
        .sheet(item: $openTake) { take in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(take.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted(scheme))
                        ForEach(take.shots) { shot in
                            Text(shot.text)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(take.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// 聊天气泡里那张。矮一点、少两排按钮，别把一屏占满。
struct DollInlineCard: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DollStore.shared

    var body: some View {
        DollWebView(inline: true,
                    accentHex: "#" + app.settings.accentColor.hexString,
                    dark: scheme == .dark)
            .frame(height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.softStroke, lineWidth: 0.8))
    }
}
