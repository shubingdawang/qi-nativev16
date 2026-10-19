import SwiftUI
import PhotosUI

// MARK: - 交给他做这一天

/// 挑几张照片、点一个感觉、说一句（不说也行），交给他拼一页。
/// 照片在缩小之前先从原图读拍摄时间、地点、光圈快门，一起交过去。
struct JournalHandOffSheet: View {
    let startDay: Date
    let accent: Color
    /// 交出去：哪天、照片原图、感觉、那一句
    let onSend: (Date, [Data], [String], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var day: Date
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var datas: [Data] = []
    @State private var thumbs: [UIImage] = []
    @State private var moods: Set<String> = []
    @State private var note = ""
    @State private var loading = false

    static let maxPhotos = 9

    init(startDay: Date, accent: Color, onSend: @escaping (Date, [Data], [String], String) -> Void) {
        self.startDay = startDay
        self.accent = accent
        self.onSend = onSend
        _day = State(initialValue: startDay)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker(selection: $day, in: ...Date(), displayedComponents: .date) {
                            Text("做哪一天").font(.app(14)).foregroundStyle(Theme.textMain(scheme))
                        }
                        .tint(accent)
                        .glassCard()

                        photoCard
                        moodCard

                        VStack(alignment: .leading, spacing: 8) {
                            Text("再说一句（不说也行）").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                            TextField("比如：那天风很大", text: $note, axis: .vertical)
                                .lineLimit(1...4)
                                .font(.app(14))
                        }
                        .glassCard()

                        Text("照片里读得到的拍摄时间、地点、光圈快门会一起交给他；截图和聊天软件存下来的图一般读不到。不挑照片的话，他用那天你在聊天里发的照片。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("交给他")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("交给他") {
                        let order = JournalPhotoInfo.moods.filter { moods.contains($0) }
                        onSend(day, datas, order, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(accent)
                    .disabled(loading)
                }
            }
        }
        .background(PhotoPickHost(open: $picking, picked: $picked,
                                  maxCount: max(1, Self.maxPhotos - datas.count), keepOriginal: true))
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            loading = true
            Task { @MainActor in
                for it in items where datas.count < Self.maxPhotos {
                    // 拿原图的 Data：缩小、重存会把拍摄信息丢掉
                    guard let d = try? await it.loadTransferable(type: Data.self),
                          let img = UIImage(data: d) else { continue }
                    datas.append(d)
                    thumbs.append(ImageStore.downscale(img, maxSide: 300))
                }
                picked = []
                loading = false
            }
        }
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("照片 \(datas.count)/\(Self.maxPhotos)").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(thumbs.indices, id: \.self) { i in
                    Image(uiImage: thumbs[i])
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                datas.remove(at: i)
                                thumbs.remove(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.white, Color.black.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                        }
                }
                if datas.count < Self.maxPhotos {
                    Button { picking = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(accent)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想要什么感觉").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
            FlowChips(items: JournalPhotoInfo.moods, picked: moods, accent: accent) { m in
                if moods.contains(m) { moods.remove(m) } else { moods.insert(m) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// 一排能换行的小胶囊
private struct FlowChips: View {
    let items: [String]
    let picked: Set<String>
    let accent: Color
    let tap: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { m in
                let on = picked.contains(m)
                Button { tap(m) } label: {
                    Text(m)
                        .font(.app(12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .white : Theme.textSoft(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? accent.opacity(0.85) : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 最近撕掉的

struct JournalTrashSheet: View {
    @ObservedObject private var store = JournalStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var confirm: JournalTrashed?

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if store.trash.isEmpty {
                            Text("没有撕掉的页")
                                .font(.app(13))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 60)
                        }
                        ForEach(store.trash) { t in
                            HStack(spacing: 12) {
                                JournalThumb(page: t.page, height: 76)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.page.dayKey + " · " + t.page.displayTitle)
                                        .font(.app(13.5))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .lineLimit(1)
                                    Text("还留 \(t.daysLeft) 天")
                                        .font(.app(11))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                Spacer(minLength: 0)
                                Button("放回去") { store.restore(t.id) }
                                    .font(.app(12.5, weight: .medium))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.textSoft(scheme))
                            }
                            .padding(12)
                            .glassCard(padding: 0)
                            .contextMenu {
                                Button(role: .destructive) { confirm = t } label: {
                                    Label("彻底撕掉", systemImage: Icon.trash)
                                }
                            }
                        }
                        if !store.trash.isEmpty {
                            Text("撕掉的页留 30 天，过了连照片一起删。长按一页可以马上彻底撕掉。")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 6)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("最近撕掉的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .confirmationDialog("彻底撕掉这一页？", isPresented: Binding(
                get: { confirm != nil }, set: { if !$0 { confirm = nil } }
            ), titleVisibility: .visible) {
                Button("彻底撕掉", role: .destructive) {
                    if let t = confirm { store.purge(t.id) }
                    confirm = nil
                }
                Button("取消", role: .cancel) { confirm = nil }
            } message: {
                Text("连同上面的照片一起删掉，找不回来。")
            }
        }
    }
}
