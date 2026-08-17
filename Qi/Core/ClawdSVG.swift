import Foundation

/// clawd 表情工坊用的那些料。
///
/// 她想「直接用 SVG 和 CSS 做 clawd 的表情包」，所以这儿放的是**起点和零件**，
/// 不是一堆做好的成品：一副能改的骨架、几张换脸的模板、
/// 一排点一下就插进去的小零件。
///
/// 尺寸统一 `viewBox="0 0 320 230"`，跟像素版那只是一个比例
/// （图纸 32 × 23，这儿每格当 10）。这样两版摆在一起不会一个胖一个瘦。
///
/// 颜色也照像素版那份调色板走，别自己另配一套：
///   身子 #F2715F · 暗一档 #C9553F · 眼睛纯黑 · 头顶小闪光 #F0C040
enum ClawdSVG {

    static let bodyColor = "#F2715F"
    static let darkColor = "#C9553F"

    /// 骨架。身子、两只手、四条腿——**除了脸，别的都在这儿了**。
    /// 她要改表情，改的是下面那个 `face` 区块。
    static let skeleton = """
    <svg viewBox="0 0 320 230" xmlns="http://www.w3.org/2000/svg">
      <g id="clawd">
        <!-- 两只手 -->
        <rect class="body" x="0"   y="60" width="40" height="30"/>
        <rect class="body" x="280" y="60" width="40" height="30"/>
        <!-- 身子 -->
        <rect class="body" x="40" y="0" width="240" height="170" rx="6"/>
        <!-- 四条腿：左边两条、右边两条，中间空一大段 -->
        <rect class="body" x="40"  y="170" width="30" height="60"/>
        <rect class="body" x="100" y="170" width="30" height="60"/>
        <rect class="body" x="210" y="170" width="30" height="60"/>
        <rect class="body" x="270" y="170" width="30" height="60"/>
        <!-- 脸。改这里 -->
        <g id="face">
          <rect class="eye" x="70"  y="50" width="30" height="30"/>
          <rect class="eye" x="220" y="50" width="30" height="30"/>
        </g>
      </g>
    </svg>
    """

    static let baseCSS = """
    /* 底色一律用变量，改一处全身跟着变 */
    :root {
      --body: \(bodyColor);
      --dark: \(darkColor);
    }
    .body { fill: var(--body); }
    .eye  { fill: #000; }
    .dim  { fill: var(--dark); }
    .blush { fill: #FF9A8B; opacity: .55; }

    /* 整只呼吸。不想要就把这段删了 */
    #clawd {
      transform-origin: 160px 200px;
      animation: breathe 2.6s ease-in-out infinite;
    }
    @keyframes breathe {
      0%, 100% { transform: translateY(0) scaleY(1); }
      50%      { transform: translateY(4px) scaleY(.985); }
    }
    """

    // MARK: 换一张脸

    struct Face: Identifiable {
        var id: String { name }
        let name: String
        let svg: String
    }

    /// 点一下就把 `#face` 整块换掉。
    /// 每张脸都只用矩形——clawd 本来就是方的，画圆反而不像它。
    static let faces: [Face] = [
        Face(name: "睁着", svg: """
        <rect class="eye" x="70"  y="50" width="30" height="30"/>
        <rect class="eye" x="220" y="50" width="30" height="30"/>
        """),
        Face(name: "眯眼笑", svg: """
        <rect class="eye" x="70"  y="68" width="30" height="12"/>
        <rect class="eye" x="220" y="68" width="30" height="12"/>
        <rect class="blush" x="55"  y="95" width="34" height="16" rx="8"/>
        <rect class="blush" x="231" y="95" width="34" height="16" rx="8"/>
        """),
        Face(name: "闭着睡", svg: """
        <rect class="dim" x="70"  y="66" width="30" height="8"/>
        <rect class="dim" x="220" y="66" width="30" height="8"/>
        """),
        Face(name: "眨一只", svg: """
        <rect class="eye" x="70"  y="50" width="30" height="30"/>
        <rect class="eye" x="220" y="68" width="30" height="12"/>
        """),
        Face(name: "惊了", svg: """
        <rect class="eye" x="66"  y="42" width="38" height="46"/>
        <rect class="eye" x="216" y="42" width="38" height="46"/>
        <rect class="dim" x="140" y="110" width="40" height="26" rx="12"/>
        """),
        Face(name: "生气", svg: """
        <rect class="eye" x="70"  y="56" width="30" height="24"/>
        <rect class="eye" x="220" y="56" width="30" height="24"/>
        <rect class="dim" x="62"  y="36" width="44" height="9" transform="rotate(14 84 40)"/>
        <rect class="dim" x="214" y="36" width="44" height="9" transform="rotate(-14 236 40)"/>
        """),
        Face(name: "委屈", svg: """
        <rect class="eye" x="70"  y="54" width="30" height="30"/>
        <rect class="eye" x="220" y="54" width="30" height="30"/>
        <rect class="dim" x="62"  y="40" width="44" height="8" transform="rotate(-12 84 44)"/>
        <rect class="dim" x="214" y="40" width="44" height="8" transform="rotate(12 236 44)"/>
        <rect class="dim" x="148" y="112" width="24" height="8" rx="4"/>
        """),
        Face(name: "害羞", svg: """
        <rect class="eye" x="70"  y="66" width="30" height="14"/>
        <rect class="eye" x="220" y="66" width="30" height="14"/>
        <rect class="blush" x="50"  y="92" width="42" height="20" rx="10"/>
        <rect class="blush" x="228" y="92" width="42" height="20" rx="10"/>
        """)
    ]

    // MARK: 点一下插一块

    struct Part: Identifiable {
        var id: String { name }
        let name: String
        /// 插进 svg 里的那段
        let svg: String
        /// 要配的样式，没有就是空的
        let css: String
    }

    static let parts: [Part] = [
        Part(name: "腮红",
             svg: """
             <rect class="blush" x="50"  y="92" width="42" height="20" rx="10"/>
             <rect class="blush" x="228" y="92" width="42" height="20" rx="10"/>
             """,
             css: ""),
        Part(name: "头顶闪光",
             svg: """
             <rect class="spark" x="150" y="-26" width="16" height="16"/>
             """,
             css: """
             .spark {
               fill: #F0C040;
               animation: twinkle .9s steps(2) infinite;
             }
             @keyframes twinkle { 50% { opacity: 0; } }
             """),
        Part(name: "举高高",
             svg: "",
             css: """
             #clawd { animation: hop .7s ease-in-out infinite; }
             @keyframes hop {
               0%, 100% { transform: translateY(0); }
               50%      { transform: translateY(-16px); }
             }
             """),
        Part(name: "左右晃",
             svg: "",
             css: """
             #clawd {
               transform-origin: 160px 230px;
               animation: sway 1.4s ease-in-out infinite;
             }
             @keyframes sway {
               0%, 100% { transform: rotate(-5deg); }
               50%      { transform: rotate(5deg); }
             }
             """),
        Part(name: "一行字",
             svg: """
             <text class="say" x="160" y="-34">在呢</text>
             """,
             css: """
             .say {
               fill: #4A4038;
               font-size: 34px;
               font-weight: 600;
               text-anchor: middle;
             }
             """),
        Part(name: "小水滴",
             svg: """
             <rect class="tear" x="86" y="86" width="12" height="22" rx="6"/>
             """,
             css: """
             .tear {
               fill: #7FB3D5;
               animation: drop 1.6s ease-in infinite;
             }
             @keyframes drop {
               0%   { transform: translateY(0); opacity: 1; }
               100% { transform: translateY(70px); opacity: 0; }
             }
             """),
        Part(name: "抱个东西",
             svg: """
             <rect class="hold" x="118" y="120" width="84" height="60" rx="6"/>
             """,
             css: """
             .hold { fill: #E5DCC8; stroke: #C9BFA6; stroke-width: 4; }
             """)
    ]

    // MARK: 拼成一张能渲染的网页

    /// 预览和导出用的是**同一份** HTML，所见即所得。
    ///
    /// 背景留透明——表情包贴到聊天里不该带一块白底。
    static func page(svg: String, css: String, scale: Double = 1) -> String {
        // viewBox 是 320×230，留点余量给头顶的闪光和那行字
        let width = 380.0 * scale
        let height = 320.0 * scale
        return """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body {
          margin: 0; padding: 0;
          background: transparent;
          width: \(Int(width))px; height: \(Int(height))px;
          display: flex; align-items: center; justify-content: center;
          overflow: hidden;
        }
        svg { width: \(Int(width * 0.86))px; overflow: visible; }
        \(css)
        </style>
        </head><body>
        \(svg)
        </body></html>
        """
    }

    /// 把骨架里的 `#face` 换成另一张脸
    static func replaceFace(in svg: String, with face: String) -> String {
        guard let start = svg.range(of: "<g id=\"face\">"),
              let end = svg.range(of: "</g>", range: start.upperBound..<svg.endIndex)
        else { return svg }
        let head = svg[svg.startIndex..<start.upperBound]
        let tail = svg[end.lowerBound..<svg.endIndex]
        return head + "\n" + face + "\n      " + tail
    }

    /// 在最后一个 `</g>` 之前塞一块进去。
    /// 塞在 clawd 这一组里面，它才会跟着整只一起动。
    static func insert(_ part: String, into svg: String) -> String {
        guard !part.isEmpty else { return svg }
        guard let mark = svg.range(of: "</g>", options: .backwards) else {
            return svg
        }
        return svg.replacingCharacters(in: mark, with: "  " + part + "\n  </g>")
    }
}
