import SwiftUI

/// 手帐本。
///
/// 「做完的手帐按日期放进文件夹」——所以这一页是按月分的架子，
/// 一格一页，格子里是那一页的缩略图。点进去接着改。
struct JournalView: View {

    @ObservedObject private var store = JournalStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var opened: JournalPage?
    @State private var confirmDelete: JournalPage?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if store.pages.isEmpty {
                    empty
                }
                ForEach(store.byMonth, id: \.month) { group in
                    Text(group.month)
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.pages) { p in
                            cover(p)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .navigationTitle("手帐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    opened = store.newPage()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $opened) { p in
            JournalPageView(page: p)
        }
        .confirmationDialog("撕掉这一页？", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        ), titleVisibility: .visible) {
            Button("撕掉", role: .destructive) {
                if let p = confirmDelete { store.remove(p.id) }
                confirmDelete = nil
            }
            Button("算了", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("这一页上贴的照片也会一起没掉。")
        }
    }

    private var empty: some View {
        EmptyNote(icon: "book.closed",
                  title: "还没做过手帐",
                  hint: "右上角加一页。胶带、贴纸、邮票、夹子都在底下那排，"
                      + "收藏过的句子能直接贴上去。")
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// 一格。缩略图是**把那一页真的缩小画一遍**，
    /// 不是截图——所以永远跟里面一致，也不用管缓存失效。
    private func cover(_ p: JournalPage) -> some View {
        Button {
            opened = p
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    (Color(hexString: p.paperHex) ?? Color(hexString: "F3E9D8")!)
                    GeometryReader { geo in
                        ForEach(p.elements.sorted { $0.z < $1.z }) { e in
                            thumb(e)
                                .position(x: e.x * geo.size.width,
                                          y: e.y * geo.size.height)
                        }
                    }
                }
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 5, y: 3)

                Text(p.displayTitle)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    // 给他看的那几页标一下，一眼看得出哪些他能看见
                    if p.shared {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    Text(dayText(p.day))
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.toggleShared(p.id)
            } label: {
                Label(p.shared ? "不给他看了" : "给他看",
                      systemImage: p.shared ? "person.slash" : "person.2")
            }
            Button(role: .destructive) { confirmDelete = p } label: {
                Label("撕掉这一页", systemImage: Icon.trash)
            }
        }
    }

    /// 缩略图里的一样东西。只画个意思——一格才一百来点宽，
    /// 画细节没人看得见，画个色块和轮廓反而看得清这一页大概长什么样。
    @ViewBuilder
    private func thumb(_ e: JournalElement) -> some View {
        Group {
            switch e.kind {
            case .text, .quote:
                Text(e.text)
                    .font(.app(5))
                    .foregroundStyle(e.color)
                    .lineLimit(3)
                    .frame(maxWidth: 54)
            case .tape:
                Rectangle().fill(e.color.opacity(0.62))
                    .frame(width: 30, height: 7)
            case .sticker:
                Text(e.emoji).font(.app(11))
            case .stamp:
                Text(e.emoji.isEmpty ? "📮" : e.emoji)
                    .font(.app(8))
                    .frame(width: 15, height: 17)
                    .background(Color(hexString: "F6F2E8")!)
            case .clip:
                RoundedRectangle(cornerRadius: 1).fill(e.color)
                    .frame(width: 6, height: 9)
            case .note:
                Rectangle().fill(e.color).frame(width: 30, height: 25)
            case .photo:
                if let img = ImageStore.load(e.imageName) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 33, height: 33).clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .frame(width: 33, height: 33)
                }
            case .cutout:
                // 剪贴是透明底的 PNG，**不裁方块也不套框**——
                // 裁了透明的那圈就没了，看着就不是贴纸了
                if let img = ImageStore.load(e.imageName) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "scissors")
                        .font(.app(11))
                        .foregroundStyle(e.color)
                }
            case .frame:
                VStack(spacing: 0) {
                    if let img = ImageStore.load(e.imageName) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 30, height: 30).clipped()
                    } else {
                        Rectangle().fill(Color(hexString: "DDD8CE")!)
                            .frame(width: 30, height: 30)
                    }
                    Rectangle().fill(Color.white).frame(width: 30, height: 7)
                }
                .padding(2)
                .background(Color.white)
            }
        }
        .scaleEffect(e.scale)
        .rotationEffect(.degrees(e.angle))
    }

    private func dayText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}
