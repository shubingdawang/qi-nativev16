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

    /// clawd 的骨架，**只有这一份**。
    ///
    /// ⚠️ 她连着两轮报「表情工坊的 clawd 一条腿长在身体外面」，
    /// 第一轮我改了下面那串 SVG，她说「依然是」——因为**骨架抄了两份**：
    /// 这儿一份，`ClawdGridEditor` 里的 `ClawdSilhouette` 又照着画了一遍，
    /// 而工坊画布上她看到的恰恰是后面那一份，它还留着老坐标
    /// （最后一条腿 x=270 宽 30 → 270..300，身子只到 280，
    ///  二十个点实实在在戳在外面）。
    ///
    /// 所以这次不是再改一遍坐标，是**把两份合成一份**：
    /// 方块只在这儿列一次（`blocks`），SVG 那串和剪影那个 Shape 都从它生成。
    /// 抄两份的下场就是这样——改对了一份，她看到的偏偏是另一份。
    ///
    /// 坐标照像素版那份图纸换算（图纸 32 格 × 每格 10）：
    /// 身子占第 4..27 格 → 40..280；
    /// 腿在第 4-6、9-11、20-22、25-27 格 → 40 / 90 / 200 / 250，左右对称。
    /// ⚠️ 叫 `Block` 不叫 `Part`：**这个文件里早就有一个 `Part`**——
    /// 底下那个是「点一下插一块」的**零件**（腮红、头顶闪光、举高高……）。
    /// 我第一版顺手也起名 `Part`，构建当场报 ambiguous。
    /// 同一轮里第二次栽在重名上了，规矩记在这儿：
    /// **新起一个名字之前，先在这个文件里搜一遍它在不在。**
    struct Block {
        var x: Double, y: Double, w: Double, h: Double
        /// 圆角。只有身子有
        var rx: Double = 0
    }

    static let blocks: [Block] = [
        // 两只手
        Block(x: 0,   y: 60,  w: 40,  h: 30),
        Block(x: 280, y: 60,  w: 40,  h: 30),
        // 身子
        Block(x: 40,  y: 0,   w: 240, h: 170, rx: 6),
        // 四条腿：左边两条、右边两条，中间空一大段
        Block(x: 40,  y: 170, w: 30,  h: 60),
        Block(x: 90,  y: 170, w: 30,  h: 60),
        Block(x: 200, y: 170, w: 30,  h: 60),
        Block(x: 250, y: 170, w: 30,  h: 60)
    ]

    /// 骨架那串 SVG。**从 `blocks` 生成**，别再手写一遍。
    /// 她要改表情，改的是里面那个 `face` 区块。
    static var skeleton: String {
        var s = "<svg viewBox=\"0 0 320 230\" xmlns=\"http://www.w3.org/2000/svg\">\n"
        s += "  <g id=\"clawd\">\n"
        for p in blocks {
            s += "    <rect class=\"body\""
            s += " x=\"\(Int(p.x))\" y=\"\(Int(p.y))\""
            s += " width=\"\(Int(p.w))\" height=\"\(Int(p.h))\""
            if p.rx > 0 { s += " rx=\"\(Int(p.rx))\"" }
            s += "/>\n"
        }
        s += "    <g id=\"face\">\n"
        s += "      <rect class=\"eye\" x=\"70\" y=\"50\" width=\"30\" height=\"30\"/>\n"
        s += "      <rect class=\"eye\" x=\"220\" y=\"50\" width=\"30\" height=\"30\"/>\n"
        s += "    </g>\n"
        s += "  </g>\n</svg>"
        return s
    }

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
             """)
    ]

    // MARK: 能自己填字的那一件

    /// 说一句话。**字是她填的，不是写死的。**
    ///
    /// ⚠️ 上一版把这件做成了固定零件，内容写死成「在呢」。
    /// 她的原话：「加一行字，写死了只有在呢，
    /// 我需要输入其他东西就不行了。」
    ///
    /// **一件只能产出一个结果的「零件」，对她来说等于没有。**
    /// 同理那件「抱个东西」——它只能抱一个白方块，
    /// 换不了别的，所以**整件删了**（她定的：
    /// 「无法 diy 的就不要了」）。
    static func sayPart(_ words: String) -> Part {
        Part(name: "一行字",
             svg: "<text class=\"say\" x=\"160\" y=\"-34\">" + escape(words) + "</text>",
             css: """
             .say {
               fill: #4A4038;
               font-size: 34px;
               font-weight: 600;
               text-anchor: middle;
             }
             """)
    }

    /// 往 SVG 里塞文字之前必须转义。
    ///
    /// ⚠️ 她要是打了一个 `<` 或者 `&`，
    /// **整张 SVG 当场变成废文件**，预览一片空白。
    /// 能让她自由输入的地方，就得把输入当成不可信的。
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: 拼成一张能渲染的网页

    /// 预览和导出用的是**同一份** HTML，所见即所得。
    ///
    /// 背景留透明——表情包贴到聊天里不该带一块白底。
    static func page(svg: String, css: String, scale: Double = 1) -> String {
        // ⚠️ **尺寸不许再写死像素。**
        //
        // 上一版是 `width: 380px; height: 320px`，而预览那块 WebView
        // 只有 260 点高——WKWebView 不会把页面缩下去，它就是**裁掉**。
        // 于是任何跑到 viewBox 外面的东西（头顶闪光在 y=-26、
        // 那行字在 y=-34）都被切在屏幕外。
        //
        // 她的原话：「我在零件这边点击加一行字，上面的字在屏幕外面，
        // 我甚至不能缩小看清全部。」——**缩小也没用，因为它不是被缩掉的，
        // 是被裁掉的。**「头顶闪光」其实一直也是隐形的，只是没人发现。
        //
        // 现在按百分比铺：页面永远等于容器那么大，SVG 占八成、
        // 剩下两成留给溢出的内容（`overflow: visible` 让它画得出来）。
        // 容器多大都不会裁。
        //
        // `scale` 这个参数留着不动——导出那条路要用它决定倍率。
        _ = scale
        return """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body {
          margin: 0; padding: 0;
          background: transparent;
          width: 100%; height: 100%;
          display: flex; align-items: center; justify-content: center;
          overflow: hidden;
        }
        svg {
          width: 80%; height: 80%;
          overflow: visible;
        }
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

    /// **只有画的那一张，不带身子。**
    ///
    /// 她说「顶上预览不该老是 clawd 的身子」——
    /// 她想画的不一定是 clawd：一朵花、一杯奶茶、一句话，
    /// 底下压着那个身子的话，那些东西永远只是「贴在 clawd 上的贴纸」。
    /// 尺寸还是同一个 viewBox，导出、存进表情库那条路一个字都不用改。
    static func bare(_ inner: String) -> String {
        "<svg viewBox=\"0 0 320 230\" xmlns=\"http://www.w3.org/2000/svg\">\n"
            + "  <g id=\"clawd\">\n    <g id=\"face\">\n"
            + inner
            + "\n    </g>\n  </g>\n</svg>"
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

    // MARK: 放上去的零件要能挪

    /// 每一件零件的坐标都是**照 clawd 的身子定死的**
    /// （腮红在 x=50,y=92，因为那儿正好是他的脸颊）。
    ///
    /// 她画的不一定是 clawd——画一朵花、一杯奶茶，
    /// 腮红照样落在「clawd 脸颊」那个位置上，落在哪儿全看运气。
    ///
    /// 所以放上去的零件统统包一层 `<g id="pN" data-name="腮红" transform="…">`：
    /// **位置变成一个能改的属性**，而不是写死在坐标里。
    ///
    /// ⚠️ 为什么不另存一份「零件清单」在 Swift 里：
    /// 「图形」那一页她能直接改 SVG。**存两份就一定会对不上**——
    /// 她手改了一处，Swift 那份还以为是原来的样子。
    /// 现在 SVG 本身就是唯一的那份账，要什么就从它身上读。
    struct Placed: Identifiable {
        let id: String
        let name: String
    }

    /// 包一层，变成能挪的
    static func placed(_ inner: String, name: String, id: String) -> String {
        "<g id=\"" + id + "\" data-name=\"" + escape(name) + "\""
            + " transform=\"translate(0,0) scale(1)\">"
            + inner
            + "</g>"
    }

    /// 下一件该叫什么 id。**扫现有的取最大再加一**——
    /// 不这么算的话，删掉中间一件再放一件就会撞 id
    static func nextPlacedID(in svg: String) -> String {
        var maxN = 0
        var rest = Substring(svg)
        while let r = rest.range(of: "id=\"p") {
            let after = rest[r.upperBound...]
            let digits = after.prefix { $0.isNumber }
            if let n = Int(digits) { maxN = max(maxN, n) }
            rest = after
        }
        return "p\(maxN + 1)"
    }

    /// 现在放着哪几件
    static func placedList(in svg: String) -> [Placed] {
        var out: [Placed] = []
        var rest = Substring(svg)
        while let open = rest.range(of: "<g id=\"p") {
            let after = rest[open.upperBound...]
            let digits = String(after.prefix { $0.isNumber })
            guard !digits.isEmpty else { rest = after; continue }
            var name = "零件"
            if let n = after.range(of: "data-name=\""),
               let e = after.range(of: "\"", range: n.upperBound..<after.endIndex) {
                name = unescape(String(after[n.upperBound..<e.lowerBound]))
            }
            out.append(Placed(id: "p" + digits, name: name))
            rest = after
        }
        return out
    }

    /// 读某一件现在挪到哪儿、放大了多少
    static func transformOf(_ id: String, in svg: String) -> (dx: Double, dy: Double, scale: Double) {
        guard let g = svg.range(of: "<g id=\"" + id + "\""),
              let t = svg.range(of: "transform=\"", range: g.upperBound..<svg.endIndex),
              let e = svg.range(of: "\"", range: t.upperBound..<svg.endIndex)
        else { return (0, 0, 1) }
        return parse(String(svg[t.upperBound..<e.lowerBound]))
    }

    /// `translate(12,-30) scale(1.2)` → 三个数
    static func parse(_ transform: String) -> (dx: Double, dy: Double, scale: Double) {
        func number(after key: String) -> [Double] {
            guard let r = transform.range(of: key + "(") ,
                  let e = transform.range(of: ")", range: r.upperBound..<transform.endIndex)
            else { return [] }
            return transform[r.upperBound..<e.lowerBound]
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        let t = number(after: "translate")
        let s = number(after: "scale")
        return (t.count > 0 ? t[0] : 0,
                t.count > 1 ? t[1] : 0,
                s.first ?? 1)
    }

    static func transformText(dx: Double, dy: Double, scale: Double) -> String {
        String(format: "translate(%.1f,%.1f) scale(%.2f)", dx, dy, scale)
    }

    /// 把某一件挪到新位置
    static func move(_ id: String, dx: Double, dy: Double, scale: Double,
                     in svg: String) -> String {
        guard let g = svg.range(of: "<g id=\"" + id + "\""),
              let t = svg.range(of: "transform=\"", range: g.upperBound..<svg.endIndex),
              let e = svg.range(of: "\"", range: t.upperBound..<svg.endIndex)
        else { return svg }
        return svg.replacingCharacters(in: t.upperBound..<e.lowerBound,
                                       with: transformText(dx: dx, dy: dy, scale: scale))
    }

    /// 把某一件整个拿掉。
    ///
    /// ⚠️ 零件里面不会再有 `<g>`，所以找**紧接着的第一个** `</g>` 就是它的收尾。
    /// 哪天零件里出现了嵌套的组，这儿要改成数层数。
    static func removePlaced(_ id: String, from svg: String) -> String {
        guard let open = svg.range(of: "<g id=\"" + id + "\""),
              let close = svg.range(of: "</g>", range: open.upperBound..<svg.endIndex)
        else { return svg }
        return svg.replacingCharacters(in: open.lowerBound..<close.upperBound, with: "")
    }

    /// `escape` 的反向。读 `data-name` 的时候用
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
