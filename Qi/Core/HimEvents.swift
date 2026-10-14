import SwiftUI

/// 攒着还没告诉他的事（小岛、小屋里做的事）。
///
/// 在小岛上做了一件事，会先问她要不要告诉他：告诉就当场发过去，
/// 不告诉就存在这儿。之后在聊天输入框的「+ → 事件」里挑一件或几件，一起发给他当个话题。
struct HimEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 发给他的那句（「小岛上，她……」）
    var text: String
    /// 从哪儿来的：小岛、小屋
    var source: String
    var at = Date()
}

@MainActor
final class HimEvents: ObservableObject {

    static let shared = HimEvents()

    @Published private(set) var items: [HimEvent] = [] {
        didSet { Storage.save(items, to: "him-events.json") }
    }

    private init() {
        items = Storage.load([HimEvent].self, from: "him-events.json") ?? []
    }

    func add(_ text: String, source: String) {
        items.insert(HimEvent(text: text, source: source), at: 0)
        // 攒太多就把最老的丢掉
        if items.count > 200 { items.removeLast(items.count - 200) }
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    /// 挑出来的几件拼成一句发给他
    static func message(_ list: [HimEvent]) -> String {
        let sorted = list.sorted { $0.at < $1.at }
        if sorted.count == 1 { return sorted[0].text }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        let lines = sorted.enumerated().map { i, e in "\(i + 1). \(f.string(from: e.at))，\(e.text)" }
        return "她攒了几件事想跟你说：\n" + lines.joined(separator: "\n")
    }
}

/// 做了一件事：先问她要不要现在告诉他
struct HimOfferModifier: ViewModifier {
    @Binding var queue: [String]
    let source: String
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        content.alert("要告诉他吗？", isPresented: Binding(get: { !queue.isEmpty },
                                                    set: { if !$0, !queue.isEmpty { queue.removeFirst() } })) {
            Button("现在告诉他") {
                if let line = queue.first { app.tellHim(line) }
            }
            Button("先存着，之后再说") {
                if let line = queue.first { HimEvents.shared.add(line, source: source) }
            }
        } message: {
            Text((queue.first ?? "") + "\n\n存着的在聊天输入框「+ → 事件」里，可以挑几件一起发给他。")
        }
    }
}

extension View {
    /// 要告诉他的事先排队问她（见 `HimOfferModifier`）
    func himOffer(_ queue: Binding<[String]>, source: String) -> some View {
        modifier(HimOfferModifier(queue: queue, source: source))
    }
}

/// 聊天输入框「+ → 事件」：挑一件或几件攒着的事发给他
struct HimEventsSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = HimEvents.shared
    @State private var chosen: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if store.items.isEmpty {
                        EmptyNote(icon: "tray", title: "还没有攒着的事",
                                  hint: "在小岛上做了事、选「先存着」，就会出现在这里。")
                            .padding(.top, 40)
                    }
                    ForEach(store.items) { e in
                        let on = chosen.contains(e.id)
                        Button {
                            if on { chosen.remove(e.id) } else { chosen.insert(e.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.app(17))
                                    .foregroundStyle(on ? app.settings.accentColor : Theme.textMuted(scheme))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.text).font(.app(13.5)).foregroundStyle(Theme.textMain(scheme))
                                        .multilineTextAlignment(.leading)
                                    Text(e.source + " · " + e.at.formatted(date: .abbreviated, time: .shortened))
                                        .font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .glassCard(padding: 0)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.remove([e.id]); chosen.remove(e.id) } label: {
                                Label("删掉", systemImage: Icon.trash)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .safeAreaInset(edge: .bottom) {
                if !store.items.isEmpty {
                    Button {
                        let list = store.items.filter { chosen.contains($0.id) }
                        guard !list.isEmpty else { return }
                        app.tellHim(HimEvents.message(list))
                        store.remove(chosen)
                        dismiss()
                    } label: {
                        Text(chosen.isEmpty ? "挑几件发给他" : "发给他（\(chosen.count) 件）")
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(chosen.isEmpty ? Color.gray.opacity(0.5) : app.settings.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(chosen.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("事件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.items.isEmpty {
                        Button(chosen.count == store.items.count ? "全不选" : "全选") {
                            chosen = chosen.count == store.items.count ? [] : Set(store.items.map(\.id))
                        }
                    }
                }
            }
        }
    }
}
