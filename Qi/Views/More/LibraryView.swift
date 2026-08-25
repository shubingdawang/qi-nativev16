import SwiftUI

// MARK: - 划下那句话的详情
//
// ⚠️ 这个文件原来还装着 `LibraryView`（老的那份平铺书单）和 `ReaderView`。
// 书房 v107 重做之后：
//   · 书单 → `BookshelfView.swift`（书架 / 书脊 / 封面墙 / 批注页）
//   · 阅读页 → `ReaderView.swift`（按句选、马克笔、翻页方式、点屏召唤设置）
// 这儿只剩下这一张「点开某一句看详情」的卡片，两边都在用它。

struct AnnotationSheet: View {

    @State var annotation: Annotation

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var jumpFailed = false

    /// 跳回当时聊的那一轮。
    /// **跳不成要说实话**——那条记录可能已经被她清掉了。
    private func jump() {
        guard let turn = fresh.talkIDs.last else { return }
        if app.jumpToTurn(turn) {
            dismiss()
        } else {
            jumpFailed = true
        }
    }

    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var fresh: Annotation { store.annotation(annotation.id) ?? annotation }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // 划下的那句
                            HStack(alignment: .top, spacing: 9) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(app.settings.accentColor.opacity(0.6))
                                    .frame(width: 3)
                                Text(fresh.quote)
                                    .font(.app(14))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .lineSpacing(5)
                            }
                            .padding(.bottom, 4)

                            ForEach(fresh.notes) { note in
                                noteRow(note)
                            }

                            if fresh.notes.isEmpty {
                                Text("尚无批注。记录这句话打动你的原因。")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }

                            // 跟他围绕这句聊过的话，在聊天记录里。
                            // 上面那些是**留在这句底下**的往来；
                            // 这个按钮是回到**当时那一轮对话**里去看。
                            if !fresh.talkIDs.isEmpty {
                                Divider().opacity(0.4).padding(.vertical, 4)
                                Button {
                                    jump()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bubble.left.and.text.bubble.right")
                                            .font(.app(12))
                                        Text("看当时聊了什么")
                                            .font(.app(13))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.app(10))
                                    }
                                    .foregroundStyle(app.settings.accentColor)
                                }
                                .buttonStyle(.plain)
                                if jumpFailed {
                                    Text("那一轮的记录找不着了（可能被清过）。")
                                        .font(.app(11))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(18)
                    }

                    HStack(spacing: 8) {
                        TextField("再说一句…", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .glassBackground(radius: 20, strength: app.settings.glassOpacity)

                        Button {
                            store.reply(to: fresh.id, text: draft, by: me)
                            draft = ""
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(app.settings.accentColor.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("这一句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: Icon.close)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.removeAnnotation(fresh.id)
                        dismiss()
                    } label: {
                        Text("取消划线").foregroundStyle(.red)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func noteRow(_ note: AnnotationNote) -> some View {
        let mine = note.author == me
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(note.text)
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .glassBackground(radius: 15, strength: app.settings.glassOpacity,
                                     extra: mine ? 0.3 : 0)
                Text(stamp(note))
                    .font(.app(9))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func stamp(_ note: AnnotationNote) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return note.author + " · " + f.string(from: note.createdAt)
    }
}
