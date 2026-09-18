import SwiftUI

/// 「音乐」页右上角进来的那一页：登网易云账号、看每日推荐和红心。
///
/// 登录靠她自己浏览器里的 cookie（见 `NeteaseAccount`）。
/// 这一页要让她一眼知道三件事：登没登上、登的是谁、cookie 过期了没有。
struct NeteaseAccountView: View {

    /// 两个框分开填（她说的：「不然我每次都要打标题，好麻烦」）
    @State private var musicU = ""
    @State private var csrf = ""
    @State private var cookie = NeteaseAccount.Cookie.load()
    @State private var who: String?
    @State private var daily: [NeteaseAccount.Song] = []
    @State private var liked: [NeteaseAccount.Song] = []
    @State private var why: String?
    @State private var loading = false

    var body: some View {
        QiForm {
            Section {
                if cookie.isSet {
                    HStack {
                        Text(who.map { "已登录：\($0)" } ?? (loading ? "正在确认…" : "已填 cookie"))
                        Spacer()
                        Button("退出", role: .destructive) {
                            cookie = NeteaseAccount.Cookie()
                            cookie.save()
                            who = nil; daily = []; liked = []
                        }
                        .font(.footnote)
                    }
                }
                // 只粘值就行，不用写「MUSIC_U=」；整段 cookie 粘进第一个框也认得出来
                TextField(cookie.musicU.isEmpty ? "MUSIC_U" : "MUSIC_U（已填，要换就粘新的）",
                          text: $musicU, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(cookie.csrf.isEmpty ? "__csrf" : "__csrf（已填，要换就粘新的）", text: $csrf)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("存下并确认") {
                    var c = cookie
                    let u = musicU.trimmingCharacters(in: .whitespacesAndNewlines)
                    if u.contains("=") {
                        // 整段 cookie 粘进来了：两样都从里面取
                        let parsed = NeteaseAccount.Cookie.parse(u)
                        if !parsed.musicU.isEmpty { c.musicU = parsed.musicU }
                        if !parsed.csrf.isEmpty { c.csrf = parsed.csrf }
                    } else if !u.isEmpty {
                        c.musicU = u
                    }
                    let k = csrf.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "__csrf=", with: "")
                    if !k.isEmpty { c.csrf = k }
                    cookie = c
                    cookie.save()
                    musicU = ""; csrf = ""
                    Task { await refresh() }
                }
                .disabled(musicU.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && csrf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("网易云账号")
            } footer: {
                Text("电脑浏览器登录 music.163.com → 按 F12 → 应用程序（Application）→ Cookie，"
                     + "把 MUSIC_U 和 __csrf 两项的值分别粘进上面两个框。"
                     + "只存在本机，不进备份。__csrf 过期后红心、改歌单会失败，只换第二个框即可。")
            }

            if let why {
                Section { Text(why).font(.footnote).foregroundStyle(.orange) }
            }

            if !daily.isEmpty {
                Section("今日推荐") {
                    ForEach(daily.prefix(10), id: \.id) { songRow($0) }
                }
            }
            if !liked.isEmpty {
                Section("最近红心") {
                    ForEach(liked.prefix(10), id: \.id) { songRow($0) }
                }
            }
        }
        .navigationTitle("网易云")
        .navigationBarTitleDisplayMode(.inline)
        .task { if cookie.isSet { await refresh() } }
        .refreshable { await refresh() }
    }

    private func songRow(_ s: NeteaseAccount.Song) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.name)
            Text(s.artist).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        loading = true
        why = nil
        defer { loading = false }
        do {
            let (_, nick) = try await NeteaseAccount.uid()
            who = nick.isEmpty ? "（没有昵称）" : nick
            daily = (try? await NeteaseAccount.daily()) ?? []
            liked = (try? await NeteaseAccount.liked(limit: 10)) ?? []
        } catch {
            // ⚠️ 原样给她看：过期了要她去重抓 cookie，不是去查网
            why = error.localizedDescription
        }
    }
}
