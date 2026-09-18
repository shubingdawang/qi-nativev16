import SwiftUI

/// 聊天页左上角那个心情小签（见 `MoodTagStore`）。点一下打开「状态记录」
struct MoodTagChip: View {

    let conversationID: UUID
    @ObservedObject private var store = MoodTagStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showing = false

    var body: some View {
        if let t = store.current(conversationID) {
            Button { showing = true } label: {
                HStack(spacing: 5) {
                    Text(t.emoji).font(.system(size: 14))
                    Text(t.text)
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.app(9, weight: .semibold))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            // 新的一条进来的时候轻轻换一下，不是硬切
            .id(t.id)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: t.id)
            .sheet(isPresented: $showing) {
                MoodTagHistoryView(conversationID: conversationID)
            }
        }
    }
}

/// 「状态记录」：这一窗里他的心情，一条条往上长的时间线
struct MoodTagHistoryView: View {

    let conversationID: UUID
    @ObservedObject private var store = MoodTagStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let list = store.history(conversationID)
                    if list.isEmpty {
                        Text("还没有记录。聊着聊着他心情变了，这里就会多一条。")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                        row(t, last: i == list.count - 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background { WallpaperBackground() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("状态记录").font(.app(16, weight: .semibold))
                        Text("继续聊天会更新状态").font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            }
        }
    }

    private func row(_ t: MoodTag, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 左边那条线和圆点
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Theme.textSoft(scheme), lineWidth: 2)
                    .frame(width: 11, height: 11)
                    .padding(.top, 4)
                if !last {
                    Rectangle().fill(Theme.textSoft(scheme).opacity(0.35)).frame(width: 1)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(Self.when.string(from: t.at))
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                HStack(spacing: 10) {
                    Text(t.emoji).font(.system(size: 20))
                    Text(t.text)
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(app.settings.accentColor)
                    Spacer(minLength: 6)
                    // 钉住：钉了的永远留着
                    Button { store.togglePin(t.id) } label: {
                        Image(systemName: t.pinned ? "lock.fill" : "lock.open")
                            .font(.app(12))
                            .foregroundStyle(t.pinned ? app.settings.accentColor : Theme.textMuted(scheme))
                            .frame(width: 32, height: 32)
                            .background(Circle().strokeBorder(Theme.textSoft(scheme).opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassCard(radius: 18, padding: 0)
            }
            .padding(.bottom, 16)
        }
    }
}
