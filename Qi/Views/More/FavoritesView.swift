import SwiftUI

/// 收藏起来的那些句子，全部对话里挑出来的。
struct FavoritesView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var shareImage: ShareImage?
    @State private var tab = 0

    private struct Item: Identifiable {
        let id = UUID()
        let conversationID: UUID
        let title: String
        let message: ChatMessage
    }

    /// 她收的
    private var mine: [Item] {
        pick { $0.starred }
    }

    /// 他收的。
    ///
    /// 她定的：「在收藏页给他也加一个区域，
    /// 他也可以收藏我的句子。」——**收藏本来就该是双向的。**
    private var theirs: [Item] {
        pick { $0.keptByHim }
    }

    private func pick(_ keep: (ChatMessage) -> Bool) -> [Item] {
        var out: [Item] = []
        for c in app.conversations {
            for m in c.messages where keep(m) {
                out.append(Item(conversationID: c.id, title: c.title, message: m))
            }
        }
        return out.sorted { $0.message.createdAt > $1.message.createdAt }
    }

    private var items: [Item] { tab == 0 ? mine : theirs }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {

                // 两栏。**两边都空的时候也摆**——
                // 不摆的话她无从知道「他也能收」这件事。
                Picker("", selection: $tab) {
                    Text("我收的 \(mine.count)").tag(0)
                    Text("他收的 \(theirs.count)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

                if items.isEmpty {
                    EmptyNote(icon: Icon.star,
                              title: tab == 0 ? "还没有收藏" : "他还没收过",
                              hint: tab == 0
                                ? "在对话中选中一句，点击下方的收藏按钮即可加入"
                                : "他可以把你说过的某一句收下来，并写下缘由")
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

                        Text(MD.inline(item.message.content))
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        // 他为什么留着它。
                        // **这句比收本身要紧**——只摆一句她说过的话，
                        // 她看不出他为什么收，那就只是一份剪贴。
                        if !item.message.keptNote.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Capsule()
                                    .fill(app.settings.accentColor.opacity(0.45))
                                    .frame(width: 2)
                                Text(MD.inline(item.message.keptNote))
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
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
                        if tab == 0 {
                            Button(role: .destructive) {
                                app.toggleStar([item.message.id], in: item.conversationID)
                            } label: {
                                Label("取消收藏", systemImage: "star.slash")
                            }
                        } else {
                            // 他收的也能撤——**它在她手机里，就得她能拿掉**。
                            Button(role: .destructive) {
                                app.unkeep(item.message.id, in: item.conversationID)
                            } label: {
                                Label("从他收的里移除", systemImage: "star.slash")
                            }
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
