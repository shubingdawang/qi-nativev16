import SwiftUI

/// 聊天里那张终端卡。
///
/// ## 它是干什么的
///
/// 她给的参考图：气泡底下嵌一块黑底等宽的终端，顶上是 macOS 那种
/// 三个圆点加一个标签，里面是**它刚才在终端里做了什么**。
///
/// 用在工坊那一栏——那边接的是 Claude Code 本身（`opus-code`），
/// 它会读文件、改代码、跑命令。那些过程用「工具调用」的样子摆出来
/// 是一串卡片，用终端的样子摆出来才是它本来的样子。
///
/// ⚠️ **它只是「显示成终端」，不是一个能敲命令的终端。**
/// 那一层要真做，得让 App 能往桥那边送命令、桥再送回输出——
/// 是另一件事。这张卡先把「看得见它在干什么」做到位。
struct TerminalCard: View {

    /// 标题栏上那个标签（分支名、任务名）
    var title: String = "main"
    /// 里面那些行
    let lines: [String]
    /// 底下那行状态（跑了多久、还剩多少 token）
    var footer: String = ""

    @Environment(\.colorScheme) private var scheme
    @State private var folded = false

    /// 收起来的时候留几行。**留三行不是留零行**——
    /// 全收掉的话她得先点开才知道里面有没有东西，
    /// 而多数时候她只想扫一眼最后发生了什么。
    private static let peek = 3

    private var shown: [String] {
        guard folded, lines.count > Self.peek else { return lines }
        return Array(lines.suffix(Self.peek))
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            body_
        }
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
        )
        // ⚠️ 圆角要自己切一次：里面那块黑底是方的，
        // 不切的话四个角会从圆角里扎出来（第 109 条那个坑）。
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 顶上那条。三个圆点 + 标签 + 收起。
    private var bar: some View {
        HStack(spacing: 7) {
            // 那三个点。**不做成能点的**——它们是装饰，
            // 长得像按钮却点不动的东西比没有更让人恼火，
            // 所以做小、做暗，一看就是画上去的。
            HStack(spacing: 5) {
                dot(Color(red: 0.42, green: 0.20, blue: 0.20))
                dot(Color(red: 0.42, green: 0.32, blue: 0.16))
                dot(Color(red: 0.20, green: 0.38, blue: 0.22))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.08)))
            Spacer(minLength: 0)
            if lines.count > Self.peek {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { folded.toggle() }
                } label: {
                    Image(systemName: folded
                          ? "arrow.down.left.and.arrow.up.right"
                          : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 9, height: 9)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 11)
        .textSelection(.enabled)
    }
}
