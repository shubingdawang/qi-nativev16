import SwiftUI
import PhotosUI

/// 「小事」那一页。
///
/// 他派的那几件在这儿，她做完了在这儿打卡；攒的分能换她跟他说好的东西。
///
/// **不催。** 这一页不会有红点、不会有「你今天还没做」的横幅——
/// 催她做事的东西很快就会被关掉。挂着的就摆在那儿，做了就打个卡。
struct QuestView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = QuestStore.shared

    @State private var checkingIn: Quest?
    /// 刚到账多少币。⚠️ 只是**报一声**，币在 `QuestStore.checkIn` 里就发了，
    /// 这儿不发第二遍。
    @State private var justGot: Int?
    @State private var proofText = ""
    @State private var proofImage = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var newReward = ""
    @State private var newCost = 5
    @State private var addingReward = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                scoreCard

                if store.openToday.isEmpty && store.quests.isEmpty {
                    empty
                } else {
                    if !store.openToday.isEmpty {
                        section("还挂着") {
                            ForEach(store.openToday) { q in questCard(q, open: true) }
                        }
                    }
                    let done = store.quests
                        .filter { !$0.doneDays.isEmpty }
                        .sorted { ($0.doneDays.last ?? "") > ($1.doneDays.last ?? "") }
                    if !done.isEmpty {
                        section("做过的") {
                            ForEach(done.prefix(20)) { q in questCard(q, open: false) }
                        }
                    }
                }

                rewardCard
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("小事")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) { gotCoins }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(item: $checkingIn) { q in checkInSheet(q) }
        .alert("加一个能换的", isPresented: $addingReward) {
            TextField("换什么", text: $newReward)
            Button("算了", role: .cancel) { newReward = "" }
            Button("加上") {
                store.addReward(title: newReward, cost: newCost, by: "her")
                newReward = ""
            }
        } message: {
            Text("要多少分在下面那个滑块上调，现在是 \(newCost) 分。")
        }
    }

    // MARK: 上面那张

    private var scoreCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.points)")
                    .font(.app(26, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("分")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if store.streak > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.streak)")
                        .font(.app(26, weight: .semibold, design: .serif))
                        .foregroundStyle(app.settings.accentColor)
                    Text("天没断")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("他还没派过事")
                .font(.app(14, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text(MD.inline("此页记录由模型指派的小任务，区别于备忘（自行记录）、"
                 + "承诺（他欠你的）都不是一回事。\n"
                 + "他会在说话的时候顺手派一件，小、具体、今天做得完那种。"
                 + "你做完了在这儿打个卡，他下次说话就知道了。"))
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func section(_ title: String,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            content()
        }
    }

    // MARK: 一件

    private func questCard(_ q: Quest, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(q.kindLabel)
                    .font(.app(9.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.softFillDeep))
                Text("\(q.points) 分")
                    .font(.app(9.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                // 他给这件事挂了金币的话，**做之前就得看得见**——
                // 做完才知道有奖励，那奖励就没起到它该起的作用。
                if q.coins > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(HomePalette.amber).frame(width: 6, height: 6)
                        Text("\(q.coins)")
                            .font(.app(9.5, weight: .medium))
                    }
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(HomePalette.amber.opacity(0.16)))
                }
                Spacer(minLength: 0)
                if !open, let last = q.doneDays.last {
                    Text(last)
                        .font(.app(9.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }

            Text(q.title)
                .font(.app(15, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .fixedSize(horizontal: false, vertical: true)

            if !q.detail.isEmpty {
                Text(q.detail)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !q.proofText.isEmpty {
                Text("你交的：" + q.proofText)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            if !q.proofImage.isEmpty, let img = ImageStore.cached(q.proofImage) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !q.hisNote.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Text("他说：")
                        .font(.app(11, weight: .medium))
                        .foregroundStyle(app.settings.accentColor)
                    Text(q.hisNote)
                        .font(.app(11.5))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !q.doneDays.isEmpty && !q.seen {
                Text("他还没看到")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            HStack(spacing: 14) {
                if open {
                    Button {
                        proofText = ""
                        proofImage = ""
                        checkingIn = q
                    } label: {
                        Text("做完了")
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(app.settings.primaryColor))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.drop(q.id)
                    } label: {
                        Text("这件不做")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                } else if q.isDaily {
                    Text("每天都能再做一次")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
                Button {
                    store.remove(q.id)
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

    // MARK: 打卡

    private func checkInSheet(_ q: Quest) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(q.title)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))

                TextField("想说点什么（可以不写）", text: $proofText, axis: .vertical)
                    .font(.app(14))
                    .lineLimit(1...5)
                    .padding(12)
                    .glassBackground(radius: 12,
                                     strength: app.settings.glassOpacity * 0.9)

                if !proofImage.isEmpty, let img = ImageStore.cached(proofImage) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button { pickingPhoto = true } label: {
                    Label(proofImage.isEmpty ? "拍一张给他看" : "换一张",
                          systemImage: "photo")
                        .font(.app(13))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Text(MD.inline("提交后，模型在下一次对话中即可读取完成状态。"
                     + "**不会自动跳出一句夸你的话**，那种一眼就看得出是流水线。"))
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))

                Spacer()
            }
            .padding(16)
            .navigationTitle("打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { checkingIn = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("交了") {
                        let ok = store.checkIn(q.id, text: proofText,
                                               image: proofImage)
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        // 币是 `checkIn` 里发的（见 QuestStore）。这儿只报一声——
                        // ⚠️ **到账要当场看得见**，不然她得自己切去小屋对数。
                        if ok, q.coins > 0 { justGot = q.coins }
                        checkingIn = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 「+N 币」浮一下就走。
    @ViewBuilder
    private var gotCoins: some View {
        if let n = justGot {
            HStack(spacing: 5) {
                Circle().fill(HomePalette.amber).frame(width: 8, height: 8)
                Text("+\(n)")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.softFillDeep))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: n) {
                // ⚠️ 绑在 `id: n` 上。挂在 onAppear 上的话，
                // 连着交两件，第二件不会重新计时，第一件的计时到点就把它抹了。
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeOut(duration: 0.25)) { justGot = nil }
            }
        }
    }

    // MARK: 换

    private var rewardCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("能换的")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
                Button { addingReward = true } label: {
                    Image(systemName: "plus")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }

            if store.rewards.isEmpty {
                Text("暂无，可添加自定义条目。"
                     + "「换他讲一个睡前故事」「换一次通话」那种。他也能加。")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            ForEach(store.rewards) { r in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title)
                            .font(.app(13))
                            .foregroundStyle(Theme.textMain(scheme))
                        if r.takenCount > 0 {
                            Text("换过 \(r.takenCount) 次")
                                .font(.app(9.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        guard store.redeem(r.id) != nil else { return }
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    } label: {
                        Text("\(r.cost) 分")
                            .font(.app(12))
                            .foregroundStyle(store.points >= r.cost
                                             ? .white : Theme.textMuted(scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(store.points >= r.cost
                                               ? app.settings.primaryColor
                                               : Theme.softFillDeep)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.points < r.cost)

                    Button { store.removeReward(r.id) } label: {
                        Image(systemName: "xmark")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if addingReward || !store.rewards.isEmpty {
                HStack(spacing: 8) {
                    Text("新的要几分")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Slider(value: Binding(
                        get: { Double(newCost) },
                        set: { newCost = Int($0) }
                    ), in: 1...50, step: 1)
                    Text("\(newCost)")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image) else { return }
            await MainActor.run {
                if !proofImage.isEmpty { ImageStore.delete(proofImage) }
                proofImage = name
                photoItem = nil
            }
        }
    }
}
