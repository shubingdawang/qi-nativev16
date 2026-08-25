import SwiftUI

/// 挑几个窗口把记忆并到一起。
/// 并上之后，这几个窗口里的他彼此知道对方聊过什么；
/// 拆开就各自回到只记得自己那份的状态，互不干扰。
struct MemoryLinkView: View {

    let space: ChatSpace
    let conversationID: UUID

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var others: [Conversation] {
        app.conversations(in: space).filter { $0.id != conversationID }
    }

    private var current: Conversation? { app.conversation(conversationID) }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        VStack(alignment: .leading, spacing: 7) {
                            Text("当前窗口")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Text(current?.title ?? "")
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(summary)
                                .font(.app(12))
                                .foregroundStyle(Theme.textSoft(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()

                        // 断不断小屋那边的记忆工具
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { current?.useMemoryTools ?? true },
                                set: { newValue in
                                    if let i = app.index(of: conversationID) {
                                        app.conversations[i].useMemoryTools = newValue
                                    }
                                }
                            )) {
                                Text("允许动小屋的记忆")
                                    .font(.app(14, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                            }

                            Text("记忆库为全局共用：每隔数轮对话自动记录一次进度，下次唤醒时一并读取，内容不区分窗口。若需本窗口完全独立，需同时关闭此项——关闭后本窗口不写入也不检索记忆库，仅依据当前对话。")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .glassCard()

                        if others.isEmpty {
                            EmptyNote(icon: "square.on.square",
                                      title: "还没有别的窗口可以并")
                        }

                        ForEach(others) { conv in
                            let linked = app.isMemoryLinked(conv.id, with: conversationID)
                            Button {
                                if linked {
                                    app.unlinkMemory(conv.id)
                                } else {
                                    app.linkMemory(conv.id, with: conversationID)
                                }
                                if app.settings.haptics {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: linked ? "link" : "link.badge.plus")
                                        .font(.app(15))
                                        .foregroundStyle(linked
                                                         ? app.settings.accentColor
                                                         : Theme.textMuted(scheme))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.title)
                                            .font(.app(14, weight: linked ? .semibold : .regular))
                                            .foregroundStyle(Theme.textMain(scheme))
                                            .lineLimit(1)
                                        Text(conv.preview)
                                            .font(.app(11))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)

                                    Text(linked ? "已并" : "并上")
                                        .font(.app(11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(linked
                                                ? app.settings.accentColor.opacity(0.28)
                                                : Theme.softFillDeep)
                                        )
                                        .foregroundStyle(Theme.textSoft(scheme))
                                }
                                .padding(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glassCard(padding: 0)
                        }

                        Text("合并后，所选窗口共享同一份记忆；拆分后各窗口仅保留自身的记录，可用于隔离不同话题。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 4)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("记忆合并")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if current?.memoryGroupID != nil {
                        Button("全部解除") {
                            for peer in app.memoryPeers(of: conversationID) {
                                app.unlinkMemory(peer.id)
                            }
                            app.unlinkMemory(conversationID)
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        let peers = app.memoryPeers(of: conversationID)
        if peers.isEmpty { return "现在只记得这个窗口里聊过的" }
        return "已经和 \(peers.count) 个窗口并在一起：" + peers.map { $0.title }.joined(separator: "、")
    }
}
