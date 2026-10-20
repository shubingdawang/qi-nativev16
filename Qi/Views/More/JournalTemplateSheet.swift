import SwiftUI

/// 新建一页之前挑版式：第一个是空白页，后面是排好的模板（见 `JournalTemplates`）
struct JournalTemplateSheet: View {
    let day: Date
    /// nil = 空白页
    let pick: (JournalTemplate?) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private static let ref = CGSize(width: JournalTemplateBuilder.W, height: JournalTemplateBuilder.H)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("选一个版式，再把字和照片填进去；填完还能自己挪、换、删。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    LazyVGrid(columns: cols, spacing: 16) {
                        card(name: "空白页", note: "从一张白纸开始", page: nil) { choose(nil) }
                        ForEach(JournalTemplates.all) { t in
                            card(name: t.name, note: t.note, page: t.page(on: day)) { choose(t) }
                        }
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("选择版式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func choose(_ t: JournalTemplate?) {
        dismiss()
        // 等这一页收起来再开新页，免得两个转场撞在一起
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            pick(t)
        }
    }

    private func card(name: String, note: String, page: JournalPage?, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { g in
                    let k = g.size.width / Self.ref.width
                    Group {
                        if let page {
                            JournalCanvas(page: page, size: Self.ref)
                                .environment(\.journalEditing, true)
                        } else {
                            JournalPaperView(hex: "F5F2EA", pattern: "plain")
                                .frame(width: Self.ref.width, height: Self.ref.height)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 40, weight: .ultraLight))
                                        .foregroundStyle(Color(hexString: "8A8378")!)
                                }
                        }
                    }
                    .frame(width: Self.ref.width, height: Self.ref.height)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
                .aspectRatio(Self.ref.width / Self.ref.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                Text(name)
                    .font(.app(13.5, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(note)
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }
}
