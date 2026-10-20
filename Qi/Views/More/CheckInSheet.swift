import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - 查岗（App 里交）
//
// 他用 plan_check_in 定好时间，到点 App 发一条通知；她点开（或者到点以后打开 App）
// 弹出这一页：在做什么、一张截图、今天的健康数据，交上去就是一条消息发给他。
// 快捷指令那条路（获取查岗计划 → 提交查岗）照旧能用，两条路交的是同一份计划。

extension CheckPlan {
    static let noticeID = "himCheckIn"

    /// 到点发一条通知
    static func schedule(_ p: CheckPlan, him: String) {
        let c = UNMutableNotificationContent()
        c.title = "\(him)来查岗了"
        c.body = "看看你在做什么：" + p.items.joined(separator: "、")
        c.sound = .default
        c.userInfo = ["checkIn": true]
        let secs = max(1, p.at.timeIntervalSinceNow)
        let req = UNNotificationRequest(identifier: noticeID, content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: false))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [noticeID])
        center.add(req)
    }

    static func cancelNotice() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [noticeID])
    }

    /// 到点了还没交
    static var due: CheckPlan? {
        guard let p = current, p.at <= Date() else { return nil }
        return p
    }
}

struct CheckInSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var plan = CheckPlan.current
    @State private var doing = ""
    @State private var pick: PhotosPickerItem?
    @State private var shot: UIImage?
    @State private var withHealth = true
    @State private var sending = false

    private var him: String { app.settings.aiName.isEmpty ? "他" : app.settings.aiName }
    private var wants: [String] { plan?.items ?? ["在做什么"] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(him)想看：" + wants.joined(separator: "、"))
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("在做什么").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                        TextField("例如：在公司开会", text: $doing, axis: .vertical)
                            .font(.app(14))
                            .lineLimit(2...5)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("截图").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                        Text("可选：屏幕使用时间，或此刻的屏幕")
                            .font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                        HStack(spacing: 12) {
                            if let shot {
                                Image(uiImage: shot)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            PhotosPicker(selection: $pick, matching: .images) {
                                Label(shot == nil ? "选择截图" : "更换", systemImage: "photo")
                                    .font(.app(13, weight: .medium))
                                    .foregroundStyle(app.settings.accentColor)
                            }
                            if shot != nil {
                                Button("移除") { shot = nil; pick = nil }
                                    .font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    Toggle(isOn: $withHealth) {
                        Text("附上今天的健康数据").font(.app(14)).foregroundStyle(Theme.textMain(scheme))
                    }
                    .tint(app.settings.accentColor)
                    .glassCard()
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("查岗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("稍后") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sending ? "提交中…" : "提交") { submit() }
                        .fontWeight(.semibold)
                        .disabled(sending || (doing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && shot == nil && !withHealth))
                }
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        shot = ImageStore.downscale(img, maxSide: 1400)
                    }
                }
            }
        }
    }

    private func submit() {
        sending = true
        Task { @MainActor in
            var lines = ["（查岗回执"]
            let d = doing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { lines.append("在做什么：" + d) }
            if withHealth, let h = await HealthTools.todayBrief() { lines.append("健康：" + h) }
            if shot != nil { lines.append("附了一张截图（屏幕使用时间或此刻的屏幕）") }
            lines[lines.count - 1] += "）"
            CheckPlan.current = nil
            CheckPlan.cancelNotice()
            app.shortcutToHim(lines.joined(separator: "\n"), open: true, images: shot.map { [$0] } ?? [])
            sending = false
            dismiss()
        }
    }
}
