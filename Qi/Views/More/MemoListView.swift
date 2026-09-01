import SwiftUI

/// 备忘。写记录、待办、想留住的话都在这儿。
struct MemoListView: View {

    @ObservedObject private var store = MemoStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var writing = false
    @State private var draft = Memo()
    @State private var editing: Memo?
    @State private var showHistory = false

    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {

                // 换个样子
                Picker("", selection: $store.style) {
                    ForEach(MemoStyle.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if store.onList.isEmpty {
                    EmptyNote(icon: "checklist",
                              title: "还没有记什么",
                              hint: "点击右上角新建。长按条目可置顶，置顶后会显示在聊天页。")
                        .padding(.top, 30)
                }

                ForEach(store.onList) { memo in
                    MemoRow(memo: memo, style: store.style,
                            onToggleDone: {
                                if memo.isDone {
                                    store.undoComplete(memo.id)
                                } else {
                                    store.complete(memo.id,
                                                   by: app.settings.userName.isEmpty
                                                       ? "饼饼" : app.settings.userName)
                                }
                            })
                        .onTapGesture { editing = memo }
                        .contextMenu {
                            if memo.isActive {
                                Button {
                                    store.togglePin(memo.id)
                                } label: {
                                    Label(memo.pinned ? "取消置顶" : "置顶到聊天页",
                                          systemImage: memo.pinned ? "pin.slash" : "pin")
                                }
                                Button {
                                    store.complete(memo.id, by: me)
                                } label: {
                                    Label("完成", systemImage: "checkmark")
                                }
                                Button(role: .destructive) {
                                    store.cancel(memo.id, by: me)
                                } label: {
                                    Label("取消这条", systemImage: "xmark")
                                }
                            } else {
                                Button {
                                    store.undoComplete(memo.id)
                                } label: {
                                    Label("点错了，挂回去", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("备忘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button {
                        draft = Memo(author: me)
                        writing = true
                    } label: {
                        Image(systemName: Icon.add)
                    }
                }
            }
        }
        .sheet(isPresented: $writing) {
            MemoEditor(memo: draft, isNew: true)
        }
        .sheet(item: $editing) { m in
            MemoEditor(memo: m, isNew: false)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { MemoHistoryView() }
        }
    }
}

// MARK: - 一条的样子

struct MemoRow: View {

    let memo: Memo
    var style: MemoStyle = .plain
    var compact: Bool = false

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    /// 点那个圈＝勾掉/取消勾掉
    var onToggleDone: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if style != .ticket {
                // 这个圈**就是打勾的地方**（她问的第 8 条）。
                // 以前点它跟点别处一样都是进编辑页——那它长成一个待办的样子
                // 就是骗人。现在点圈＝勾掉，点别处才是编辑。
                Button {
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    onToggleDone()
                } label: {
                    Image(systemName: memo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.app(16, weight: .regular))
                        .foregroundStyle(memo.isDone
                                         ? StatusTone.done.color
                                         : Theme.textMuted(scheme).opacity(0.5))
                        .padding(.top, 1)
                        // 圈本身才 16 点，四周留出富余，手指按偏一点也能中
                        .padding(.trailing, 6)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if memo.pinned {
                        Image(systemName: "pin.fill")
                            .font(.app(9))
                            .foregroundStyle(app.settings.preset.skin.remind
                                             ?? app.settings.accentColor)
                    }
                    if !memo.badge.isEmpty {
                        // 挂着的事是提醒（琥珀），做完了是好消息（鼠尾草）
                        StatusChip(tone: memo.isDone ? .done : .remind, text: memo.badge)
                    }
                    if memo.isDone && memo.badge.isEmpty {
                        StatusChip(tone: .done, text: "已完成")
                    }
                    Spacer(minLength: 0)
                }

                Text(memo.text)
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .strikethrough(memo.isDone, color: Theme.textMuted(scheme))
                    .opacity(memo.isDone ? 0.5 : 1)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(memo.author.isEmpty ? "" : memo.author + " 写的")
                    if memo.isDone {
                        Text("· \(memo.doneBy) 完成")
                    }
                    if !memo.notes.isEmpty {
                        Text("· \(memo.notes.count) 条批注")
                    }
                }
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(style == .tape ? 14 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .top) {
            // 胶带那一小条，贴在顶上
            if style == .tape {
                RoundedRectangle(cornerRadius: 2)
                    .fill(app.settings.accentColor.opacity(0.35))
                    .frame(width: 56, height: 15)
                    .rotationEffect(.degrees(-3))
                    .offset(y: -6)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain:
            GlassSurface(radius: 14, strength: app.settings.glassOpacity)
        case .note:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(app.settings.accentColor.opacity(scheme == .dark ? 0.14 : 0.13))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(app.settings.accentColor.opacity(0.55))
                        .frame(width: 3)
                }
        case .tape:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.6))
                .shadow(color: Theme.shadow(scheme), radius: 6, x: 0, y: 3)
        case .ticket:
            // 票根：左边一条虚线，像撕下来的
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55))
                .overlay(alignment: .leading) {
                    DashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.5))
                        .frame(width: 1)
                        .padding(.leading, 26)
                        .rotationEffect(.degrees(90))
                }
        }
    }
}

// MARK: - 写一条

struct MemoEditor: View {

    @State var memo: Memo
    let isNew: Bool

    @ObservedObject private var store = MemoStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var newNote = ""

    private let colors: [(String, String)] = [
        ("跟随", ""),
        ("炭", "2B2A27"),
        ("橘", "C96442"),
        ("琥珀", "E3A13A"),
        ("粉", "E8A0B4"),
        ("苔", "96B08F")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        field("要记什么") {
                            TextField("写点什么…", text: $memo.text, axis: .vertical)
                                .lineLimit(2...6)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("挂出来的那一小节")
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("十点前 / 很重要 / 别忘了", text: $memo.badge)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                            Text("置顶后以短标签形式显示在聊天页边缘，仅显示此处填写的文字。")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Toggle("置顶到聊天页", isOn: $memo.pinned)
                            .font(.app(14))

                        if memo.pinned {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("浮窗上的字色")
                                    .font(.app(13, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(colors, id: \.1) { name, hex in
                                            Button {
                                                memo.colorHex = hex
                                            } label: {
                                                Text(name)
                                                    .font(.app(12))
                                                    .foregroundStyle(hex.isEmpty
                                                        ? Theme.textSoft(scheme)
                                                        : (Color(hexString: hex) ?? .primary))
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 7)
                                                    .background(
                                                        Capsule().fill(memo.colorHex == hex
                                                            ? app.settings.accentColor.opacity(0.25)
                                                            : Theme.softFillDeep)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                Text("只管挂在外面那个浮窗。备忘页里的字跟着深浅色走，不受这个影响。")
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }

                        if !isNew {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("批注")
                                    .font(.app(13, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                                ForEach(memo.notes) { n in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.text)
                                            .font(.app(13))
                                            .foregroundStyle(Theme.textSoft(scheme))
                                        Text(n.author)
                                            .font(.app(10))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(Theme.softFillDeep))
                                }
                                HStack(spacing: 8) {
                                    TextField("补一句", text: $newNote)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.softFillDeep))
                                    Button("加上") {
                                        let me = app.settings.userName.isEmpty ? "我" : app.settings.userName
                                        store.annotate(memo.id, text: newNote, by: me)
                                        if let fresh = store.memo(memo.id) { memo = fresh }
                                        newNote = ""
                                    }
                                    .disabled(newNote.isEmpty)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "记一条" : "改一改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好了") {
                        if isNew {
                            store.add(memo.text, badge: memo.badge,
                                      author: memo.author, pinned: memo.pinned,
                                      colorHex: memo.colorHex)
                        } else {
                            store.update(memo)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(memo.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            content()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
        }
    }
}

// MARK: - 历史

struct MemoHistoryView: View {

    @ObservedObject private var store = MemoStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var annotating: Memo?
    @State private var noteText = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.history.isEmpty {
                    Text("这里还空着")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 60)
                }

                ForEach(store.history) { memo in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(memo.text)
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))
                            .strikethrough(memo.isDone)
                            .opacity(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(memo.isDone ? Color.green.opacity(0.7) : Color.orange.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text(status(memo))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        ForEach(memo.notes) { n in
                            Text("· \(n.text)　\(n.author)")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .padding(12)
                    .glassCard(padding: 0)
                    // ⚠ `contextMenu` 认的是真画出来的那几个像素，内容少的那几条底下是空的、长按收不到。
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            store.restore(memo.id)
                        } label: {
                            Label("挂回去", systemImage: "arrow.uturn.backward")
                        }
                        Button {
                            noteText = ""
                            annotating = memo
                        } label: {
                            Label("写批注", systemImage: "text.bubble")
                        }
                        Button(role: .destructive) {
                            store.remove(memo.id)
                        } label: {
                            Label("彻底删掉", systemImage: Icon.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .navigationTitle("历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关上") { dismiss() }
            }
        }
        .alert("写批注", isPresented: Binding(
            get: { annotating != nil }, set: { if !$0 { annotating = nil } }
        )) {
            TextField("说点什么", text: $noteText)
            Button("取消", role: .cancel) { annotating = nil }
            Button("加上") {
                if let m = annotating, !noteText.isEmpty {
                    let me = app.settings.userName.isEmpty ? "我" : app.settings.userName
                    store.annotate(m.id, text: noteText, by: me)
                }
                annotating = nil
            }
        }
    }

    private func status(_ memo: Memo) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        if let d = memo.doneAt {
            return "\(memo.doneBy) 完成 · \(f.string(from: d))"
        }
        if let c = memo.cancelledAt {
            return "\(memo.cancelledBy) 取消 · \(f.string(from: c))"
        }
        return ""
    }
}
