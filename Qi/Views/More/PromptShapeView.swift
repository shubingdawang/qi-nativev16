import SwiftUI

/// 「这一份都花在哪儿」。
///
/// 她问过好几次：「token 依旧是 12w 多」「是注入太多了吗」。
/// 我每次只能凭着读代码猜——**猜是最没用的回答**。
/// 这一页把上一次真发出去的那份请求分块量出来，她自己看得见。
///
/// 入口：聊天里每条底下那行「N tokens」，点一下就是这儿。
struct PromptShapeView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var shape: PromptShape? { app.lastPromptShape }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = shape {
                    VStack(alignment: .leading, spacing: 14) {
                        total(s)
                        ForEach(s.blocks) { b in row(b, of: s.total) }
                        cacheNote(s)
                        if !s.fattestTools.isEmpty { tools(s) }
                        Text(MD.inline("此处数值为**估算**。实际 token 数以接口返回为准，"
                             + "即每条消息下方标注的数值。本页用于查看**各部分的占比**，"
                             + "谁比谁大三倍，估着也看得出来。"))
                            .font(.app(10.5))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(16)
                } else {
                    Text("尚无请求记录。发送一条消息后再查看。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(32)
                }
            }
            .transparentList()
            .navigationTitle("都花在哪儿")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func total(_ s: PromptShape) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("上一次发出去大约")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
            Text(k(s.total))
                .font(HomeType.number(30, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text("\(s.messageCount) 条消息 · \(s.toolCount) 件工具"
                 + (s.imageCount > 0 ? " · \(s.imageCount) 张图" : ""))
                .font(.app(11))
                .foregroundStyle(Theme.textSoft(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ b: PromptBlock, of total: Int) -> some View {
        let share = total > 0 ? Double(b.tokens) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(b.name)
                    .font(.app(13.5, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Text(k(b.tokens))
                    .font(HomeType.number(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("\(Int(share * 100))%")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.softFillDeep)
                    Capsule()
                        .fill(b.cached
                              ? app.settings.accentColor.opacity(0.65)
                              : Color.orange.opacity(0.75))
                        .frame(width: max(2, geo.size.width * share))
                }
            }
            .frame(height: 5)
            HStack(spacing: 5) {
                Circle()
                    .fill(b.cached ? app.settings.accentColor : Color.orange)
                    .frame(width: 6, height: 6)
                Text(b.cached ? "进缓存" : "每轮重算")
                    .font(.app(10, weight: .medium))
                    .foregroundStyle(b.cached ? Theme.textSoft(scheme) : .orange)
            }
            Text(MD.inline(b.note))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func cacheNote(_ s: PromptShape) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("缓存能省下多少")
                .font(.app(13.5, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text(MD.inline(
                "其中 **\(k(s.cachedTotal))** 是排在缓存断点前面的，"
                + "也就是 **\(pct(s.cachedTotal, s.total))** 的内容"
                + "仅**首次**按全价计费，其后每轮大幅降低。\n\n"
                + "⚠️ 前提是**上一次的缓存尚未过期**。Anthropic 默认保留 5 分钟，"
                + "间隔超过该时长后缓存失效，需重新建立。"
                + "所以现在标的是 **1 小时**那一档：她一天说几次话，中间隔着几十分钟，"
                + "5 分钟那档几乎每次都是冷的。"))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func tools(_ s: PromptShape) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最占地方的几件工具")
                .font(.app(13.5, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text("不需要的可在「设置 → MCP」中关闭。关闭后相应部分不再计入，"
                 + "但此部分位于缓存内，节省的是上下文占用，而非每轮费用。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
            ForEach(Array(s.fattestTools.enumerated()), id: \.offset) { _, t in
                HStack {
                    Text(t.name)
                        .font(.app(11.5, design: .monospaced))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(k(t.tokens))
                        .font(HomeType.number(11.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func k(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func pct(_ a: Int, _ b: Int) -> String {
        b > 0 ? "\(Int(Double(a) / Double(b) * 100))%" : "0%"
    }
}
