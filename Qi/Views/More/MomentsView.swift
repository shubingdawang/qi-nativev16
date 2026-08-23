import SwiftUI
import PhotosUI

/// 动态那一页。
///
/// 他发的那些留在这儿等她翻到；她也能发一条，他下次说话就知道。
///
/// **她在这儿写的每一句都会变成对话里她说的一句话**——
/// 不另起一个后台请求去「让他回复评论」，那违反那条铁律
/// （除了她跟他说话和他调工具，任何会额外调模型的地方都必须是她主动点的）。
/// 她按下「回一句」就是她主动点的那一下。
struct MomentsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MomentStore.shared

    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: String = ""
    @State private var replyTo: Moment?
    @State private var replyText = ""
    @State private var pickingPhoto = false

    private var her: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                composer
                if store.feed.isEmpty {
                    empty
                } else {
                    ForEach(store.feed) { m in
                        card(m)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(item: $replyTo) { m in replySheet(m) }
    }

    // MARK: 空的时候

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这儿还什么都没有")
                .font(.app(14, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text("他说话的时候顺手就能往这儿放一条——听到一句歌词、窗外在下雨、"
                 + "刚画完一张。你不在的那几个小时，他留下的东西会在这儿等你。"
                 + "\n你也可以先发一条，他下次说话就知道了。")
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 她发一条

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("这会儿在想什么", text: $draft, axis: .vertical)
                .font(.app(14))
                .lineLimit(1...5)
                .foregroundStyle(Theme.textMain(scheme))

            if !pickedImage.isEmpty, let img = ImageStore.load(pickedImage) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            ImageStore.delete(pickedImage)
                            pickedImage = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.app(16))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
            }

            HStack(spacing: 10) {
                Button { pickingPhoto = true } label: {
                    Image(systemName: "photo")
                        .font(.app(15))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    postMine()
                } label: {
                    Text("发出去")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(app.settings.primaryColor))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty
                          && pickedImage.isEmpty)
            }

            Text("发在这儿**不会打扰他**——他下次说话的时候才会知道有这么一条。"
                 + "急事直接去对话里说。")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 一条

    private func card(_ m: Moment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(m.isHers ? her : him)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(m.isHers
                                     ? Theme.textMain(scheme)
                                     : app.settings.accentColor)
                Text(stamp(m.at))
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
                if m.isHers && !m.seen {
                    Text("他还没看到")
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }

            if !m.text.isEmpty {
                Text(m.text)
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !m.attach.isEmpty {
                Text("♫ " + m.attach)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            if !m.imageName.isEmpty, let img = ImageStore.load(m.imageName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // 评论
            ForEach(m.comments) { c in
                HStack(alignment: .top, spacing: 5) {
                    Text((c.who == "her" ? her : him) + "：")
                        .font(.app(11, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(c.text)
                        .font(.app(11))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 16) {
                Button {
                    store.like(m.id, by: "her")
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.likedByHer ? "heart.fill" : "heart")
                        Text(m.likedByHer ? "赞过了" : "赞一下")
                    }
                    .font(.app(11))
                    .foregroundStyle(m.likedByHer
                                     ? (Color(hexString: "E8879B") ?? .pink)
                                     : Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    replyText = ""
                    replyTo = m
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text("回一句")
                    }
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if m.likedByHim {
                    Text("❤️ 他赞过")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Button {
                    store.remove(m.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 回一句

    private func replySheet(_ m: Moment) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(m.isHers ? "你自己那条" : (him + "：" + m.text))
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(3)

                TextField("回他一句", text: $replyText, axis: .vertical)
                    .font(.app(15))
                    .lineLimit(1...6)
                    .padding(12)
                    .glassBackground(radius: 12,
                                     strength: app.settings.glassOpacity * 0.9)

                Text("这一句会**同时发进对话里**——他下一轮就看得见，"
                     + "跟你在聊天里说话是同一回事。所以点这一下等于跟他说话。")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))

                Spacer()
            }
            .padding(16)
            .navigationTitle("回一句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { replyTo = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("发") { sendReply(m) }
                        .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: 手脚

    private func postMine() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !pickedImage.isEmpty else { return }
        store.post(who: "her", text: t, imageName: pickedImage)
        draft = ""
        pickedImage = ""
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func sendReply(_ m: Moment) {
        let t = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.comment(m.id, who: "her", text: t)
        // 同一句话进对话。**这是她主动点的那一下**——
        // 不在后台替她开一次请求，规矩就守在这儿。
        if let cid = app.activeID(for: .chat) {
            let quoted = m.isHers ? "" : "（在你那条动态「\(m.text.prefix(18))」下面）"
            app.send(text: quoted + t, images: [], in: cid)
        }
        replyTo = nil
        replyText = ""
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image) else { return }
            await MainActor.run {
                if !pickedImage.isEmpty { ImageStore.delete(pickedImage) }
                pickedImage = name
                photoItem = nil
            }
        }
    }

    private func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(d) { f.dateFormat = "今天 HH:mm" }
        else if cal.isDateInYesterday(d) { f.dateFormat = "昨天 HH:mm" }
        else { f.dateFormat = "M月d日 HH:mm" }
        return f.string(from: d)
    }
}
