import SwiftUI

/// 聊天记录。一页里两种找法：打关键词，或者挑一个日子。
struct ChatSearchView: View {

    let space: ChatSpace
    /// 找到了以后跳过去
    var onJump: (UUID) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0            // 0 关键词，1 日期
    @State private var keyword = ""
    @State private var day = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                VStack(spacing: 0) {

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
        }
    }

    // MARK: 关键词输入

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: Icon.search)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted(scheme))
            TextField("说过的某个词", text: $keyword)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .submitLabel(.search)
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
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

    private var hits: [Hit] {
        let convs = app.conversations(in: space)
        var out: [Hit] = []

        if mode == 0 {
            let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.count >= 1 else { return [] }
            for c in convs {
                for m in c.messages where m.content.localizedCaseInsensitiveContains(key) {
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
        ScrollView {
            LazyVStack(spacing: 8) {
                let list = hits

                if list.isEmpty {
                    Text(emptyHint)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 40)
                } else {
                    HStack {
                        Text("找到 \(list.count) 条")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                    ForEach(list) { hit in
                        Button {
                            onJump(hit.conversationID)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(hit.message.role == .user
                                         ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                                         : (app.settings.aiName.isEmpty ? "他" : app.settings.aiName))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(app.settings.accentColor)
                                    Text(hit.conversationTitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(stamp(hit.message.createdAt))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                Text(snippet(hit.message.content))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textMain(scheme))
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassCard(padding: 0)
                        .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }

    private var emptyHint: String {
        if mode == 0 {
            return keyword.isEmpty ? "打几个字试试" : "这个词没说过"
        }
        return "这天没说过话"
    }

    /// 命中的词前后各留一点，别把整段都堆出来
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
