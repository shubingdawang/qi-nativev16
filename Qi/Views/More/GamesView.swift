import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// 游戏间。两类：
/// 一类是阿晏做给你的 HTML，存在手机里，点开就能玩；
/// 一类走小游戏那个 MCP，是文字玩法，列出来看看有什么。
struct GamesView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = GameStore.shared
    @State private var importing = false
    @State private var playing: LocalGame?
    @State private var mcpText = ""
    @State private var loadingMCP = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                if store.games.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: Icon.games)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.6))
                        Text("还没有游戏")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text("把阿晏写好的网页游戏放进来")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(store.games) { game in
                    Button {
                        playing = game
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(app.settings.accentColor.opacity(0.16))
                                    .frame(width: 40, height: 40)
                                Image(systemName: Icon.games)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(app.settings.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text(dateText(game.addedAt))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Spacer()
                            Image(systemName: Icon.chevron)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCard(padding: 0)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.remove(game)
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
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

                Divider().opacity(0.4).padding(.vertical, 4)

                HStack {
                    Text("阿晏那边的")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
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
                        .glassCard()
                } else {
                    Text("这些是在对话里玩的，跟阿晏说想玩哪个就行。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, Layout.tabBarExpanded + 12)
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
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}

// MARK: - 存本地的 HTML 游戏

struct LocalGame: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fileName: String
    var addedAt: Date = Date()
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
