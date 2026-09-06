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
        }
    }
}
