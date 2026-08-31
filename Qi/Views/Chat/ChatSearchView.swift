import SwiftUI

/// 聊天记录。一页里两种找法：打关键词，或者挑一个日子。
struct ChatSearchView: View {

    let space: ChatSpace
    /// 找到了以后跳过去：(哪一窗, 哪一条)
    var onJump: (UUID, UUID) -> Void

    /// 上次搜到哪儿了。**静态量**——这一页是 sheet，关掉就整个销毁，
    /// 状态放在 @State 里下次进来一定是空的。
    /// 她要的是「点进去看完退出来，还在刚刚那个位置」。
    nonisolated(unsafe) static var lastMode = 0
    nonisolated(unsafe) static var lastKeyword = ""
    nonisolated(unsafe) static var lastPicked: UUID?

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0            // 0 关键词，1 日期
    @State private var keyword = ""
    @State private var day = Date()
    /// 挑了哪一类。`nil` = 不按类型筛（只按词或日子）。
    @State private var kind: Kind?
    /// 上次点过的那条，重新进来时滚回去
    @State private var restoreTo: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                VStack(spacing: 0) {

                    // ⚠️ 「类型」**不单开一栏**。她定的：
                    // 「聊天记录的类型应该放在关键词页，不是单独开一个区域。」
                    // 对——找语音和打个词找，本来就是同一件事的两种入口，
                    // 分成两栏等于逼她先想「我这次算哪一类」。
                    Picker("", selection: $mode) {
                        Text("关键词").tag(0)
                        Text("日期").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                    if mode == 0 {
                        searchField
                        kindPicker
                    } else {
                        DatePicker("", selection: $day, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 6)
                            .glassCard(padding: 6)
                            .padding(.horizontal, 14)
                    }

                    resultList
                }
            }
            .navigationTitle("聊天记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
            .onAppear {
                // 把上次的搜索条件摆回去（她要的「点进去看完退出来，
                // 还在刚刚那个位置」）
                if keyword.isEmpty, restoreTo == nil {
                    mode = Self.lastMode
                    keyword = Self.lastKeyword
                    restoreTo = Self.lastPicked
                }
            }
        }
    }

    // MARK: 关键词输入

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: Icon.search)
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))
            TextField("说过的某个词", text: $keyword)
                .textFieldStyle(.plain)
                .font(.app(15))
                .submitLabel(.search)
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Theme.softFillDeep))
        .overlay(Capsule().strokeBorder(Theme.softStroke, lineWidth: 0.8))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: 结果

    private struct Hit: Identifiable {
        let id = UUID()
        let conversationID: UUID
        let conversationTitle: String
        let message: ChatMessage
    }

    /// 「类型」那一档挑的是哪一类
    enum Kind: String, CaseIterable {
        case voice = "语音"
        case link = "链接"
        case image = "图片"
        case file = "文件"

        var icon: String {
            switch self {
            case .voice: return "waveform"
            case .link:  return "link"
            case .image: return "photo"
            case .file:  return "doc"
            }
        }
    }

    /// 这一条算不算这一类。
    ///
    /// ⚠️ 链接**不看有没有卡片**。她定的：
    /// 「小红书／b站／抖音链接，没有卡片框的也属于链接。」
    /// 卡片是我们认出来才画的，认不出来的照样是一条链接——
    /// 按「有没有卡片」来分，等于把认漏的那些又漏一次。
    static func matches(_ m: ChatMessage, _ k: Kind) -> Bool {
        switch k {
        case .voice: return !m.voiceName.isEmpty
        case .image: return !m.imageNames.isEmpty
        case .file:  return !m.files.isEmpty
        case .link:
            let t = m.content
            return t.contains("http://") || t.contains("https://")
                || t.contains("xhslink.com") || t.contains("b23.tv")
                || t.contains("v.douyin.com")
        }
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Kind.allCases, id: \.self) { k in
                    let on = kind == k
                    Button {
                        // 再点一下取消——不给「全部」那一档，
                        // 多一个按钮不如少一次思考。
                        withAnimation(.easeOut(duration: 0.14)) { kind = on ? nil : k }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: k.icon).font(.app(11))
                            Text(k.rawValue).font(.app(12.5, weight: on ? .semibold : .regular))
                        }
                        .foregroundStyle(on ? .white : Theme.textSoft(scheme))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(on ? app.settings.accentColor.opacity(0.85)
                                                   : Theme.softFillDeep))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var hits: [Hit] {
        let convs = app.conversations(in: space)
        var out: [Hit] = []

        if mode == 0 {
            // 关键词和类型是**与**的关系：
            // 只挑了类型就翻出那一类的全部；打了词又挑了类型，
            // 就是「在这一类里找这个词」。两个都空才什么都不给。
            let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty || kind != nil else { return [] }
            for c in convs {
                for m in c.messages {
                    if let k = kind, !Self.matches(m, k) { continue }
                    if !key.isEmpty,
                       !m.content.localizedCaseInsensitiveContains(key) { continue }
                    out.append(Hit(conversationID: c.id, conversationTitle: c.title, message: m))
                }
            }
        } else {
            let cal = Calendar.current
            for c in convs {
                for m in c.messages where cal.isDate(m.createdAt, inSameDayAs: day) {
                    out.append(Hit(conversationID: c.id, conversationTitle: c.title, message: m))
                }
            }
        }
        return out.sorted { $0.message.createdAt > $1.message.createdAt }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 8) {
                let list = hits

                if list.isEmpty {
                    Text(emptyHint)
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 40)
                } else {
                    HStack {
                        Text("找到 \(list.count) 条")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                    ForEach(list) { hit in
                        Button {
                            // 记住这次搜的是什么、点的是哪条，下次进来照原样摆回去
                            Self.lastMode = mode
                            Self.lastKeyword = keyword
                            Self.lastPicked = hit.message.id
                            onJump(hit.conversationID, hit.message.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(hit.message.role == .user
                                         ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                                         : (app.settings.aiName.isEmpty ? "他" : app.settings.aiName))
                                        .font(.app(12, weight: .semibold))
                                        .foregroundStyle(app.settings.accentColor)
                                    Text(hit.conversationTitle)
                                        .font(.app(11))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(stamp(hit.message.createdAt))
                                        .font(.app(10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                // ⚠️ 语音、图片、文件那几条 `content` 常常是空的。
                                // 只画 `content` 的话，「找语音」找出来一整屏
                                // 全是空条目——看着像没找到。
                                Text(snippet(hit.message.content).isEmpty
                                     ? tagLine(hit.message)
                                     : snippet(hit.message.content))
                                    .font(.app(13))
                                    .foregroundStyle(snippet(hit.message.content).isEmpty
                                                     ? Theme.textMuted(scheme)
                                                     : Theme.textMain(scheme))
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassCard(padding: 0)
                        .padding(.horizontal, 14)
                        .id(hit.message.id)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        // 重新进来的时候，滚回上次点的那一条。
        // 延一点点再滚——列表是 Lazy 的，刚出现那一帧还没排好版。
        .onAppear {
            guard let target = restoreTo else { return }
            restoreTo = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        }
    }

    private var emptyHint: String {
        if mode == 0 {
            if keyword.isEmpty && kind == nil { return "打几个字，或者挑一类" }
            if keyword.isEmpty { return "这一类里还什么都没有" }
            return "这个词没说过"
        }
        return "这天没说过话"
    }

    /// 命中的词前后各留一点，别把整段都堆出来
    /// 没有正文的那些条，摆一句「这是什么」。
    private func tagLine(_ m: ChatMessage) -> String {
        if !m.voiceName.isEmpty {
            return "语音 \(Int(VoiceStore.duration(m.voiceName)))″"
        }
        if !m.imageNames.isEmpty { return "\(m.imageNames.count) 张图" }
        if !m.files.isEmpty { return "文件" }
        return "（没有正文）"
    }

    private func snippet(_ text: String) -> String {
        guard mode == 0,
              let range = text.range(of: keyword, options: .caseInsensitive)
        else { return text }
        let start = text.index(range.lowerBound,
                               offsetBy: -30,
                               limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound,
                             offsetBy: 60,
                             limitedBy: text.endIndex) ?? text.endIndex
        var s = String(text[start..<end])
        if start != text.startIndex { s = "…" + s }
        if end != text.endIndex { s += "…" }
        return s
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = mode == 0 ? "M月d日 HH:mm" : "HH:mm"
        return f.string(from: d)
    }
}
