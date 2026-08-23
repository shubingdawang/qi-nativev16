import SwiftUI
import UniformTypeIdentifiers

/// 飞行棋那一页：选版本、看整盘、掷、导棋盘。
///
/// **格子里写什么不由这儿定。** 棋盘是导进来的——
/// 那些格子写的是他们俩之间的事，该由她定；
/// 写死在代码里的话，她想改一句都得等下一次构建。
struct FlightChessView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var game = FlightChess.shared

    @State private var importing = false
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var notice: String?
    @State private var fetching = false

    private var her: String { app.settings.userName.isEmpty ? "你" : app.settings.userName }
    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if game.hasBoards {
                    versionPicker
                    positions
                    rollBar
                    boardGrid
                } else {
                    empty
                }
                importBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("飞行棋")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.html, .json, .plainText],
                      allowsMultipleSelection: false) { result in
            handleFile(result)
        }
        .sheet(isPresented: $pasting) { pasteSheet }
        .alert("飞行棋", isPresented: Binding(get: { notice != nil },
                                           set: { if !$0 { notice = nil } })) {
            Button("好") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: 还没有棋盘

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有棋盘")
                .font(.app(14, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text("这一页只管走法：掷骰、走格、停下才生效、后进和退回、谁接受那一格。"
                 + "格子上写什么是你定的——把那份 index.html 导进来（九个版本一次全进），"
                 + "或者自己写一份 JSON 粘进来。")
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 选版本

    private var versionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("哪一副")
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(game.boards) { b in
                    Button {
                        guard b.id != game.state.boardID else { return }
                        game.newGame(boardID: b.id)
                    } label: {
                        Text(b.name)
                            .font(.app(12.5))
                            .lineLimit(1)
                            .foregroundStyle(b.id == game.state.boardID
                                             ? app.settings.accentColor
                                             : Theme.textMain(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(b.id == game.state.boardID
                                          ? app.settings.accentColor.opacity(0.16)
                                          : Theme.softFillDeep)
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            game.removeBoard(b.id)
                        } label: {
                            Label("删掉这一副", systemImage: "trash")
                        }
                    }
                }
            }
            Text("换一副＝重开一局。长按某一副可以删掉它。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 走到哪儿了

    private var positions: some View {
        HStack(spacing: 14) {
            side(name: her, pos: game.state.herPos, mine: true)
            side(name: him, pos: game.state.himPos, mine: false)
        }
    }

    private func side(name: String, pos: Int, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
            Text("第 \(pos) 格")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(isTurn(mine) ? app.settings.accentColor
                                              : Theme.textMain(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .glassCard(padding: 0)
    }

    private func isTurn(_ mine: Bool) -> Bool {
        game.state.turn == (mine ? "her" : "him")
    }

    // MARK: 掷

    private var rollBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            if game.state.stopped {
                Text("这一局停了（404）。想再来就上面换一副，或者再点一次同一副。")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else if game.state.finished {
                Text("走完了。换一副或者重开同一副。")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Button {
                    rollMine()
                } label: {
                    Text(game.state.turn == "her" ? "我掷一次" : "轮到他掷了")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(game.state.turn == "her"
                                      ? app.settings.accentColor
                                      : Theme.textMuted(scheme).opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(game.state.turn != "her")

                Text(game.state.turn == "her"
                     ? "掷完这一下会直接说给他听——他那边不用再掷一次。"
                     : "轮到他了。去聊天里跟他说一声，他自己掷。")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            if let ev = game.state.lastEvent {
                Divider().opacity(0.25)
                Text("刚才：\(ev.lander == "her" ? her : him)掷出 \(ev.dice)，"
                     + "停在第 \(ev.landed) 格"
                     + (ev.note.isEmpty ? "" : ev.note))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(ev.text)
                    .font(.app(13))
                    .foregroundStyle(Theme.textMain(scheme))
            }

            Button {
                game.stop()
            } label: {
                Text("404 · 停")
                    .font(.app(12))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func rollMine() {
        guard let ev = game.roll(who: "her") else { return }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // 掷完直接说给他听：**骰子已经掷完了**，他那边不该再掷一次。
        // 走旁白那条路（跟戳一戳一样）——这不是她说的话，是这一下发生了。
        if let cid = app.activeID(for: .chat) {
            app.send(text: game.brief(ev, herName: her, himName: him),
                     images: [], in: cid, narration: true)
        }
    }

    // MARK: 整盘

    private var boardGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(game.board?.name ?? "")
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 7)], spacing: 7) {
                ForEach(Array((game.board?.cells ?? []).enumerated()), id: \.offset) { i, cell in
                    cellChip(i, cell)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func cellChip(_ i: Int, _ cell: FCCell) -> some View {
        let hers = game.state.herPos == i
        let his = game.state.himPos == i
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("\(i)")
                    .font(.app(9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
                if hers { dot(app.settings.accentColor) }
                if his { dot(Theme.textMain(scheme).opacity(0.55)) }
            }
            Text(cell.text)
                .font(.app(10))
                .lineLimit(3)
                .foregroundStyle(Theme.textMain(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hers || his
                      ? app.settings.accentColor.opacity(0.13)
                      : Theme.softFillDeep)
        )
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    // MARK: 导棋盘

    private var importBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("棋盘")
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))

            Button { importing = true } label: {
                rowLabel("从文件导入", "把那份 index.html 或一份 JSON 选进来", "doc")
            }
            .buttonStyle(.plain)

            Button { pasteText = ""; pasting = true } label: {
                rowLabel("粘贴一段", "整份 index.html 的内容，或者自己写的 JSON", "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            Button { fetchFromRepo() } label: {
                rowLabel(fetching ? "正在下…" : "从那个仓库直接下",
                         "lili0926/player 的 index.html，九副一次全进", "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .disabled(fetching)

            Text("导进来的存在手机里，随时能重导一份顶掉。"
                 + "JSON 的格式：`[{\"id\":\"couple\",\"name\":\"情侣版\",\"cells\":[\"起点\",\"…\"]}]`")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func rowLabel(_ title: String, _ sub: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.app(15))
                .foregroundStyle(app.settings.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(13))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(sub)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pasteText)
                .font(.app(12))
                .padding(10)
                .navigationTitle("粘贴棋盘")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { pasting = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("导进来") {
                            take(pasteText)
                            pasting = false
                        }
                    }
                }
        }
    }

    // MARK: 真正干活的那几下

    /// 一段文本，是 HTML 还是 JSON 自己认
    private func take(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var found = FCImporter.boards(fromJSON: t)
        if found.isEmpty { found = FCImporter.boards(fromHTML: t) }
        guard !found.isEmpty else {
            notice = "这段里没找到棋盘。要么是那份 index.html 的全文，要么是一份 JSON 数组。"
            return
        }
        let n = game.importBoards(found)
        notice = "进来了 \(n) 副：" + found.map(\.name).joined(separator: "、")
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            notice = "这个文件读不出来。"
            return
        }
        take(text)
    }

    /// 直接去那个仓库下一份。她手机上不用先想办法把文件弄下来。
    private func fetchFromRepo() {
        guard let url = URL(string:
            "https://raw.githubusercontent.com/lili0926/player/main/index.html") else { return }
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    notice = "下下来了，但读不出来。"
                    return
                }
                take(text)
            } catch {
                notice = "没下下来：\(error.localizedDescription)。"
                    + "挂着梯子再试一次，或者用上面那两条路。"
            }
        }
    }
}
