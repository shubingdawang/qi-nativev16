import SwiftUI
import UniformTypeIdentifiers

/// 音乐库。
///
/// 说明一下跟图标的区别：**歌是随时导入的，不用重新构建。**
/// 图标那个是特例——iOS 规定备用图标必须打包时就在，所以只能走仓库。
/// 除了图标，App 里所有东西（歌、书、表情包、文件）都是运行时导进来的。
struct MusicLibraryView: View {

    @ObservedObject private var library = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var importing = false
    @State private var keyword = ""
    @State private var searching = false
    @State private var webResults: [Track] = []
    @State private var notice: String? {
        didSet {
            // ⚠️ 说完自己走。
            // 她报的：「导入后会显示导入了 x 首歌，没有消掉会一直显示。」
            // 那句话是**一次性的回执**，不是这一页的状态——
            // 常驻在那儿之后，她下次进来还看见「导进来 3 首」，
            // 会以为刚刚又导了一次。
            guard notice != nil else { return }
            let mine = notice
            noticeTask?.cancel()
            noticeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled, notice == mine { notice = nil }
            }
        }
    }
    @State private var noticeTask: Task<Void, Never>?
    @State private var showingLyrics = false
    /// 按歌手分组还是排成一长条
    @AppStorage("musicGroupByArtist") private var byArtist = false
    /// 长按某首歌弹出来的那个
    @State private var regrouping: Track?
    @State private var artistDraft = ""

    /// 文件不在了那句话。
    ///
    /// ⚠️⚠️ **拆出来是为了能编过。** 原来它是写在 `Text(...)` 里的
    /// 一串 `+`：一个可选解包加三段字面量，摆在 `alert` 的
    /// `message:` 那个泛型闭包里——编译器要在那儿同时定
    /// `Text` 的初始化重载、`+` 的几十个重载、`??` 的两个重载，
    /// 组合爆了，报的是
    /// 「unable to type-check this expression in reasonable time」。
    ///
    /// ⚠️ 这个错**跟改动大小无关**：它是有阈值的，
    /// 同一个文件里别处多几行就可能把它顶过线。
    /// 所以记一句：**别在 ViewBuilder 里拼长字符串。**
    /// 先在外面把 `String` 拼好，`Text` 只接一个现成的值。
    private var missingWhy: String {
        let br = "\n\n"
        var s = player.missingFile ?? ""
        s += br
        s += "两种可能：一是这首超过 20 MB，备份本来就不带"
        s += "（整包会大到导不出来）；"
        s += "二是它是被 v112 之前那个备份路径 bug 弄丢的。"
        s += "从「文件」重新导一次就行。"
        return s
    }

    private var mine: [Track] { library.search(keyword) }

    /// 按歌手分好组。
    ///
    /// ⚠️ 分组用的是 `groupName`（她自己改过的那个），
    /// 不是 `artist`。她的原话：「长按可以选择分组，
    /// 以免一些歌手艺名不同」——
    /// 同一个人在不同文件里的歌手名可能写法不一样
    /// （简繁体、中英文、带不带乐队名），
    /// **按原始歌手名分组一定会把一个人拆成好几组**。
    /// 所以分组名得能改，而且改的是**另一个字段**——
    /// 原始歌手名是文件里读出来的事实，不该被抹掉。
    private var grouped: [(String, [Track])] {
        var box: [String: [Track]] = [:]
        for t in mine {
            box[t.groupName, default: []].append(t)
        }
        // 歌多的排前面；一样多的按名字。
        // 「不知道歌手」那组永远排最后——它不是一个人。
        return box.sorted { a, b in
            if a.key == Track.unknownArtist { return false }
            if b.key == Track.unknownArtist { return true }
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.key < b.key
        }.map { ($0.key, $0.value) }
    }

    var body: some View {
        // ⚠️ 「正在放的那首」**钉在顶上，不跟着列表滚**。
        //
        // 她的原话：「最顶上那个可以点击进入歌词页的应该固定在页面的顶上，
        // 就是当我下滑音乐列表的时候歌词页依旧在顶上，随时可以点进去，
        // 不然每次划到很下面找歌还要划到最上才能点进去。」
        //
        // 以前它是 ScrollView **里面**的第一个子元素，
        // 所以一往下滑就跑掉了。现在摆到 ScrollView 外面。
        VStack(spacing: 0) {
            if let now = player.current {
                nowPlayingRow(now)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            listBody
        }
        .navigationTitle("音乐")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var listBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: Icon.search)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                        TextField("找歌，或者搜网上的", text: $keyword)
                            .textFieldStyle(.plain)
                            .font(.app(14))
                            .submitLabel(.search)
                            .onSubmit { Task { await searchWeb() } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.softFillDeep))

                    // ⚠️ 走 `ImportButton`：弹窗不能挂在这一页上。
                    // 这一页订阅了 `app`，后台存盘、身体推进、他在别的窗口
                    // 回了一句话，都会重建它，正在弹的选择器当场被撤掉——
                    // 跟当初「导入备份要点五次」是同一个病。
                    ImportButton(title: "", icon: Icon.add,
                                 types: [.audio, .mp3, .mpeg4Audio, .data],
                                 multiple: true,
                                 label: AnyView(
                                    Image(systemName: Icon.add)
                                        .font(.app(16))
                                        .foregroundStyle(app.settings.accentColor)
                                        .frame(width: 34, height: 34)
                                        .contentShape(Rectangle())
                                 ),
                                 // ⚠️ 这个标签不能省：`label` 排在 `onPick`
                                 // 前面，尾随闭包往回配会先撞上它——
                                 // 编译器现在只是警告，以后就不认了。
                                 onPick: { result in
                        guard case .success(let urls) = result else { return }
                        var added = 0
                        var dup = 0
                        for u in urls {
                            guard let t = MusicStore.importFile(from: u) else { continue }
                            // ⚠️ `add` 现在会查重，重了就把已有那首还回来。
                            // 靠「回来的是不是同一件」判断这次到底收没收——
                            // 只数 importFile 成功几次的话，
                            // 重复导入十次也会说「导进来 10 首」。
                            let got = library.add(t)
                            if got.id == t.id { added += 1 } else { dup += 1 }
                        }
                        if added == 0 && dup > 0 {
                            notice = "这 \(dup) 首库里已经有了"
                        } else if dup > 0 {
                            notice = "导进来 \(added) 首，另外 \(dup) 首库里已经有了"
                        } else {
                            notice = added > 0 ? "导进来 \(added) 首" : "这些文件读不出来"
                        }
                    })
                }

                if let notice {
                    Text(notice)
                        .font(.app(11))
                        .foregroundStyle(.orange)
                }

                // ⚠️ 判空要用 `playable`。库里躺着二十几条音频已经没了的记录，
                // `tracks.isEmpty` 是 false——于是「还没有歌」那段提示不出来，
                // 她看到的是一页什么都没有的空白。
                if library.playable.isEmpty && webResults.isEmpty {
                    EmptyNote(icon: "music.note.list",
                              title: "还没有歌",
                              hint: "点击右上角从「文件」导入 mp3、m4a、flac。\n"
                                  + "网易云下载的音频需先存入「文件」App 再导入，导入后为完整音频。\n"
                                  + "上方搜索框检索的是网络试听资源，时长三十秒。")
                        .padding(.top, 20)
                }

                if !mine.isEmpty {
                    HStack(spacing: 8) {
                        Text("我的")
                            .font(.app(13, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Spacer(minLength: 0)
                        // 分组开关。记在 `@AppStorage` 里——
                        // 她选完一次就不应该再选第二次
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { byArtist.toggle() }
                        } label: {
                            Label(byArtist ? "按歌手分组" : "不分组",
                                  systemImage: byArtist
                                  ? "person.2" : "list.bullet")
                                .font(.app(11))
                                .foregroundStyle(app.settings.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if byArtist {
                        ForEach(grouped, id: \.0) { name, list in
                            Text(name)
                                .font(.app(11, weight: .medium))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 4)
                            ForEach(list) { track in
                                row(track, local: true)
                            }
                        }
                    } else {
                        ForEach(mine) { track in
                            row(track, local: true)
                        }
                    }
                }

                // 音频没了的那些**不列出来**（她定的：「音乐既然没有备份了，
                // 就不要显示歌名了，不然每次还要一个个删掉有点麻烦」）。
                //
                // 但也不闷声抹掉——那样她会以为歌是自己蒸发的。
                // 这儿留一句话，要清她自己点；不点就一直藏着，
                // 哪天音频回来了（重新导一份带音频的备份），歌自己就冒出来了。
                if !library.orphans.isEmpty {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("有 \(library.orphans.count) 首的音频文件不在了")
                                .font(.app(12))
                                .foregroundStyle(Theme.textSoft(scheme))
                            Text("先藏起来了。音频找回来它们自己会回来；不想等就清掉。")
                                .font(.app(10.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Spacer(minLength: 0)
                        Button("清掉") {
                            let n = library.dropOrphans()
                            notice = "清掉了 \(n) 首没有音频的记录。"
                        }
                        .font(.app(12))
                        .buttonStyle(.plain)
                        .foregroundStyle(app.settings.accentColor)
                    }
                    .padding(.vertical, 8)
                }

                if searching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("在搜…").font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }

                if !webResults.isEmpty {
                    Text("网络试听（三十秒）")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.top, 6)
                    ForEach(webResults) { track in
                        row(track, local: false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        // 标题挂在外面那一层了，这儿不能再挂一遍
        // 点了一首文件已经不在的歌。**不能一声不吭**——
        // 以前只是什么都不发生，她只会觉得「这 App 坏了」。
        .alert("这首歌的文件不在了", isPresented: Binding(
            get: { player.missingFile != nil },
            set: { if !$0 { player.missingFile = nil } }
        )) {
            Button("好") { player.missingFile = nil }
        } message: {
            Text(missingWhy)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PlayCountView()
                } label: {
                    Image(systemName: "chart.bar")
                }
            }
        }
        .alert("归到哪个歌手", isPresented: Binding(
            get: { regrouping != nil }, set: { if !$0 { regrouping = nil } }
        )) {
            TextField("歌手名", text: $artistDraft)
            Button("取消", role: .cancel) { regrouping = nil }
            Button("归好了") {
                if let t = regrouping { library.regroup(t.id, to: artistDraft) }
                regrouping = nil
            }
        } message: {
            Text("改的只是分组，歌曲自带的歌手名不会被改掉。\n"
                 + "同一个人的歌写成同一个分组名，就会归到一起。")
        }
        .fullScreenCover(isPresented: $showingLyrics) { NowPlayingView() }

    }

    /// 正在放的那一条。整条都能点，进歌词页。
    private func nowPlayingRow(_ track: Track) -> some View {
        Button {
            showingLyrics = true
        } label: {
            HStack(spacing: 11) {
                // 那个「正在播放的音乐头像」。转起来，一眼看出它是活的。
                TrackArtwork(track: track, side: 46)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text(nowLine ?? (track.subtitle.isEmpty ? "一起听着" : track.subtitle))
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(12)
            .glassCard(padding: 0)
            // ⚠️ 整条都要能点。
            // 她报的：「音乐功能里最顶上的点击进入歌词页也是跟聊天记录一个毛病，
            // 不是整条都能点击的。」——对，`buttonStyle(.plain)` 下
            // 能点的只有真画出来的字和图，`Spacer` 和 padding 是透明的。
            // 跟侧边栏那几行是同一个病。
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var nowLine: String? {
        guard let i = player.currentLine,
              player.lines.indices.contains(i) else { return nil }
        return player.lines[i].text
    }

    private func row(_ track: Track, local: Bool) -> some View {
        let isCurrent = player.current?.id == track.id
        return Button {
            player.toggle(track)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isCurrent && player.playing ? "pause.fill" : "play.fill")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(app.settings.accentColor.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.app(14))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    if !track.subtitle.isEmpty {
                        Text(track.subtitle)
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                if !local {
                    Text("试听")
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(padding: 0)
        .contextMenu {
            if local {
                // 她要的：长按选分组。
                // 现有的分组名直接列出来——
                // **归一首歌到已有的人名下面，不该需要重新打一遍那个名字**，
                // 打一遍就有可能打成另一个写法，那就又拆成两组了。
                Menu("归到哪个歌手") {
                    ForEach(library.groupNames, id: \.self) { n in
                        Button(n) { library.regroup(track.id, to: n) }
                    }
                    Divider()
                    Button("另起一个名字…") {
                        artistDraft = track.groupName
                        regrouping = track
                    }
                    if !track.artistGroup.isEmpty {
                        Button("改回原来的（\(track.artist)）") {
                            library.regroup(track.id, to: "")
                        }
                    }
                }
                Button(role: .destructive) {
                    library.remove(track)
                } label: {
                    Label("删掉", systemImage: Icon.trash)
                }
            }
        }
    }

    private func searchWeb() async {
        guard !keyword.isEmpty else { return }
        searching = true
        notice = nil

        // 三条路，从好到差依次退。
        //
        // ① 她要是配了电脑上那套，先走它——**只有那条能放 VIP**
        // ② 没配（或者没通）就**手机直连网易云**：整首 + 歌词，不用电脑、
        //    不用登录、不用配任何东西。这条是常态
        // ③ 直连也不成，才退回 iTunes 那三十秒
        //
        // 一路退到底也不报错让她一首都听不成——
        // **有得听比有个错误提示强。**

        let base = app.settings.neteaseBaseURL.trimmingCharacters(in: .whitespaces)
        if !base.isEmpty {
            if let r = try? await MusicSearch.searchNetease(keyword, base: base, limit: 8),
               !r.isEmpty {
                webResults = r
                searching = false
                return
            }
            notice = "你电脑那套没通，用直连的"
        }

        if let r = try? await MusicSearch.searchNeteaseDirect(keyword, limit: 10),
           !r.isEmpty {
            webResults = r
            searching = false
            return
        }

        do {
            webResults = try await MusicSearch.search(keyword, limit: 8)
            if notice == nil, !webResults.isEmpty {
                notice = "网易云没搜到能放的，这些是 iTunes 的三十秒试听"
            }
        } catch {
            notice = error.localizedDescription
            webResults = []
        }
        searching = false
    }
}

// MARK: - 一起听

/// 聊天页顶上的那条。放着歌的时候才出现，写着「一起听着」。
struct ListeningBar: View {

    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                TrackArtwork(track: track, side: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.app(12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text("一起听着")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Spacer(minLength: 4)

                Button {
                    player.playing ? player.pause() : player.resume()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(10, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassBackground(radius: 18, strength: app.settings.glassOpacity, extra: 0.15)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
