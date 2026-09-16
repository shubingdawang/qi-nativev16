import SwiftUI

/// 「音乐」页右上角进来的那一页：登网易云账号、看每日推荐和红心。
///
/// 登录靠她自己浏览器里的 cookie（见 `NeteaseAccount`）。
/// 这一页要让她一眼知道三件事：登没登上、登的是谁、cookie 过期了没有。
struct NeteaseAccountView: View {

    @State private var raw = ""
    @State private var cookie = NeteaseAccount.Cookie.load()
    @State private var who: String?
    @State private var daily: [NeteaseAccount.Song] = []
    @State private var liked: [NeteaseAccount.Song] = []
    @State private var why: String?
    @State private var loading = false

    var body: some View {
        Form {
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
                TextField("粘贴 cookie（整段，或只粘 MUSIC_U 的值）", text: $raw, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("存下并确认") {
                    var c = NeteaseAccount.Cookie.parse(raw)
                    // 只粘了 MUSIC_U 的时候，别把之前填过的 __csrf 冲掉
                    if c.csrf.isEmpty { c.csrf = cookie.csrf }
                    cookie = c
                    cookie.save()
                    raw = ""
                    Task { await refresh() }
                }
                .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("网易云账号")
            } footer: {
                Text("电脑浏览器登录 music.163.com → 按 F12 → 应用程序（Application）→ Cookie → "
                     + "复制 MUSIC_U 和 __csrf 两项，写成「MUSIC_U=…; __csrf=…」粘进来。"
                     + "只存在本机，不进备份。__csrf 过期后红心、改歌单会失败，重新复制一次即可。")
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
