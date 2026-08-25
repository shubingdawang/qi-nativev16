import SwiftUI

/// 设置页里那种带标题和读数的滑块。
///
/// ## 为什么不是直接一个 `Slider(value: $app.settings.xxx)`
///
/// 她说「深色下压暗这个进度条无法拖动了」。滑块本身没坏——
/// **是拖的每一帧都太贵**：那个值一动，
///
///   · `AppSettings` 变 → 整个 App 重新求值
///   · `Theme.glassDim` 跟着变 → 屏幕上**每一块玻璃**重画一次模糊
///   · 而这根滑块底下正好还垫着两块带壁纸的样品，又是两次模糊
///
/// 一秒钟六十次这个，主线程直接被吃满，手指划过去屏幕没反应——
/// 看着就是「拖不动」。
///
/// 所以现在：**拖的时候只在自己心里改**（外加通知旁边那两块小样品），
/// **松手才写回全局**。拖起来跟手，效果也还看得见。
struct SettingsSlider: View {

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// 右上角那个读数。传进来的是「当前 value 的读数」，
    /// 拖的时候用下面 `draftReadout` 现算，免得读数不跟着动。
    var readout: String
    var note: String?
    var tint: Color
    var scheme: ColorScheme
    /// 拖的过程中把实时值喊出去（给旁边的样品用）。松手传 nil。
    var onDraft: ((Double?) -> Void)?
    /// 拖的过程中就写回去。
    ///
    /// 只给**便宜**的滑块开：字号那根就得开——她说
    /// 「设置里的字号调整没有即时显示，拖动时设置里的字不会跟着变」，
    /// 而字号一变整页的字当场就跟着长大，那正是她要看的反馈。
    /// 玻璃那两根不能开：一动就要重画全屏的模糊，拖起来会卡死。
    var live = false

    /// 拖的时候先落在这儿，不碰全局
    @State private var draft: Double?
    @State private var dragging = false

    private var liveValue: Double { draft ?? value }

    /// 拖的时候读数按草稿算。原来的 readout 是外面按 value 拼好的字符串，
    /// 拖的时候它不会变——所以这里按格式重算一遍。
    private var liveReadout: String {
        guard let d = draft, d != value else { return readout }
        // 原来的读数长什么样，就照着拼：带 % 的按百分比，别的按整数
        if readout.hasSuffix("%") { return "\(Int(d * 100))%" }
        if readout.contains(".") { return String(format: "%.1f", d) }
        return "\(Int(d))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Text(liveReadout)
                    .font(.app(12, design: .monospaced))
                    .foregroundStyle(dragging ? tint : Theme.textMuted(scheme))
            }

            Group {
                if let step {
                    Slider(value: binding, in: range, step: step,
                           onEditingChanged: editing)
                } else {
                    Slider(value: binding, in: range, onEditingChanged: editing)
                }
            }
            .tint(tint)
            // 按住的时候整根胖一点。她说别的按钮按下去会放大一下，这根没有反应。
            .scaleEffect(y: dragging ? 1.35 : 1, anchor: .center)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: dragging)

            if let note {
                // ⚠️ 走 `MD.inline`，不能是 `Text(note)`。
                // `note` 是个**变量**——SwiftUI 只对写死的字面量解析 markdown，
                // 拿变量渲染的时候两对星号是原样显示出来的。
                // 她说的「没有 markdown 渲染」就是这一处：
                // 「模糊程度」「深色下压暗」那几段说明底下全是裸露的 `**`。
                Text(MD.inline(note))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var binding: Binding<Double> {
        Binding(get: { liveValue },
                set: { v in
                    draft = v
                    onDraft?(v)
                    if live { value = v }
                })
    }

    private func editing(_ on: Bool) {
        dragging = on
        guard !on else { return }
        // 松手：把草稿写回去，全局这时候才重画一次。
        //
        // ⚠️ **清草稿要等下一帧**。
        // 以前是写完 `value` 紧接着就 `draft = nil`，两件事挤在同一帧里：
        // 那一帧样品读的是 `draft ?? 全局值`，草稿已经没了、全局那份
        // 又还没传下来，于是它先闪回旧的样子，下一帧才跳到新的——
        // 她看到的「样品偶尔会显示效果，然后才是全局玻璃更换」就是这一闪。
        //
        // 而且这一闪之后 `onDraft?(nil)` 已经发出去了，
        // 外面那个 @State 也被清成 nil；多拖几次之后节奏一乱，
        // 样品就再也接不上即时反馈了（她说的第二半）。
        if let d = draft { value = d }
        DispatchQueue.main.async {
            draft = nil
            onDraft?(nil)
        }
    }
}
