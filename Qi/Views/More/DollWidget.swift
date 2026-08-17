import SwiftUI
import WebKit

/// 娃娃那张能点的卡片。
///
/// 这是 gist 里那个 widget 的本地版：**HTML 只负责画和传操作**，
/// 一个字的状态都不存在它里面（原文档反复强调的那条：
/// 「服务器保存游戏事实，Widget 只负责展示和传操作」）。
///
/// 桥是 `window.qi.act(action, args)`：
/// 原版走 `window.openai.callTool`，这版走 WKWebView 的消息通道，
/// 一样是「点一下 → 那边改状态 → 回一份完整快照 → 原地重画」。
///
/// 同一个 View 用在两个地方：
/// · 游戏里的娃娃房（整页）
/// · 聊天气泡里的卡片（`inline: true`，矮一点、少两排按钮）
///
/// **两边是同一份状态**——在聊天里点完，进娃娃房看到的就是刚才那个样子。
struct DollWebView: UIViewRepresentable {

    var inline: Bool = false
    var accentHex: String
    var dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        // 带回复的消息通道：JS 那边 await 得到一份完整快照
        ucc.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "doll")
        config.userContentController = ucc

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.bounces = false
        web.scrollView.isScrollEnabled = !inline
        web.isOpaque = false
        web.backgroundColor = .clear
        context.coordinator.web = web
        web.loadHTMLString(DollWidget.page(inline: inline, accentHex: accentHex, dark: dark),
                           baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // 他在聊天里动了娃娃、或者另一边点了什么——把新快照推进去重画。
        // **推的是完整快照**，不是增量（原文档第 13 节头一个坑）。
        let snap = DollStore.shared.snapshotJSON()
        if context.coordinator.lastPushed != snap {
            context.coordinator.lastPushed = snap
            web.evaluateJavaScript("window.applySnapshot && window.applySnapshot(\(snap));")
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply {
        weak var web: WKWebView?
        var lastPushed: String = ""

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            let body = message.body as? [String: Any] ?? [:]
            let action = (body["action"] as? String) ?? ""
            // 状态那边是 @MainActor 的，绕一趟主线程再回话
            Task { @MainActor in
                // ready 只是要一份当前状态，不改任何东西
                if !action.isEmpty && action != "ready" {
                    _ = DollStore.shared.act(action,
                                             zone: body["zone"] as? String,
                                             pose: body["pose"] as? String,
                                             camera: body["camera"] as? String,
                                             narration: body["narration"] as? String)
                }
                let snap = DollStore.shared.snapshotJSON()
                self.lastPushed = snap
                replyHandler(snap, nil)
            }
        }
    }
}

// MARK: - 那张 HTML

enum DollWidget {

    /// 整页。用原始字符串写（`#"""..."""#`），里面的引号和反斜杠都不用转义——
    /// **别用脚本改这段**，`\n` 会被写成真换行、整个字符串就断了（这坑踩过两次）。
    static func page(inline: Bool, accentHex: String, dark: Bool) -> String {
        let css = #"""
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        body {
          margin: 0; padding: 10px;
          font: 13px/1.5 -apple-system, "PingFang SC", sans-serif;
          color: var(--ink); background: transparent;
          user-select: none;
        }
        .stage {
          position: relative; width: 100%; aspect-ratio: 1 / 1;
          max-height: var(--stage-max);
          margin: 0 auto; border-radius: 18px; overflow: hidden;
          background: linear-gradient(160deg, var(--bg1), var(--bg2));
        }
        .stage svg { width: 100%; height: 100%; display: block; }
        .hotspot {
          position: absolute; border: 0; padding: 0; margin: 0;
          background: transparent; border-radius: 50%;
          display: flex; align-items: center; justify-content: center;
          transition: transform .18s ease;
        }
        /* 平时露一个小点，让她一眼看出哪儿能碰 */
        .hotspot .dot {
          width: 9px; height: 9px; border-radius: 50%;
          background: var(--accent); opacity: .45;
          transition: all .2s ease;
        }
        .hotspot .tag {
          position: absolute; top: 100%; margin-top: 1px;
          font-size: 9px; font-weight: 400; color: var(--muted);
          opacity: 0; transition: opacity .2s ease; white-space: nowrap;
        }
        .hotspot.touched { transform: scale(1.25); }
        .hotspot.touched .dot { opacity: 1; width: 26px; height: 26px; }
        .hotspot.touched .tag { opacity: 1; }
        /* 「哪儿能点」按下去：全部标出来 */
        .hint .hotspot .dot { opacity: .95; width: 16px; height: 16px; }
        .hint .hotspot .tag { opacity: 1; }
        /* 刚发生的那一句，压在画面底下 */
        .said {
          position: absolute; left: 10px; right: 10px; bottom: 10px;
          font-size: 12px; line-height: 1.45; color: var(--ink);
          background: var(--fill); border-radius: 12px; padding: 8px 10px;
          backdrop-filter: blur(6px);
        }
        .said:empty { display: none; }
        .row { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
        button.chip {
          font: 12px/1 -apple-system, "PingFang SC", sans-serif;
          padding: 8px 11px; min-height: 34px;
          border-radius: 999px; border: 0;
          color: var(--ink); background: var(--fill);
        }
        button.chip.on { background: var(--accent); color: #fff; }
        .bars { margin-top: 10px; display: grid; gap: 5px; }
        .bar { display: flex; align-items: center; gap: 7px; font-size: 11px; }
        .bar span.k { width: 30px; color: var(--muted); }
        .bar .track { flex: 1; height: 5px; border-radius: 3px; background: var(--fill); overflow: hidden; }
        .bar .fill { height: 100%; background: var(--accent); border-radius: 3px; transition: width .3s ease; }
        .bar span.v { width: 26px; text-align: right; color: var(--muted); font-variant-numeric: tabular-nums; }
        .shots { margin-top: 10px; display: grid; gap: 4px; }
        .shots p { margin: 0; font-size: 12px; color: var(--soft); }
        .shots p:last-child { color: var(--ink); }
        .meta { margin-top: 8px; font-size: 10px; color: var(--muted); }
        @media (prefers-reduced-motion: reduce) {
          .hotspot, .bar .fill { transition: none; }
        }
        """#

        let js = #"""
        // 桥。原版是 window.openai.callTool，这版是 App 的消息通道，
        // 形状一样：传一个动作，拿回一份完整快照。
        window.qi = {
          act: function (action, args) {
            return window.webkit.messageHandlers.doll.postMessage(
              Object.assign({ action: action }, args || {})
            );
          }
        };

        var S = null;

        // 四个姿势。
        //
        // 上一版是几根线条 + 一个圆脑袋，她的原话是「有点太粗糙了，
        // 不太看得懂发生了什么」——**看不懂的一半原因是那根本不像个人**。
        // 这一版还是纯 SVG（手上没有立绘素材），但把该有的都画出来：
        // 头发、脸（眼睛/腮红/嘴）、身子是件连衣裙、四肢有粗细。
        // 身体数值也画进去：脸红跟着「热」走、抖跟着「抖」走。
        function figure(pose, camera, body) {
          var warm = Math.min(1, (body.warmth || 0) / 70);
          var poses = {
            sit:   { dress: "M100,112 L74,196 L126,196 Z", legs: "M88,196 C84,222 76,236 66,248 M112,196 C116,222 124,236 134,248", arms: "M84,124 C70,142 64,158 62,174 M116,124 C130,142 136,158 138,174", head: 0 },
            lean:  { dress: "M104,112 L84,196 L134,196 Z", legs: "M96,196 C90,224 82,238 72,250 M120,196 C126,220 136,236 148,246", arms: "M88,124 C72,136 62,144 54,150 M120,124 C134,144 140,160 142,178", head: -8 },
            curl:  { dress: "M100,114 L80,186 L124,186 Z", legs: "M90,186 C74,196 64,210 62,226 M112,186 C120,202 122,216 118,232", arms: "M86,126 C74,136 68,148 70,162 M114,126 C126,136 130,148 128,162", head: 10 },
            reach: { dress: "M100,112 L74,196 L126,196 Z", legs: "M88,196 C84,224 76,238 68,250 M112,196 C118,222 126,238 134,248", arms: "M84,122 C68,110 58,98 52,84 M116,124 C130,142 136,158 138,176", head: -4 }
          };
          var p = poses[pose] || poses.sit;
          // 机位：整体缩放和平移，不是换素材
          var cam = { front: "translate(0,0) scale(1)", side: "translate(10,0) scale(1) rotate(-6 100 150)",
                      close: "translate(0,-30) scale(1.34)", top: "translate(0,10) scale(0.94) rotate(3 100 150)" };
          var t = cam[camera] || cam.front;
          // 眼睛：热到一定程度就眯起来
          var eyes = warm > 0.55
            ? '<path d="M86,72 q6,-5 12,0" stroke="var(--ink)" stroke-width="3" fill="none" stroke-linecap="round"/>' +
              '<path d="M102,72 q6,-5 12,0" stroke="var(--ink)" stroke-width="3" fill="none" stroke-linecap="round"/>'
            : '<circle cx="92" cy="72" r="3.2" fill="var(--ink)"/><circle cx="108" cy="72" r="3.2" fill="var(--ink)"/>';
          return '<svg viewBox="0 0 200 280" xmlns="http://www.w3.org/2000/svg">' +
            '<g transform="' + t + '">' +
              // 腿和胳膊：有粗细，收笔是圆的
              '<g fill="none" stroke="var(--skin2)" stroke-width="11" stroke-linecap="round">' +
                '<path d="' + p.legs + '"/></g>' +
              '<g fill="none" stroke="var(--skin2)" stroke-width="9" stroke-linecap="round">' +
                '<path d="' + p.arms + '"/></g>' +
              // 连衣裙
              '<path d="' + p.dress + '" fill="var(--accent)" opacity=".85"/>' +
              // 脖子和头
              '<rect x="94" y="96" width="12" height="14" rx="5" fill="var(--skin2)"/>' +
              '<g transform="rotate(' + p.head + ' 100 78)">' +
                '<circle cx="100" cy="76" r="24" fill="var(--skin)"/>' +
                eyes +
                '<circle cx="82" cy="82" r="6" fill="#FF8FA0" opacity="' + (0.18 + warm * 0.5).toFixed(2) + '"/>' +
                '<circle cx="118" cy="82" r="6" fill="#FF8FA0" opacity="' + (0.18 + warm * 0.5).toFixed(2) + '"/>' +
                '<path d="M95,88 q5,4 10,0" stroke="var(--ink)" stroke-width="2.4" fill="none" stroke-linecap="round"/>' +
                // 头发：一顶盖过去，两侧垂下来
                '<path d="M74,74 C74,44 126,44 126,74 L120,66 C112,58 88,58 80,66 Z" fill="var(--hair)"/>' +
                '<path d="M76,72 C70,92 72,104 76,110" stroke="var(--hair)" stroke-width="8" fill="none" stroke-linecap="round"/>' +
                '<path d="M124,72 C130,92 128,104 124,110" stroke="var(--hair)" stroke-width="8" fill="none" stroke-linecap="round"/>' +
              '</g>' +
            '</g></svg>';
        }

        // 热区。位置是百分比，跟着舞台缩放走；
        // 平时不显示，点下去闪一下就收——原文档第 9 节那套。
        var ZONE_XY = {
          hair:  [50, 20], cheek: [58, 27], neck: [50, 35],
          hand:  [30, 45], waist: [50, 60], knee: [42, 76]
        };

        function render(s) {
          S = s;
          document.getElementById("art").innerHTML = figure(s.pose, s.camera, s.body);

          var hs = document.getElementById("spots");
          if (hs.childElementCount !== s.zones.length) {
            hs.innerHTML = "";
            s.zones.forEach(function (z) {
              var xy = ZONE_XY[z.id] || [50, 50];
              var b = document.createElement("button");
              b.className = "hotspot";
              b.style.left = "calc(" + xy[0] + "% - 26px)";
              b.style.top = "calc(" + xy[1] + "% - 26px)";
              b.style.width = "52px"; b.style.height = "52px";
              b.setAttribute("aria-label", z.label);
              // 能点的地方**默认就露一个小点**。
              // 上一版全透明，她说「不太看得懂发生了什么」——
              // 一半是因为根本看不出哪儿能点。
              b.innerHTML = '<i class="dot"></i><b class="tag">' + z.label + '</b>';
              b.onclick = function () {
                b.classList.add("touched");
                setTimeout(function () { b.classList.remove("touched"); }, 700);
                act("touch_zone", { zone: z.id });
              };
              hs.appendChild(b);
            });
          }

          fillRow("poses", s.poses, s.pose, function (id) { act("change_pose", { pose: id }); });
          fillRow("cameras", s.cameras, s.camera, function (id) { act("change_camera", { camera: id }); });

          var b = s.body;
          setBar("sen", "敏感", b.sensitivity);
          setBar("war", "热", b.warmth);
          setBar("tre", "抖", b.tremor);
          setBar("voi", "声", b.voice);
          setBar("int", "强度", s.intensity);

          // 最新那一句压在画面上，剩下的往下排
          var all = s.take.shots || [];
          document.getElementById("said").textContent = all.length ? all[all.length - 1] : "";

          var shots = document.getElementById("shots");
          shots.innerHTML = "";
          all.slice(-4, -1).forEach(function (t) {
            var p = document.createElement("p"); p.textContent = t; shots.appendChild(p);
          });

          document.getElementById("meta").textContent =
            s.name + "· " + s.take.title + "· 节奏 " + s.rhythm +
            (s.poseLocked ? "· 姿势锁着" : "") +
            (s.archiveCount ? "· 收着 " + s.archiveCount + " 段" : "");

          var lock = document.getElementById("lockbtn");
          if (lock) lock.className = "chip" + (s.poseLocked ? " on" : "");
        }

        function fillRow(id, list, current, onPick) {
          var row = document.getElementById(id);
          if (!row) return;
          if (row.childElementCount !== list.length) {
            row.innerHTML = "";
            list.forEach(function (item) {
              var b = document.createElement("button");
              b.textContent = item.label;
              b.dataset.id = item.id;
              b.onclick = function () { onPick(item.id); };
              row.appendChild(b);
            });
          }
          Array.prototype.forEach.call(row.children, function (b) {
            b.className = "chip" + (b.dataset.id === current ? " on" : "");
          });
        }

        function setBar(id, label, v) {
          var el = document.getElementById("b_" + id);
          if (!el) return;
          el.querySelector(".fill").style.width = Math.max(0, Math.min(100, v)) + "%";
          el.querySelector(".v").textContent = v;
        }

        async function act(action, args) {
          var snap = await window.qi.act(action, args);
          if (typeof snap === "string") { snap = JSON.parse(snap); }
          render(snap);
        }

        // App 那边主动推进来的（比如他在聊天里动了娃娃）
        window.applySnapshot = function (s) {
          if (!S || s.version !== S.version) { render(s); }
        };

        act("ready");
        """#

        let stageMax = inline ? "230px" : "420px"
        let ink = dark ? "#EDEDED" : "#2B2B2B"
        let soft = dark ? "#B8B8B8" : "#5A5A5A"
        let muted = dark ? "#8A8A8A" : "#8E8E8E"
        let fill = dark ? "rgba(255,255,255,.10)" : "rgba(0,0,0,.06)"
        let bg1 = dark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.55)"
        let bg2 = dark ? "rgba(255,255,255,.02)" : "rgba(255,255,255,.18)"
        let line = dark ? "rgba(255,255,255,.55)" : "rgba(60,50,50,.45)"
        let skin = dark ? "rgba(255,225,215,.22)" : "rgba(255,225,215,.75)"
        let skin2 = dark ? "rgba(255,225,215,.16)" : "rgba(255,225,215,.55)"

        // 整页比卡片多两排：锁姿势、收起来、重新来过。
        // 卡片里不放「重新来过」——手一滑在聊天里把一整段清了，太亏。
        let extraRow = inline
            ? #"<button class="chip" onclick="act('save')">收起来</button>"#
            : #"""
              <button class="chip" id="lockbtn" onclick="act('lock')">锁住姿势</button>
              <button class="chip" onclick="act('save')">收起这一段</button>
              <button class="chip" onclick="act('reset')">重新来过</button>
              """#

        return #"""
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root {
          --accent: \#(accentHex);
          --ink: \#(ink); --soft: \#(soft); --muted: \#(muted);
          --fill: \#(fill); --bg1: \#(bg1); --bg2: \#(bg2);
          --line: \#(line); --skin: \#(skin); --skin2: \#(skin2);
          --hair: \#(accentHex);
          --stage-max: \#(stageMax);
        }
        \#(css)
        </style></head><body>
          <div class="stage" id="stage">
            <div id="art"></div>
            <div id="spots"></div>
            <!-- 刚刚发生的那一句，直接压在画面上。
                 底下那三行小字她说看不出发生了什么，那就把最新那句摆到画里 -->
            <div class="said" id="said"></div>
          </div>
          <div class="row" id="poses"></div>
          <div class="row" id="cameras"></div>
          <div class="row">
            <button class="chip" onclick="act('slower')">慢一点</button>
            <button class="chip" onclick="act('faster')">快一点</button>
            <button class="chip" onclick="document.getElementById('stage').classList.toggle('hint')">哪儿能点</button>
            \#(extraRow)
          </div>
          <div class="bars">
            <div class="bar" id="b_sen"><span class="k">敏感</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_war"><span class="k">热</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_tre"><span class="k">抖</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_voi"><span class="k">声</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_int"><span class="k">强度</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
          </div>
          <div class="shots" id="shots"></div>
          <div class="meta" id="meta"></div>
        <script>
        \#(js)
        </script></body></html>
        """#
    }
}
