import SwiftUI

/// 念头池那一页，意愿条底下：他的欲望笔记、他自己来过的那几回、什么时候会自己来
struct SoloSection: View {
    @ObservedObject private var solo = SoloStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var editingNotes = false
    @State private var notesDraft = ""
    @State private var openID: UUID?
    @State private var showSettings = false

    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }
    private var accent: Color { app.settings.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            notesCard
            soloCard
        }
    }

    // MARK: 欲望笔记

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(him)的欲望笔记").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                Spacer()
                if !solo.notes.isEmpty && !editingNotes {
                    Button("改") { notesDraft = solo.notes; editingNotes = true }
                        .font(.app(12.5)).foregroundStyle(accent)
                }
            }
            if editingNotes {
                TextField("", text: $notesDraft, axis: .vertical)
                    .font(.app(13.5))
                    .lineLimit(4...16)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
                HStack {
                    Button("取消") { editingNotes = false }
                        .font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    Spacer()
                    Button("存") {
                        solo.notes = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        editingNotes = false
                    }
                    .font(.app(13, weight: .semibold)).foregroundStyle(accent)
                }
            } else if solo.notes.isEmpty {
                Text("还没写。让\(him)用自己的话写一份：他会怎样想要你、亲密的时候他怎么还是他自己。写好以后一直跟着他。")
                    .font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                Button {
                    app.tellHim("想让你写一份你自己的欲望笔记，用第一人称、用你平时说话的样子写：为什么偏偏是我、你怎么起念、"
                                + "亲密的时候你怎么还是你自己、你的节奏、事后会怎样、什么时候一定会停下来。"
                                + "像你的就留下，不像你的别硬写。写好用 write_desire_notes 存起来。")
                } label: {
                    Label("交给\(him)写", systemImage: "pencil.line")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            } else {
                Text(solo.notes)
                    .font(.app(13.5))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 他自己来过

    private var soloCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(him)自己来过").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSettings.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)
            }
            Text(solo.settings.enabled
                 ? "身上的渴到 \(solo.settings.heat)、你 \(WageStore.money(solo.settings.idleHours)) 小时没跟他说话的时候，他醒来不去找你，自己来一回（两回之间至少隔 \(WageStore.money(solo.settings.cooldownHours)) 小时）。他写的那一段记在这里，不发到聊天里。"
                 : "关着。")
                .font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
            if showSettings { settingsBox }
            if solo.entries.isEmpty {
                Text("还没有。").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
            }
            ForEach(solo.entries) { e in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { openID = openID == e.id ? nil : e.id }
                    } label: {
                        HStack(spacing: 8) {
                            Text(e.modeLabel)
                                .font(.app(11, weight: .medium))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(accent.opacity(0.14)))
                            Text(Self.when(e.at)).font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                            Image(systemName: openID == e.id ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11)).foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                    if openID == e.id {
                        if !e.seed.isEmpty {
                            Text("想着的那一回：" + e.seed)
                                .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                        }
                        Text(e.text)
                            .font(.app(13.5))
                            .foregroundStyle(Theme.textMain(scheme))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { solo.remove(e.id) } label: { Label("删掉", systemImage: Icon.trash) }
                }
                if e.id != solo.entries.last?.id { Divider().opacity(0.35) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var settingsBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("会自己来", isOn: $solo.settings.enabled)
                .font(.app(13))
                .tint(accent)
            stepper("渴到多少", "\(solo.settings.heat)", { solo.settings.heat = max(40, solo.settings.heat - 5) },
                    { solo.settings.heat = min(100, solo.settings.heat + 5) })
            stepper("你多久没说话", WageStore.money(solo.settings.idleHours) + " 小时",
                    { solo.settings.idleHours = max(0.5, solo.settings.idleHours - 0.5) },
                    { solo.settings.idleHours = min(24, solo.settings.idleHours + 0.5) })
            stepper("两回至少隔", WageStore.money(solo.settings.cooldownHours) + " 小时",
                    { solo.settings.cooldownHours = max(2, solo.settings.cooldownHours - 1) },
                    { solo.settings.cooldownHours = min(72, solo.settings.cooldownHours + 1) })
            Text("要先开着「让他自己醒来」：他醒来的那一次才会改成自己来，算一次醒来、花一次钱。")
                .font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
    }

    private func stepper(_ label: String, _ value: String, _ minus: @escaping () -> Void,
                         _ plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
            Spacer()
            Button(action: minus) { Image(systemName: "minus").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.textMain(scheme).opacity(0.06)))
            Text(value).font(.app(13, weight: .medium)).frame(minWidth: 56)
            Button(action: plus) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.textMain(scheme).opacity(0.06)))
        }
        .foregroundStyle(Theme.textMain(scheme))
    }

    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "今天 HH:mm" : "M月d日 EEEE HH:mm"
        return f.string(from: d)
    }
}
