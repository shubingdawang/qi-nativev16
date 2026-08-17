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

    /// 拖的时候先落在这儿，不碰全局
    @State private var draft: Double?
    @State private var dragging = false

    private var live: Double { draft ?? value }

    /// 拖的时候读数按草稿算。原来的 readout 是外面按 value 拼好的字符串，
    /// 拖的时候它不会变——所以这里按格式重算一遍。
    private var liveReadout: String {
        guard let d = draft else { return readout }
        // 原来的读数长什么样，就照着拼：带 % 的按百分比，别的按整数
        if readout.hasSuffix("%") { return "\(Int(d * 100))%" }
        if readout.contains(".") { return String(format: "%.1f", d) }
        return "\(Int(d))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Text(liveReadout)
                    .font(.system(size: 12, design: .monospaced))
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
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var binding: Binding<Double> {
        Binding(get: { live },
                set: { v in
                    draft = v
                    onDraft?(v)
                })
    }

    private func editing(_ on: Bool) {
        dragging = on
        guard !on else { return }
        // 松手：把草稿写回去，全局这时候才重画一次
        if let d = draft { value = d }
        draft = nil
        onDraft?(nil)
    }
}
