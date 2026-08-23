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

                            Text("小屋的记忆库是全公用的。他每聊三五轮会自动 checkpoint 记一笔进度，下次醒来又会一并读回来——那些内容不分窗口。所以真想让这个窗口独门独户，得把这个也关掉：关了之后他在这儿不存也不查，只靠眼前这段对话。")
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

                        Text("并上之后，他在这几个窗口里都记得同一批事；拆开就各自只记得自己那份。这样不想混在一起的话题可以彻底分开。")
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
