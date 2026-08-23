import SwiftUI

/// 戳一戳那一页。两排可选项加一个按钮，没什么可讲的——
/// 要紧的是那份文档里点名的两件事：
///
/// · **先上屏，再发请求。** 点下去立刻关掉这一页，让她看着那句话落进聊天里。
/// · **他忙的时候要说人话。** 正在回上一句就把按钮按灭，
///   老老实实写「他这会儿在忙，这一下先欠着」——
///   千万别假装成功，戳了没反应比不能戳伤人得多。
struct PokeSheet: View {

    let conversationID: UUID

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// 上次挑的那一对留着。她多半会连着戳好几下，
    /// 每次都要重挑一遍的话，这个功能玩两次就懒得开了。
    @AppStorage("pokeAction") private var actionKey = "poke"
    @AppStorage("pokePart") private var partKey = "ear"

    private var action: Poke.Action { Poke.action(actionKey) }
    private var part: Poke.Part { Poke.part(partKey) }
    private var busy: Bool { app.runningConversationIDs.contains(conversationID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    group("做什么") {
                        chips(Poke.actions.map { Chip(id: $0.key, label: $0.label) },
                              selected: actionKey) { actionKey = $0 }
                    }

                    group("落在哪") {
                        chips(Poke.parts.map { Chip(id: $0.key, label: $0.label) },
                              selected: partKey) { partKey = $0 }
                    }

                    // 按之前就看得见这一下是什么。旁白写的是发生了什么事，
                    // 不写他该有什么反应——那句话由他自己接。
                    Text(Poke.narration(action, part))
                        .font(.app(14))
                        .italic()
                        .foregroundStyle(Theme.textMain(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .glassBackground(radius: 14,
                                         strength: app.settings.glassOpacity * 0.9)

                    Button {
                        guard app.poke(action, at: part, in: conversationID) else { return }
                        dismiss()
                    } label: {
                        Text(busy ? "他这会儿在忙" : "戳")
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(busy
                                          ? Theme.textMuted(scheme).opacity(0.4)
                                          : app.settings.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    Text(busy
                         ? "他正在回上一句。这一下先欠着——等他说完再戳。"
                         : "这一下会先动他的身体，他的话是之后才到的。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(16)
            }
            .navigationTitle("戳一戳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关掉") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 零件

    @ViewBuilder
    private func group(_ title: String,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            content()
        }
    }

    /// 一颗可点的。**不用元组**——Swift 没有指向元组元素的 key path，
    /// `ForEach(items, id: \.0)` 是编译不过的。
    private struct Chip: Identifiable {
        let id: String
        let label: String
    }

    private func chips(_ items: [Chip], selected: String,
                       pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
            ForEach(items) { chip in
                Button {
                    if app.settings.haptics {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    pick(chip.id)
                } label: {
                    Text(chip.label)
                        .font(.app(14))
                        .foregroundStyle(selected == chip.id
                                         ? app.settings.accentColor
                                         : Theme.textMain(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected == chip.id
                                      ? app.settings.accentColor.opacity(0.16)
                                      : Theme.softFillDeep)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
