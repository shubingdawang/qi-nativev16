import SwiftUI

/// 收藏起来的那些句子，全部对话里挑出来的。
struct FavoritesView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var shareImage: ShareImage?

    private struct Item: Identifiable {
        let id = UUID()
        let conversationID: UUID
        let title: String
        let message: ChatMessage
    }

    private var items: [Item] {
        var out: [Item] = []
        for c in app.conversations {
            for m in c.messages where m.starred {
                out.append(Item(conversationID: c.id, title: c.title, message: m))
            }
        }
        return out.sorted { $0.message.createdAt > $1.message.createdAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if items.isEmpty {
                    EmptyNote(icon: Icon.star,
                              title: "还没有收藏",
                              hint: "在对话里挑中一句，底下点收藏就行")
                        .padding(.top, 50)
                }

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(item.message.role == .user
                                 ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                                 : (app.settings.aiName.isEmpty ? "他" : app.settings.aiName))
                                .font(.app(12, weight: .semibold))
                                .foregroundStyle(app.settings.accentColor)
                            Text(item.title)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .lineLimit(1)
                            Spacer()
                            Text(stamp(item.message.createdAt))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Text(item.message.content)
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .glassCard(padding: 0)
                    .padding(.horizontal, 14)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.message.content
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }
                        Button {
                            if let img = ShareCardRenderer.render(
                                messages: [item.message], settings: app.settings) {
                                shareImage = ShareImage(image: img)
                            }
                        } label: {
                            Label("做成图片", systemImage: Icon.share)
                        }
                        Button(role: .destructive) {
                            app.toggleStar([item.message.id], in: item.conversationID)
                        } label: {
                            Label("取消收藏", systemImage: "star.slash")
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image])
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
