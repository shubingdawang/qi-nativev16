import SwiftUI

/// 黑板：此刻的状态（过时自己撤掉）、今天的计数、家里百宝箱还剩什么。
/// 他聊天时顺手记，她在这儿看、改、擦。
struct NowBoardView: View {
    @ObservedObject private var board = NowBoard.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var editingSlot: SlotEdit?
    @State private var editingItem: PantryEdit?
    @State private var addingCounter = false

    struct SlotEdit: Identifiable { let id: String; var text: String; var hours: Double }
    struct PantryEdit: Identifiable { let id = UUID(); var item: PantryItem; let isNew: Bool }

    private var accent: Color { app.settings.accentColor }
    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    var body: some View {
        PaneScroll {
            slotsCard
            countersCard
            pantryCard
        }
        .navigationTitle("黑板")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSlot) { e in
            SlotEditor(edit: e, accent: accent)
                .presentationDetents([.height(330)])
        }
        .sheet(item: $editingItem) { e in
            PantryEditor(start: e.item, isNew: e.isNew, accent: accent)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $addingCounter) {
            CounterEditor(accent: accent)
                .presentationDetents([.height(300)])
        }
    }

    private func header(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.app(14, weight: .semibold)).foregroundStyle(main)
            Text(sub).font(.app(11)).foregroundStyle(muted)
        }
    }

    // MARK: 此刻

    private func remain(_ s: BoardSlot) -> String {
        let mins = Int(Date().timeIntervalSince(s.updated) / 60)
        let ago = mins < 60 ? "\(max(1, mins)) 分钟前" : "\(mins / 60) 小时前"
        let left = Int(s.expires.timeIntervalSinceNow / 3600)
        return ago + " · " + (left >= 1 ? "还留 \(left) 小时" : "即将过期")
    }

    private var slotsCard: some View {
        let live = Dictionary(uniqueKeysWithValues: board.liveSlots.map { ($0.id, $0.slot) })
        return VStack(alignment: .leading, spacing: 14) {
            header("此刻", "在哪、身体、吃了什么药、今天的安排……过时了自己擦掉")
            ForEach(NowBoard.slotInfo.indices, id: \.self) { i in
                let info = NowBoard.slotInfo[i]
                let s = live[info.id]
                Button {
                    editingSlot = SlotEdit(id: info.id, text: s?.value ?? "", hours: info.hours)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(info.label)
                            .font(.app(12))
                            .foregroundStyle(muted)
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s?.value ?? "—")
                                .font(.app(14))
                                .foregroundStyle(s == nil ? muted.opacity(0.6) : main)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let s {
                                Text(remain(s)).font(.app(10.5)).foregroundStyle(muted)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if s != nil {
                        Button(role: .destructive) { board.clear(info.id) } label: {
                            Label("清除", systemImage: "eraser")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 今天

    private var countersCard: some View {
        let counts = board.todayCounts
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                header("今天", "喝水这种要数的，零点清零")
                Spacer()
                Button { addingCounter = true } label: {
                    Image(systemName: "plus.circle").font(.system(size: 18, weight: .light)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            if board.counterNames.isEmpty {
                Text("暂无计数项").font(.app(12.5)).foregroundStyle(muted)
            }
            ForEach(board.counterNames, id: \.self) { k in
                let cur = counts[k] ?? 0
                let goal = board.file.goals[k]
                let unit = board.file.units[k] ?? ""
                HStack(spacing: 10) {
                    Text(k).font(.app(14)).foregroundStyle(main)
                    if let goal {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(main.opacity(0.07))
                                Capsule().fill(accent.opacity(0.6))
                                    .frame(width: g.size.width * min(1, CGFloat(cur) / CGFloat(max(1, goal))))
                            }
                        }
                        .frame(height: 5)
                    } else {
                        Spacer()
                    }
                    Text(goal.map { "\(cur)/\($0)\(unit)" } ?? "\(cur)\(unit)")
                        .font(.app(13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(main)
                    Button { board.bump(k, by: -1) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(muted)
                    }
                    .buttonStyle(.plain)
                    Button { board.bump(k, by: 1) } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 百宝箱

    private var pantryCard: some View {
        let groups = Dictionary(grouping: board.pantry, by: \.kind)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                header("百宝箱", "家里的药和零食还剩多少，快没了会标出来")
                Spacer()
                Button { editingItem = PantryEdit(item: PantryItem(name: ""), isNew: true) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 18, weight: .light)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            if board.pantry.isEmpty {
                Text("还是空的。跟他说一句「家里还有一盒布洛芬」，或者点右上角自己加")
                    .font(.app(12.5)).foregroundStyle(muted)
            }
            ForEach(groups.keys.sorted(), id: \.self) { k in
                Text(k).font(.app(11)).foregroundStyle(muted).padding(.top, 2)
                ForEach(groups[k] ?? []) { it in
                    Button { editingItem = PantryEdit(item: it, isNew: false) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(it.isLow ? Color.orange : accent.opacity(0.35)).frame(width: 6, height: 6)
                            Text(it.name).font(.app(14)).foregroundStyle(main)
                            if !it.place.isEmpty {
                                Text("@" + it.place).font(.app(11)).foregroundStyle(muted)
                            }
                            Spacer()
                            Text(it.amountText)
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(it.isLow ? Color.orange : main)
                            if it.count != nil {
                                Button { board.use(it.name, 1) } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(muted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { board.removePantry(it.name) } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - 编辑

private struct SlotEditor: View {
    let edit: NowBoardView.SlotEdit
    let accent: Color
    @State private var text: String
    @State private var hours: Double
    @Environment(\.dismiss) private var dismiss

    init(edit: NowBoardView.SlotEdit, accent: Color) {
        self.edit = edit
        self.accent = accent
        _text = State(initialValue: edit.text)
        _hours = State(initialValue: edit.hours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NowBoard.label(edit.id)).font(.app(16, weight: .semibold))
            TextField("添加内容", text: $text, axis: .vertical)
                .lineLimit(1...3)
                .font(.app(15))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
            HStack {
                Text("保留时长").font(.app(13.5))
                Spacer()
                Stepper("\(Int(hours)) 小时", value: $hours, in: 1...720, step: hours < 24 ? 1 : 12)
                    .font(.app(13.5))
                    .fixedSize()
            }
            HStack(spacing: 12) {
                Button("清除") {
                    NowBoard.shared.clear(edit.id)
                    dismiss()
                }
                .foregroundStyle(.red)
                Spacer()
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { NowBoard.shared.clear(edit.id) } else { NowBoard.shared.set(edit.id, t, hours: hours) }
                    dismiss()
                } label: {
                    Text("添加").font(.app(15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }
}

private struct CounterEditor: View {
    let accent: Color
    @State private var name = "喝水"
    @State private var goal = "8"
    @State private var unit = "杯"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日计数").font(.app(16, weight: .semibold))
            HStack(spacing: 10) {
                TextField("名字", text: $name).font(.app(15))
                TextField("目标", text: $goal).keyboardType(.numberPad).frame(width: 60).font(.app(15))
                TextField("单位", text: $unit).frame(width: 50).font(.app(15))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
            Text("目标填 0 就是只数不设目标").font(.app(11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    NowBoard.shared.setGoal(n, Int(goal) ?? 0, unit: unit)
                    NowBoard.shared.bump(n, by: 0)
                    dismiss()
                } label: {
                    Text("加上").font(.app(15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }
}

private struct PantryEditor: View {
    let isNew: Bool
    let accent: Color
    @State private var item: PantryItem
    @State private var countText: String
    @State private var counted: Bool
    @Environment(\.dismiss) private var dismiss

    init(start: PantryItem, isNew: Bool, accent: Color) {
        self.isNew = isNew
        self.accent = accent
        _item = State(initialValue: start)
        _countText = State(initialValue: start.count.map { String($0) } ?? "")
        _counted = State(initialValue: start.count != nil || isNew)
    }

    var body: some View {
        NavigationStack {
            QiForm {
                TextField("名字，比如：布洛芬", text: $item.name)
                    .disabled(!isNew)
                Picker("种类", selection: $item.kind) {
                    ForEach(["药", "零食", "日用", "其他"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("按数量记录", isOn: $counted)
                if counted {
                    HStack {
                        TextField("剩余数量", text: $countText).keyboardType(.numberPad)
                        TextField("单位", text: $item.unit).frame(width: 70)
                    }
                    Stepper("剩 \(item.low) 个就提醒", value: $item.low, in: 0...50)
                } else {
                    Picker("余量", selection: $item.level) {
                        ForEach(["有", "即将用完", "已用完"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                TextField("存放位置（选填）", text: $item.place)
            }
            .navigationTitle(isNew ? "添加物品" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("存") {
                        var it = item
                        it.name = it.name.trimmingCharacters(in: .whitespaces)
                        guard !it.name.isEmpty else { return }
                        it.count = counted ? (Int(countText) ?? 0) : nil
                        NowBoard.shared.savePantry(it)
                        dismiss()
                    }
                    .foregroundStyle(accent)
                }
            }
        }
    }
}
