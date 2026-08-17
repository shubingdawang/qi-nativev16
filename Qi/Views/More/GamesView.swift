import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// 游戏间。
///
/// 顶上两栏，跟聊天记录那页一个样式：
///
/// · **网页** —— 存在手机里、点开就在 App 里跑的那些（阿晏写的 HTML、娃娃房）
/// · **对话** —— 在聊天里玩的那些（大富翁、MCP 那边的小游戏）
///
/// 栏里再按类型分组。分类是按**怎么玩**分的，不是按技术实现分的——
/// 「这是 MCP 还是本地」她不需要关心，能不能点开玩、在哪儿玩才是要紧的。
struct GamesView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = GameStore.shared
    @ObservedObject private var mono = MonopolyGame.shared

    @State private var tab = 0            // 0 网页，1 对话
    @State private var importing = false
    @State private var playing: LocalGame?
    @State private var mcpText = ""
    @State private var loadingMCP = false
    @State private var pickingGenre: LocalGame?

    var body: some View {
        VStack(spacing: 0) {

            Picker("", selection: $tab) {
                Text("网页").tag(0)
                Text("对话").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == 0 { webTab } else { talkTab }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 12)
            }
        }
        .navigationTitle("游戏")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.html],
                      allowsMultipleSelection: true) { result in
            store.importFiles(result)
        }
        .fullScreenCover(item: $playing) { game in
            GamePlayerView(game: game)
        }
        .confirmationDialog("这算哪一类", isPresented: Binding(
            get: { pickingGenre != nil },
            set: { if !$0 { pickingGenre = nil } })) {
            ForEach(GameGenre.allCases, id: \.self) { g in
                Button(g.label) {
                    if let target = pickingGenre { store.setGenre(target, g) }
                    pickingGenre = nil
                }
            }
        }
    }

    // MARK: 网页

    @ViewBuilder
    private var webTab: some View {
        // 内置的那些排最前面
        section(GameGenre.raise.label) {
            NavigationLink {
                DollRoomView()
            } label: {
                row(title: DollStore.shared.state.name,
                    sub: "能点的娃娃 · 聊天里也有一张同样的卡片",
                    icon: "hand.tap")
            }
            .buttonStyle(.plain)
        }

        let grouped = Dictionary(grouping: store.games) { $0.genreValue }
        ForEach(GameGenre.allCases, id: \.self) { genre in
            if let list = grouped[genre], !list.isEmpty {
                section(genre.label) {
                    ForEach(list) { game in
                        Button {
                            playing = game
                        } label: {
                            row(title: game.name, sub: dateText(game.addedAt), icon: Icon.games)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                pickingGenre = game
                            } label: {
                                Label("改分类", systemImage: "tag")
                            }
                            Button(role: .destructive) {
                                store.remove(game)
                            } label: {
                                Label("删掉", systemImage: Icon.trash)
                            }
                        }
                    }
                }
            }
        }

        if store.games.isEmpty {
            Text("阿晏写的网页游戏放进来就能玩，长按可以改分类。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
        }

        Button {
            importing = true
        } label: {
            Label("放一个进来", systemImage: Icon.add)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(app.settings.accentColor.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 对话

    @ViewBuilder
    private var talkTab: some View {
        section(GameGenre.board.label) {
            NavigationLink {
                MonopolyView()
            } label: {
                row(title: "涩涩大富翁",
                    sub: mono.s.live
                         ? "开着局 · 回合 \(mono.s.turnCount)/\(mono.s.totalRounds) · 该 \(mono.s.turn) 掷"
                         : "两个人的棋盘 · 引擎在手机里，不用开电脑",
                    icon: "dice")
            }
            .buttonStyle(.plain)
        }

        section("阿晏那边的") {
            HStack {
                Text("在对话里玩的，跟他说想玩哪个就行")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                Button {
                    Task {
                        loadingMCP = true
                        let r = await app.callTool("list_games", args: [:])
                        mcpText = r.text
                        loadingMCP = false
                    }
                } label: {
                    if loadingMCP { ProgressView() }
                    else { Image(systemName: Icon.refresh).foregroundStyle(app.settings.accentColor) }
                }
                .buttonStyle(.plain)
            }
            if !mcpText.isEmpty {
                Text(mcpText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: 零件

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(title: String, sub: String, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(app.settings.accentColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(app.settings.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer()
            Image(systemName: Icon.chevron)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}

// MARK: - 分类

/// 按**怎么玩**分，不按技术实现分。
/// 她说过「我也不太确定是 mcp 还是什么」——那本来就不该她操心。
enum GameGenre: String, CaseIterable, Codable {
    case board, raise, puzzle, text, other

    var label: String {
        switch self {
        case .board:  return "桌游"
        case .raise:  return "养成"
        case .puzzle: return "益智"
        case .text:   return "文字"
        case .other:  return "其他"
        }
    }
}

// MARK: - 存本地的 HTML 游戏

struct LocalGame: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fileName: String
    var addedAt: Date = Date()
    /// 分类。**旧的 games.json 里没有这个字段**，所以下面写了容错解码器——
    /// 不写的话合成的解码器会直接抛，她放进去的游戏会整份读不出来
    /// （规矩见 Models.swift 末尾那一段）。
    var genre: String = GameGenre.other.rawValue

    var genreValue: GameGenre { GameGenre(rawValue: genre) ?? .other }

    init(name: String, fileName: String) {
        self.name = name
        self.fileName = fileName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "没名字"
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? Date()
        genre = (try? c.decodeIfPresent(String.self, forKey: .genre)) ?? GameGenre.other.rawValue
    }
}

@MainActor
final class GameStore: ObservableObject {

    static let shared = GameStore()

    @Published var games: [LocalGame] = [] {
        didSet { if loaded { Storage.save(games, to: "games.json") } }
    }
    private var loaded = false

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Games", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    init() {
        games = Storage.load([LocalGame].self, from: "games.json") ?? []
        loaded = true
    }

    func url(for game: LocalGame) -> URL {
        GameStore.dir.appendingPathComponent(game.fileName)
    }

    func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for src in urls {
            let needsStop = src.startAccessingSecurityScopedResource()
            defer { if needsStop { src.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: src) else { continue }
            let fileName = UUID().uuidString + ".html"
            let dest = GameStore.dir.appendingPathComponent(fileName)
            do {
                try data.write(to: dest, options: .atomic)
                let name = src.deletingPathExtension().lastPathComponent
                games.append(LocalGame(name: name, fileName: fileName))
            } catch { continue }
        }
    }

    func setGenre(_ game: LocalGame, _ genre: GameGenre) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[i].genre = genre.rawValue
    }

    func remove(_ game: LocalGame) {
        try? FileManager.default.removeItem(at: url(for: game))
        games.removeAll { $0.id == game.id }
    }
}

// MARK: - 玩

struct GamePlayerView: View {
    let game: LocalGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LocalWebView(url: GameStore.shared.url(for: game))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(game.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("退出") { dismiss() }
                    }
                }
        }
    }
}

/// 跑本地 HTML 的容器
struct LocalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}
