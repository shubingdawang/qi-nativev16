import SwiftUI

/// 中转站探针。
///
/// 出处：她给的 https://github.com/Cheiineeey/relay-cache-where-it-breaks
///
/// 它回答的是这个 App 自己回答不了的问题：我们这边 `cache_control` 标得再对，
/// 中转站转不转过去、上游认不认，从聊天页看不出来。
/// 39% 的命中率到底是「五分钟就凉了」还是「这个中转根本不支持」，
/// 只有对着同一个地址真发两次才分得清。
///
/// ⚠️⚠️ **每一项都是真实调用，她是按次计费的。**
/// 所以一件也不自动跑，每一项自己点，按钮上写着要花几次。
struct RelayProbeView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var results: [String: ProbeResult] = [:]
    @State private var running: String?
    @State private var showHistory = false
    @ObservedObject private var history = ProbeHistory.shared

    /// 拿哪个供应商去探。默认是这一窗正在用的那个。
    @State private var providerID: UUID?

    /// 絮语那一窗此刻用的是哪个供应商 / 哪个模型。
    ///
    /// ⚠️ **默认就探她真在用的那一套。** 随手挑一个供应商去探，
    /// 探出来的结论对她每天说话的那条线没有任何意义——
    /// 缓存这件事是**按地址 + 模型**成立的。
    private var live: (provider: UUID?, model: String?) {
        guard let id = app.activeID(for: .chat),
              let c = app.conversations.first(where: { $0.id == id })
        else { return (nil, nil) }
        return (c.providerID, c.modelID)
    }

    private var provider: Provider? {
        if let providerID, let p = app.providers.first(where: { $0.id == providerID }) {
            return p
        }
        if let id = live.provider, let p = app.providers.first(where: { $0.id == id }) {
            return p
        }
        return app.providers.first { $0.enabled }
    }

    private var modelID: String {
        // 换过供应商就用那家的第一个；没换过就用她此刻真在用的那个
        if providerID == nil || providerID == live.provider,
           let m = live.model, !m.isEmpty {
            return m
        }
        return provider?.models.first?.id ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                head
                if provider?.chatEndpoint == nil || modelID.isEmpty {
                    Text("请先在「设置 → 供应商」中配置地址与模型，再执行探测。")
                        .font(.app(12))
                        .foregroundStyle(.orange)
                        .glassCard()
                } else {
                    ForEach(RelayProbe.all) { probe in card(probe) }
                }
            }
            .padding(16)
            .padding(.bottom, Layout.tabBarExpanded)
        }
        .transparentList()
        .navigationTitle("探针")
        .navigationBarTitleDisplayMode(.inline)
        // 屏幕底下正中：历史记录（她要的位置）
        .safeAreaInset(edge: .bottom) {
            Button { showHistory = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.app(12))
                    Text(history.items.isEmpty ? "历史记录" : "历史记录 · \(history.items.count)")
                        .font(.app(13, weight: .medium))
                }
                .foregroundStyle(app.settings.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { ProbeHistoryView() }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = provider {
                Text(p.name.isEmpty ? "（没名字）" : p.name)
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(p.chatEndpoint?.absoluteString ?? p.baseURL)
                    .font(.app(10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(2)
                Text("拿「" + modelID + "」去探")
                    .font(.app(11))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            if app.providers.count > 1 {
                Picker("", selection: Binding(
                    get: { provider?.id ?? UUID() },
                    set: { providerID = $0 })) {
                    ForEach(app.providers) { p in
                        Text(p.name.isEmpty ? "（没名字）" : p.name).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(app.settings.accentColor)
            }
            HelpNote {
                Text(MD.inline(
                    "方法为**将同一请求发送两次**：首次写入缓存，第二次读取缓存，"
                    + "看第二次的 cache_read 是不是大于 0。\n\n"
                    + "填充内容**固定为约五千 token**，"
                    + "Anthropic 那边低于门槛（Sonnet 1024、Opus 4096）"
                    + "就算标了 cache_control 也不会真建缓存，"
                    + "那时候读到 0 跟中转站没关系。\n\n"
                    + "⚠️ **每一项均为真实调用，计入调用次数。**"
                    + "按钮上写着这一项要花几次。"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func card(_ probe: RelayProbe) -> some View {
        let r = results[probe.key]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let r {
                    Circle()
                        .fill(tone(r.tone))
                        .frame(width: 7, height: 7)
                }
                Text(probe.title)
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Button {
                    fire(probe)
                } label: {
                    HStack(spacing: 5) {
                        if running == probe.key {
                            ProgressView().controlSize(.mini)
                        }
                        Text(r == nil ? "探一下 · \(probe.calls) 次" : "再探一次")
                            .font(.app(11, weight: .medium))
                    }
                    .foregroundStyle(app.settings.accentColor)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                .disabled(running != nil)
            }

            Text(MD.inline(probe.why))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            if let r, !r.verdict.isEmpty {
                Text(MD.inline(r.verdict))
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFill))
                Text(shotLine(r))
                    .font(.app(9.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func shotLine(_ r: ProbeResult) -> String {
        r.shots.enumerated().map { i, s in
            "#\(i + 1) \(s.ok ? "\(s.status)" : "失败") · \(String(format: "%.1f", s.seconds))s"
        }.joined(separator: "   ")
    }

    private func tone(_ t: ProbeResult.Tone) -> Color {
        switch t {
        case .good: return .green
        case .unknown: return .orange
        case .bad: return .red
        }
    }

    private func fire(_ probe: RelayProbe) {
        guard let p = provider, let endpoint = p.chatEndpoint, !modelID.isEmpty else { return }
        running = probe.key
        Task { @MainActor in
            let r = await RelayProbeRunner.run(probe, endpoint: endpoint,
                                               apiKey: p.apiKey, model: modelID)
            results[probe.key] = r
            running = nil
            history.add(ProbeHistory.Entry(
                provider: p.name.isEmpty ? "（没名字）" : p.name,
                model: modelID,
                title: probe.title,
                verdict: r.verdict,
                shots: r.shots.enumerated().map { i, sh in
                    let u = sh.usage
                    return "#\(i + 1) " + (sh.ok ? "\(sh.status)" : "失败")
                        + String(format: " · %.1fs", sh.seconds)
                        + " · 输入 \(u.input) · 命中 \(u.cacheRead) · 写入 \(u.cacheWrite) · 输出 \(u.output)"
                        + (sh.error.isEmpty ? "" : " · " + String(sh.error.prefix(120)))
                },
                ok: r.tone == .good,
                unsure: r.tone == .unknown))
        }
    }
}


// MARK: - 探针的历史记录

/// 每探一次记一条。存在本机，最多留 300 条。
@MainActor
final class ProbeHistory: ObservableObject {
    static let shared = ProbeHistory()

    struct Entry: Codable, Identifiable {
        var id = UUID()
        var at = Date()
        var provider: String
        var model: String
        var title: String
        var verdict: String
        var shots: [String]
        var ok: Bool
        var unsure: Bool = false
    }

    @Published private(set) var items: [Entry] = []
    private let key = "relayProbeHistory"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([Entry].self, from: d) {
            items = v
        }
    }

    func add(_ e: Entry) {
        items.insert(e, at: 0)
        if items.count > 300 { items.removeLast(items.count - 300) }
        save()
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}

/// 历史记录那一页：一条一张卡。
/// 供应商 · 模型 / 探的什么 / 当时返回的数据 / 成功失败 + 时间
struct ProbeHistoryView: View {

    @ObservedObject private var history = ProbeHistory.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if history.items.isEmpty {
                    Text("暂无探测记录。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
                ForEach(history.items) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.provider + " · " + e.model)
                            .font(.app(11, design: .monospaced))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .lineLimit(1)
                        Text(e.title)
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(Theme.textMain(scheme))
                        if !e.verdict.isEmpty {
                            Text(MD.inline(e.verdict))
                                .font(.app(11.5))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(Array(e.shots.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.app(9.5, design: .monospaced))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(e.ok ? Color.green : (e.unsure ? Color.orange : Color.red))
                                .frame(width: 7, height: 7)
                            Text(e.ok ? "成功" : (e.unsure ? "不确定" : "失败"))
                                .font(.app(11, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Spacer(minLength: 0)
                            Text(Self.fmt.string(from: e.at))
                                .font(.app(10.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    .contextMenu {
                        Button(role: .destructive) {
                            history.remove([e.id])
                        } label: { Label("删掉这条", systemImage: "trash") }
                    }
                }
            }
            .padding(16)
        }
        .background(WallpaperBackground().ignoresSafeArea())
        .navigationTitle("探针历史")
        .navigationBarTitleDisplayMode(.inline)
    }
}
