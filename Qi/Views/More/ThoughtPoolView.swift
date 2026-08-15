import SwiftUI

/// 念头池。
///
/// 上层飘着闪念（淡、小、会散），底下沉着执念（浓、大、还在长）。
/// 越强的越往下沉——这个上下关系不是装饰，它就是那套机制本身：
/// 浮着的会消失，沉底的会反过来推着人动。
struct ThoughtPoolView: View {

    @ObservedObject private var pool = ThoughtPool.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var adding = false
    @State private var draft = ""
    @State private var showResolved = false
    @State private var breathing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // 池子
                ZStack(alignment: .top) {
                    // 水面到水底，越往下越沉
                    LinearGradient(
                        colors: [
                            app.settings.accentColor.opacity(scheme == .dark ? 0.06 : 0.05),
                            app.settings.accentColor.opacity(scheme == .dark ? 0.20 : 0.16)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 0) {
                        // 上层：闪念
                        VStack(spacing: 7) {
                            if pool.flashes.isEmpty {
                                Text("上面没什么在飘")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                                    .padding(.vertical, 14)
                            }
                            ForEach(pool.flashes) { t in
                                bubbleRow(t)
                            }
                        }
                        .padding(.top, 16)

                        Spacer(minLength: 20)

                        // 下层：执念
                        VStack(spacing: 8) {
                            ForEach(pool.obsessions) { t in
                                bubbleRow(t)
                            }
                            if pool.obsessions.isEmpty {
                                Text("底下是空的，没有压着的事")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                                    .padding(.vertical, 14)
                            }
                        }
                        .padding(.bottom, 18)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(minHeight: 340)

                if let feed = pool.lastFeed {
                    HStack(spacing: 6) {
                        StatusDot(tone: .focus)
                        Text("「\(feed)」已经压到反过来推人的程度了")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSoft(scheme))
                    }
                }

                // 说明。这套机制不写清楚，看到的人只会觉得是一堆气泡。
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([
                            "闪念从 0.5 起步，没人理它每一拍衰减到 0.82 倍，散掉就没了。",
                            "同一桩事被反复点到，强度会叠上去——聊到、或者他自己又想起来，都算。",
                            "涨过 0.8 就升级成执念。执念不衰减，反而每拍自己长 1.1 倍。",
                            "长到 0.85 会反过来推欲望。推够三次就想透了，出池——那时它不再是念头，是行动力。",
                            "这跟记忆不一样：记忆是已经落下来的沉淀物，这里是还在转的活水。"
                        ], id: \.self) { line in
                            Text("· " + line)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("这池子怎么转的")
                        .font(.system(size: 12))
                        .foregroundStyle(app.settings.accentColor)
                }

                if !pool.resolvedOnes.isEmpty {
                    Button {
                        withAnimation { showResolved.toggle() }
                    } label: {
                        Text(showResolved
                             ? "收起已经了却的"
                             : "看看已经了却的（\(pool.resolvedOnes.count)）")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)

                    if showResolved {
                        ForEach(pool.resolvedOnes.prefix(20)) { t in
                            HStack(spacing: 8) {
                                Text(t.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .strikethrough()
                                Spacer()
                                Text(t.fedCount >= 3 ? "想透了" : "散了")
                                    .font(.system(size: 10))
                                    .foregroundStyle(t.fedCount >= 3
                                                     ? StatusTone.done.color
                                                     : Theme.textMuted(scheme).opacity(0.6))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("念头池")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = ""
                    adding = true
                } label: {
                    Image(systemName: Icon.add)
                }
            }
        }
        .alert("往池子里丢一个", isPresented: $adding) {
            TextField("在想什么", text: $draft)
            Button("取消", role: .cancel) {}
            Button("丢进去") {
                pool.stir(draft)
            }
        } message: {
            Text("刚丢进去的是闪念，没人再提就自己散了。")
        }
        .onAppear {
            pool.settle()
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private func bubbleRow(_ t: Thought) -> some View {
        // 越强的字越大、越实
        let size = 12 + t.strength * 5
        let opacity = 0.35 + t.strength * 0.65

        return HStack(spacing: 8) {
            Circle()
                .fill(t.isObsession
                      ? StatusTone.focus.color.opacity(0.75)
                      : app.settings.accentColor.opacity(0.5))
                .frame(width: t.isObsession ? 8 : 6,
                       height: t.isObsession ? 8 : 6)
                .scaleEffect(t.isObsession && breathing ? 1.25 : 1)

            Text(t.text)
                .font(.system(size: size, weight: t.isObsession ? .medium : .regular))
                .foregroundStyle(Theme.textMain(scheme).opacity(opacity))
                .lineLimit(2)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.2f", t.strength))
                    .font(HomeType.number(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                if t.hits > 1 {
                    Text("被戳 \(t.hits) 次")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                }
                if t.fedCount > 0 {
                    Text("推过 \(t.fedCount)/3")
                        .font(.system(size: 9))
                        .foregroundStyle(StatusTone.focus.color.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(scheme == .dark
                                          ? 0.05 + t.strength * 0.05
                                          : 0.35 + t.strength * 0.35))
        }
        .contextMenu {
            Button {
                pool.stir(t.text)     // 再想一次，等于又戳一下
            } label: {
                Label("又想到了", systemImage: "arrow.clockwise")
            }
            Button {
                pool.resolve(t.id)
            } label: {
                Label("想通了，了却", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                pool.remove(t.id)
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }
}
