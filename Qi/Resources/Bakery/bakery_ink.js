// 甜品屋的画风：同一套形状，三种画法，可以随时切换。
// - story  绘本水彩：手抖一点的暖棕线稿、水彩晕开的深浅、纸纹、边缘积色、金色和白色的闪光
// - candy  糖果厚描边：粗粗的深棕描边、明亮的色块、一块硬边阴影、一点高光、白色小星星
// - paper  剪纸扁平：多边形色块、没有描边、错开一点的纸片阴影、纸张颗粒、碎纸屑
// 所有东西都先算成一串点（形状），再交给 paint 按当前画风上色，所以甜点、装饰、盘子、花边都能跟着换。
'use strict';

const INK = (() => {
  const TAU = Math.PI * 2;
  let STYLE = 'story';
  const style = () => STYLE;
  const setStyle = (s) => { STYLE = s; };
  // #rrggbb 和 rgba(...) 两种写法都认（算出来的颜色还会再拿去加深变浅）
  const hex = (h) => { if (h[0] !== '#') { const m = h.match(/[\d.]+/g) || [0, 0, 0]; return [+m[0], +m[1], +m[2]]; } const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const rgba = (c, a = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;
  // 加深 / 变浅；原来是半透明的（玻璃）就保留它的透明度
  const alphaOf = (h) => { if (h[0] === '#') return 1; const m = h.match(/[\d.]+/g); return m && m.length > 3 ? +m[3] : 1; };
  const tone = (h, k, a = 1) => { const c = hex(h); return rgba(k >= 0 ? c.map((v) => v + (255 - v) * k) : c.map((v) => v * (1 + k)), a * alphaOf(h)); };
  const rng = (seed) => { let s = ((seed * 9301 + 49297) % 233280 + 233280) % 233280 || 1; return () => (s = (s * 9301 + 49297) % 233280) / 233280; };

  // 纸纹：每个画布做一次
  const grains = new WeakMap();
  function grain(g) {
    if (grains.has(g)) return grains.get(g);
    const c = document.createElement('canvas'); c.width = c.height = 160;
    const x = c.getContext('2d'), id = x.createImageData(160, 160), R = rng(17);
    for (let i = 0; i < id.data.length; i += 4) { const v = 175 + R() * 80; id.data[i] = v; id.data[i + 1] = v * .98; id.data[i + 2] = v * .95; id.data[i + 3] = 255; }
    x.putImageData(id, 0, 0);
    const p = g.createPattern(c, 'repeat'); grains.set(g, p); return p;
  }

  // ———— 形状 ————
  // 椭圆上的一串点（剪纸风少几个点、角度抖一抖，就成了剪出来的多边形）
  function ell(cx, cy, rx, ry, a0 = 0, a1 = TAU, n = 0, seed = 1) {
    const paper = STYLE === 'paper', full = Math.abs(a1 - a0) >= TAU - 1e-6;
    const N = n || (paper ? Math.max(5, Math.round(Math.abs(a1 - a0) / TAU * 11)) : Math.max(8, Math.round(Math.abs(a1 - a0) / TAU * 44)));
    const R = rng(seed), out = [];
    for (let i = 0; i <= (full ? N - 1 : N); i++) {
      const a = a0 + (a1 - a0) * i / N + (paper ? (R() - .5) * .18 : 0), k = paper ? 1 + (R() - .5) * .06 : 1;
      out.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]);
    }
    return out;
  }
  // 圆柱的侧面（前半圈）：顶上那个椭圆的前半弧 + 底下的前半弧
  function side(cx, ty, rx, ry, h, seed = 1) {
    const bot = ell(cx, ty + h, rx, ry, 0, Math.PI, 0, seed), top = ell(cx, ty, rx, ry, Math.PI, 0, 0, seed + 3);
    return [...bot, ...top];
  }
  function trace(g, pts, closed = true, wob = 0, seed = 1) {
    g.beginPath();
    if (!pts.length) return;
    if (STYLE === 'paper') { pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); if (closed) g.closePath(); return; }
    const R = rng(seed), P = wob ? pts.map(([x, y]) => [x + (R() - .5) * wob, y + (R() - .5) * wob]) : pts;
    // 四个点以内的是方块、三角、条子：直边（磨圆会变成椭圆）
    if (P.length <= 4) { P.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); if (closed) g.closePath(); return; }
    const n = P.length;
    if (n < 3) { P.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); return; }
    const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    if (closed) {
      const m0 = mid(P[n - 1], P[0]); g.moveTo(m0[0], m0[1]);
      for (let i = 0; i < n; i++) { const m = mid(P[i], P[(i + 1) % n]); g.quadraticCurveTo(P[i][0], P[i][1], m[0], m[1]); }
      g.closePath();
    } else {
      g.moveTo(P[0][0], P[0][1]);
      for (let i = 1; i < n - 1; i++) { const m = mid(P[i], P[i + 1]); g.quadraticCurveTo(P[i][0], P[i][1], m[0], m[1]); }
      g.lineTo(P[n - 1][0], P[n - 1][1]);
    }
  }
  const bbox = (pts) => { let a = 1e9, b = 1e9, c = -1e9, d = -1e9; for (const [x, y] of pts) { a = Math.min(a, x); b = Math.min(b, y); c = Math.max(c, x); d = Math.max(d, y); } return { x: a, y: b, w: c - a, h: d - b }; };

  // ———— 上色：一个形状按当前画风画出来 ————
  // lw：这块东西多大（线条、阴影跟着它缩放）；line：要不要描边；gloss：亮面（果子、果冻）；flat：不要晕染（小零件）
  function paint(g, pts, col, { lw = 1, line = true, gloss = false, flat = false, seed = 1, alpha = 1 } = {}) {
    if (!pts || pts.length < 2) return;
    const b = bbox(pts);
    g.save(); g.globalAlpha *= alpha;
    if (STYLE === 'paper') {
      // 纸片的影子错开一点
      g.save(); g.translate(1.6 * lw, 2.4 * lw); trace(g, pts); g.fillStyle = 'rgba(80,45,30,.16)'; g.fill(); g.restore();
      trace(g, pts); g.fillStyle = col; g.fill();
      g.save(); g.clip();
      // 一刀切出来的暗面：右下那一半深一点
      g.beginPath(); g.moveTo(b.x + b.w * .62, b.y - 2); g.lineTo(b.x + b.w + 2, b.y - 2); g.lineTo(b.x + b.w + 2, b.y + b.h + 2); g.lineTo(b.x + b.w * .25, b.y + b.h + 2); g.closePath();
      g.fillStyle = tone(col, -.1); g.fill();
      if (gloss) { g.beginPath(); g.moveTo(b.x + b.w * .2, b.y + b.h * .18); g.lineTo(b.x + b.w * .38, b.y + b.h * .12); g.lineTo(b.x + b.w * .3, b.y + b.h * .32); g.fillStyle = 'rgba(255,255,255,.6)'; g.fill(); }
      if (!flat) { g.globalCompositeOperation = 'multiply'; g.globalAlpha = .22; g.fillStyle = grain(g); g.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4); }
      g.restore();
    } else if (STYLE === 'candy') {
      trace(g, pts); g.fillStyle = col; g.fill();
      g.save(); g.clip();
      // 硬边阴影：同一个形状往左上挪一点再填亮色，剩下右下一道月牙是暗的
      g.fillStyle = tone(col, -.16); g.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4);
      g.translate(-b.w * .07 - 1.2 * lw, -b.h * .09 - 1.2 * lw); trace(g, pts); g.fillStyle = col; g.fill();
      g.setTransform(g.getTransform());
      g.restore();
      g.save(); trace(g, pts); g.clip();
      g.fillStyle = 'rgba(255,255,255,.75)';
      if (!flat) { g.beginPath(); g.ellipse(b.x + b.w * .28, b.y + b.h * .26, Math.max(1, b.w * .1), Math.max(.8, b.h * .06), -.5, 0, TAU); g.fill(); g.beginPath(); g.arc(b.x + b.w * .42, b.y + b.h * .2, Math.max(.8, b.w * .03), 0, TAU); g.fill(); }
      g.restore();
      if (line) { trace(g, pts); g.lineJoin = 'round'; g.strokeStyle = '#5b3b30'; g.lineWidth = 2.1 * lw; g.stroke(); }
    } else {
      // 绘本水彩
      trace(g, pts, true, .7 * lw, seed); g.fillStyle = col; g.fill();
      g.save(); g.clip();
      if (!flat) {
        const R = rng(seed + 11);
        // 晕开的深浅：几团半透明的颜色
        for (let i = 0; i < 3; i++) { const x = b.x + R() * b.w, y = b.y + R() * b.h, r = Math.max(b.w, b.h) * (.3 + R() * .4); const gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, tone(col, i % 2 ? .22 : -.14, .45)); gr.addColorStop(1, tone(col, 0, 0)); g.fillStyle = gr; g.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4); }
        // 左上来的光、右下积一点色
        const lg = g.createLinearGradient(b.x, b.y, b.x + b.w, b.y + b.h); lg.addColorStop(0, 'rgba(255,250,240,.38)'); lg.addColorStop(.55, 'rgba(255,250,240,0)'); lg.addColorStop(1, tone(col, -.3, .35));
        g.fillStyle = lg; g.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4);
        // 边上积的那一圈颜色（水彩干了以后边缘深一点）
        trace(g, pts, true, .7 * lw, seed); g.strokeStyle = tone(col, -.22, .35); g.lineWidth = 3.2 * lw; g.stroke();
        g.globalCompositeOperation = 'multiply'; g.globalAlpha = .3; g.fillStyle = grain(g); g.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4);
        g.globalCompositeOperation = 'source-over'; g.globalAlpha = 1;
      }
      if (gloss) { g.fillStyle = 'rgba(255,255,255,.8)'; g.beginPath(); g.ellipse(b.x + b.w * .3, b.y + b.h * .28, Math.max(.8, b.w * .09), Math.max(.6, b.h * .05), -.6, 0, TAU); g.fill(); g.beginPath(); g.arc(b.x + b.w * .44, b.y + b.h * .22, Math.max(.6, b.w * .025), 0, TAU); g.fill(); }
      g.restore();
      if (line) { trace(g, pts, true, .9 * lw, seed + 5); g.lineJoin = 'round'; g.lineCap = 'round'; g.strokeStyle = tone(col, -.55, .85); g.lineWidth = 1.05 * lw; g.stroke(); }
    }
    g.restore();
  }
  // 一道线（叶脉、奶油的纹路、包装绳）
  function stroke(g, pts, col, w = 1, closed = false) {
    if (STYLE === 'paper') return;
    trace(g, pts, closed, STYLE === 'story' ? .5 : 0, 3);
    g.lineCap = 'round'; g.lineJoin = 'round';
    g.strokeStyle = STYLE === 'candy' ? '#5b3b30' : col; g.lineWidth = STYLE === 'candy' ? w * 1.6 : w; g.stroke();
  }
  // 闪光：绘本是金白两色的四角星，糖果是白色小星星和圆点，剪纸是一片片碎纸屑
  function sparkle(g, x, y, r, i = 0) {
    g.save(); g.translate(x, y);
    if (STYLE === 'paper') {
      g.rotate(i * 1.3); g.fillStyle = ['#f3c4cf', '#f1dca0', '#a9c9d8', '#fbf7f1'][i % 4];
      g.beginPath(); g.moveTo(-r, -r * .3); g.lineTo(r * .6, -r * .8); g.lineTo(r, r * .4); g.lineTo(-r * .4, r * .7); g.closePath(); g.fill();
    } else {
      const col = STYLE === 'candy' ? '#ffffff' : (i % 2 ? '#f6e3a4' : '#ffffff');
      g.fillStyle = col; g.beginPath();
      for (let k = 0; k < 8; k++) { const a = k / 8 * TAU, rr = k % 2 ? r * .22 : r; g.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); }
      g.closePath(); g.fill();
      if (STYLE === 'candy') { g.strokeStyle = '#5b3b30'; g.lineWidth = .9; g.stroke(); }
    }
    g.restore();
  }

  // ———— 装饰 ————
  const TOP = {
    strawberry(g, k, s) {
      const pts = []; for (let i = 0; i <= 30; i++) { const t = i / 30 * TAU, x = Math.sin(t), y = -Math.cos(t); pts.push([x * k * .46 * (1 - .25 * Math.max(0, y)), y * k * .52 + (y > 0 ? y * y * k * .12 : 0)]); }
      paint(g, pts.map(([x, y]) => [x, -y]), '#d9566b', { lw: k / 26, gloss: true, seed: s });
      if (STYLE !== 'paper') { g.fillStyle = '#f6dc8e'; for (const [a, b] of [[-.2, -.05], [.18, -.1], [0, .15], [-.28, .2], [.27, .18], [-.08, .36], [.1, .36], [-.3, -.22], [.3, -.22]]) { g.beginPath(); g.ellipse(a * k, b * k, k * .03, k * .045, 0, 0, TAU); g.fill(); } }
      else { g.fillStyle = '#f6dc8e'; for (const [a, b] of [[-.18, 0], [.15, -.08], [0, .2], [.2, .2]]) { g.fillRect(a * k - 1, b * k - 1, k * .06, k * .06); } }
      for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + (i - 2) * .55; paint(g, [[0, -k * .4], [Math.cos(a - .25) * k * .22, -k * .4 + Math.sin(a - .25) * k * .14], [Math.cos(a) * k * .3, -k * .4 + Math.sin(a) * k * .2 + k * .12], [Math.cos(a + .25) * k * .22, -k * .4 + Math.sin(a + .25) * k * .14]], '#7da35f', { lw: k / 40, flat: true, seed: s + i }); }
    },
    blueberry(g, k, s) {
      paint(g, ell(0, 0, k * .3, k * .3, 0, TAU, 0, s), '#4d5a8c', { lw: k / 30, gloss: true, seed: s });
      if (STYLE !== 'paper') { g.fillStyle = 'rgba(210,215,240,.35)'; g.beginPath(); g.arc(-k * .06, -k * .08, k * .17, 0, TAU); g.fill(); }
      g.strokeStyle = STYLE === 'candy' ? '#5b3b30' : '#2a2f50'; g.lineWidth = k * .045; for (let i = 0; i < 5; i++) { const a = i / 5 * TAU; g.beginPath(); g.moveTo(0, -k * .05); g.lineTo(Math.cos(a) * k * .09, -k * .05 + Math.sin(a) * k * .09); g.stroke(); }
    },
    halfberry(g, k, s) {
      const outer = []; for (let i = 0; i <= 26; i++) { const t = i / 26 * TAU; outer.push([Math.sin(t) * k * .44 * (1 - .2 * Math.max(0, -Math.cos(t))), -Math.cos(t) * k * .48]); }
      paint(g, outer, '#c9455a', { lw: k / 26, seed: s });
      paint(g, outer.map(([x, y]) => [x * .8, y * .8]), '#f6c2c8', { lw: k / 40, line: false, seed: s + 1 });
      stroke(g, [[0, -k * .3], [0, k * .32]], '#ffffff', k * .05);
      stroke(g, [[0, -k * .1], [-k * .18, k * .05], [-k * .14, k * .22]], '#ffffff', k * .04);
      stroke(g, [[0, -k * .1], [k * .18, k * .05], [k * .14, k * .22]], '#ffffff', k * .04);
    },
    mint(g, k, s) {
      for (const sd of [-1, 1]) { g.save(); g.rotate(sd * .55); const leaf = [[0, 0], [-k * .2, -k * .2], [-k * .14, -k * .48], [0, -k * .62], [k * .14, -k * .48], [k * .2, -k * .2]]; paint(g, leaf, '#7fb07a', { lw: k / 34, seed: s + sd }); stroke(g, [[0, -k * .05], [0, -k * .52]], 'rgba(60,100,60,.7)', k * .03); g.restore(); }
    },
    lemon(g, k, s) {
      paint(g, ell(0, 0, k * .42, k * .42, 0, TAU, 0, s), '#e6c24e', { lw: k / 28, seed: s });
      paint(g, ell(0, 0, k * .35, k * .35, 0, TAU, 0, s + 1), '#fbf3cf', { lw: k / 40, line: false, flat: true, seed: s });
      for (let i = 0; i < 8; i++) { const a = i / 8 * TAU; paint(g, [[Math.cos(a + .1) * k * .05, Math.sin(a + .1) * k * .05], ...ell(0, 0, k * .3, k * .3, a + .1, a + TAU / 8 - .1, 3, s + i)], '#f4dc78', { lw: k / 60, line: false, flat: true }); }
    },
    mango(g, k, s) { const q = k * .26; paint(g, [[-q, -q * .8], [q * .9, -q], [q, q * .85], [-q * .85, q]], '#f2b24a', { lw: k / 30, gloss: true, seed: s }); },
    peach(g, k, s) { const pts = [...ell(0, k * .2, k * .55, k * .55, Math.PI * 1.15, Math.PI * 1.85, 0, s), ...ell(0, k * .38, k * .36, k * .36, Math.PI * 1.82, Math.PI * 1.18, 0, s + 1)]; paint(g, pts, '#f6c6ae', { lw: k / 30, seed: s }); stroke(g, ell(0, k * .2, k * .52, k * .52, Math.PI * 1.17, Math.PI * 1.83, 0, s), '#d9606a', k * .06); },
    curl(g, k, s) { const pts = []; for (let t = 0; t <= 1.001; t += .06) pts.push([(t - .5) * k * 1.1, Math.sin(t * Math.PI * 3) * k * .12 - k * .06]); for (let t = 1; t >= -.001; t -= .06) pts.push([(t - .5) * k * 1.1, Math.sin(t * Math.PI * 3) * k * .12 + k * .06]); paint(g, pts, '#6b4a3a', { lw: k / 30, seed: s }); },
    nut(g, k, s) { paint(g, [[-k * .4, 0], [-k * .2, -k * .2], [k * .15, -k * .22], [k * .4, 0], [k * .15, k * .18], [-k * .2, k * .16]], '#e2c49a', { lw: k / 34, seed: s }); },
    chestnut(g, k, s) { paint(g, [[0, -k * .42], [k * .4, -k * .1], [k * .32, k * .32], [0, k * .38], [-k * .32, k * .32], [-k * .4, -k * .1]], '#8a5a3c', { lw: k / 28, gloss: true, seed: s }); paint(g, ell(0, k * .26, k * .2, k * .07, 0, TAU, 0, s), '#d8c39f', { lw: k / 50, line: false, flat: true }); },
    sakura(g, k, s) { for (let i = 0; i < 5; i++) { g.save(); g.rotate(i / 5 * TAU); paint(g, [[0, 0], [-k * .22, -k * .16], [-k * .18, -k * .42], [-k * .05, -k * .48], [0, -k * .41], [k * .05, -k * .48], [k * .18, -k * .42], [k * .22, -k * .16]], '#f6c8d2', { lw: k / 36, seed: s + i }); g.restore(); } paint(g, ell(0, 0, k * .07, k * .07, 0, TAU, 0, s), '#f2d06a', { lw: k / 50, flat: true }); },
    petal(g, k, s) { paint(g, [[-k * .35, k * .1], [-k * .25, -k * .25], [k * .15, -k * .32], [k * .38, 0], [k * .15, k * .2]], '#e7a1b0', { lw: k / 34, seed: s }); },
    sprinkle(g, k, s) { const cols = ['#f0a8c0', '#a9d0e8', '#f1dca0', '#b9d9a8', '#c7b2e0']; for (let i = 0; i < 6; i++) { const a = i * 2.3, d = (i % 3) * k * .14; g.save(); g.translate(Math.cos(a) * d, Math.sin(a) * d); g.rotate(a * 1.7); paint(g, [[-k * .1, -k * .035], [k * .1, -k * .035], [k * .1, k * .035], [-k * .1, k * .035]], cols[i % 5], { lw: k / 60, flat: true, line: STYLE !== 'story' }); g.restore(); } },
    pearl(g, k, s) { for (const [x, y, r] of [[0, 0, .16], [k * .22, k * .1, .11], [-k * .18, k * .14, .1]]) paint(g, ell(x, y, k * r, k * r, 0, TAU, 0, s), '#f1eef4', { lw: k / 50, gloss: true }); },
    gold(g, k, s) { paint(g, [[-.3, -.1], [-.1, -.32], [.12, -.2], [.32, -.28], [.26, .02], [.34, .22], [.06, .18], [-.12, .3], [-.22, .1]].map(([x, y]) => [x * k, y * k]), '#d8b45a', { lw: k / 50, gloss: true, line: STYLE === 'candy' }); },
  };
  function topping(g, t, x, y, k, a = 0, s = 1) {
    const f = TOP[t]; if (!f) return;
    g.save(); g.translate(x, y);
    if (STYLE !== 'paper') { g.save(); g.translate(k * .05, k * .12); g.scale(1, .45); g.fillStyle = 'rgba(80,50,40,.14)'; g.beginPath(); g.arc(0, 0, k * .36, 0, TAU); g.fill(); g.restore(); }
    g.rotate(a); f(g, k, s); g.restore();
  }

  // ———— 甜点 ————
  const SHAPE = {
    sponge: { top: -.34, rx: .42, ry: .15, h: .32 }, crepe: { top: -.36, rx: .42, ry: .15, h: .34 }, tart: { top: -.13, rx: .44, ry: .16, h: .12 },
    cupcake: { top: -.6, rx: .26, ry: .1, h: .6 }, choux: { top: -.44, rx: .3, ry: .12, h: .42 }, cookie: { top: -.07, rx: .4, ry: .15, h: .07 },
    roll: { top: -.3, rx: .44, ry: .1, h: .3 }, macaron: { top: -.34, rx: .3, ry: .11, h: .32 },
  };
  const topPoint = (base, x, y, W, u, v) => { const s = SHAPE[base] || SHAPE.sponge; return [x + u * s.rx * W, y + s.top * W + v * s.ry * W]; };
  // 盘子，绘本和糖果风底下垫一张蕾丝花边纸
  function plate(g, x, y, W) {
    const lw = W / 120;
    if (STYLE !== 'paper') {
      const lace = []; const n = 28;
      for (let i = 0; i < n; i++) { const a0 = i / n * TAU, a1 = (i + 1) / n * TAU; for (let k = 0; k <= 4; k++) { const a = a0 + (a1 - a0) * k / 4, r = 1 + .06 * Math.sin(k / 4 * Math.PI); lace.push([x + Math.cos(a) * W * .64 * r, y + Math.sin(a) * W * .2 * r]); } }
      paint(g, lace, '#fbf8f2', { lw, flat: true });
      g.fillStyle = 'rgba(200,185,165,.55)';
      for (let i = 0; i < 28; i++) { const a = i / 28 * TAU; g.beginPath(); g.ellipse(x + Math.cos(a) * W * .58, y + Math.sin(a) * W * .178, W * .012, W * .006, 0, 0, TAU); g.fill(); }
    }
    paint(g, ell(x, y, W * .54, W * .16, 0, TAU, 0, 4), STYLE === 'paper' ? '#f4efe6' : '#ffffff', { lw, seed: 4 });
    paint(g, ell(x, y - W * .005, W * .44, W * .12, 0, TAU, 0, 5), '#f6f1ea', { lw: lw * .6, line: STYLE === 'candy', flat: true, seed: 5 });
    if (STYLE === 'story') { g.strokeStyle = 'rgba(200,169,108,.8)'; g.lineWidth = lw * 1.2; trace(g, ell(x, y, W * .5, W * .145, 0, TAU, 0, 6), true, .4, 6); g.stroke(); }
  }
  function rosette(g, x, y, r, col, s) {
    if (STYLE === 'paper') { const pts = []; for (let i = 0; i < 12; i++) { const a = i / 12 * TAU, rr = i % 2 ? r * .7 : r; pts.push([x + Math.cos(a) * rr, y + Math.sin(a) * rr * .8]); } paint(g, pts, col, { lw: r / 10, seed: s }); return; }
    paint(g, ell(x, y, r, r * .8, 0, TAU, 0, s), col, { lw: r / 9, seed: s });
    // 奶油挤出来的螺纹
    const sp = []; for (let t = 0; t < 1; t += .06) { const a = t * TAU * 1.6, rr = r * .78 * (1 - t); sp.push([x + Math.cos(a) * rr, y + Math.sin(a) * rr * .75]); }
    stroke(g, sp, tone(col, -.35, .7), r / 9);
  }
  function body(g, base, x, y, W, creamCol, seed) {
    const s = SHAPE[base] || SHAPE.sponge, rx = s.rx * W, ry = s.ry * W, h = s.h * W, ty = y + s.top * W, lw = W / 110;
    const R = rng(seed);
    switch (base) {
      case 'sponge': {
        paint(g, side(x, ty, rx, ry, h, seed), creamCol, { lw, seed });
        // 侧面一圈缎带（像圣诞蛋糕那样），绘本风还有个小蝴蝶结
        paint(g, side(x, ty + h * .55, rx * 1.005, ry, h * .2, seed + 1), '#e8b4b8', { lw: lw * .8, seed: seed + 1 });
        if (STYLE !== 'paper') stroke(g, ell(x, ty + h * .65, rx * 1.005, ry, .15, Math.PI - .15, 0, seed), 'rgba(255,255,255,.6)', lw * .8);
        paint(g, ell(x, ty, rx, ry, 0, TAU, 0, seed + 2), tone(creamCol, .15), { lw, seed: seed + 2 });
        break;
      }
      case 'crepe': {
        for (let i = 0; i < 9; i++) paint(g, side(x, ty + h * i / 9, rx, ry, h / 9 + .5, seed + i), i % 2 ? creamCol : '#e9c48e', { lw: lw * .6, flat: STYLE === 'paper', line: i === 0 || STYLE === 'candy', seed: seed + i });
        paint(g, ell(x, ty, rx, ry, 0, TAU, 0, seed), '#e2b77c', { lw, seed });
        if (STYLE !== 'paper') { g.fillStyle = 'rgba(150,95,45,.3)'; for (let i = 0; i < 40; i++) { const a = R() * TAU, d = Math.sqrt(R()); g.beginPath(); g.ellipse(x + Math.cos(a) * d * rx * .9, ty + Math.sin(a) * d * ry * .9, lw * 1.2, lw * .6, 0, 0, TAU); g.fill(); } }
        break;
      }
      case 'tart': {
        // 波浪边的挞皮
        const rim = []; const n = 22;
        for (let i = 0; i <= n; i++) { const a = i / n * Math.PI; rim.push([x + Math.cos(a) * rx, ty + h + Math.sin(a) * ry]); }
        for (let i = n; i >= 0; i--) { const a = i / n * Math.PI; rim.push([x + Math.cos(a) * rx * 1.02, ty + Math.sin(a) * ry + (i % 2 ? -h * .12 : 0)]); }
        paint(g, rim, '#dcaa66', { lw, seed });
        const top = []; for (let i = 0; i < 26; i++) { const a = i / 26 * TAU; top.push([x + Math.cos(a) * rx * (1 + (i % 2 ? .03 : 0)), ty + Math.sin(a) * ry * (1 + (i % 2 ? .05 : 0))]); }
        paint(g, top, '#e6bd7c', { lw, seed: seed + 1 });
        paint(g, ell(x, ty + ry * .05, rx * .86, ry * .82, 0, TAU, 0, seed + 2), creamCol, { lw: lw * .8, seed: seed + 2, gloss: true });
        break;
      }
      case 'cupcake': {
        const cy = y - W * .3, bw = W * .25, tw = W * .33;
        paint(g, [[x - tw, cy], [x - bw, y], ...ell(x, y, bw, W * .05, Math.PI, 0, 0, seed).reverse().reverse(), [x + bw, y], [x + tw, cy]], '#f3cdc9', { lw, seed });
        if (STYLE !== 'paper') for (let i = 1; i < 9; i++) { const t = i / 9; stroke(g, [[x - tw + t * tw * 2, cy + 1], [x - bw + t * bw * 2, y - 1]], 'rgba(190,120,120,.5)', lw * .7); }
        else for (let i = 0; i < 4; i++) { const t = (i * 2 + 1) / 9; paint(g, [[x - tw + t * tw * 2, cy], [x - tw + (t + 1 / 9) * tw * 2, cy], [x - bw + (t + 1 / 9) * bw * 2, y], [x - bw + t * bw * 2, y]], '#e7b5b1', { lw, line: false, flat: true }); }
        paint(g, ell(x, cy, tw * 1.02, W * .07, Math.PI, TAU, 0, seed), '#d9a865', { lw, seed });
        for (let i = 0; i < 4; i++) { const yy = cy - W * (.04 + i * .085), rw = tw * (1 - i * .2); rosetteRing(g, x, yy, rw, W * .07, creamCol, seed + i, lw); }
        paint(g, ell(x, y + s.top * W, rx, ry, 0, TAU, 0, seed), tone(creamCol, .2), { lw: lw * .8, seed });
        break;
      }
      case 'choux': {
        const r = W * .3, cy = y - W * .22;
        paint(g, ell(x, cy + r * .12, r, r * .66, 0, TAU, 0, seed), '#d9a05a', { lw, seed });
        for (let i = 0; i < 9; i++) { const a = Math.PI + i / 8 * Math.PI; rosette(g, x + Math.cos(a) * r * .9, cy - W * .015, W * .055, creamCol, seed + i); }
        paint(g, ell(x, y + s.top * W, rx, ry * 1.7, 0, TAU, 0, seed + 3), '#e5b06a', { lw, seed: seed + 3 });
        if (STYLE !== 'paper') { g.strokeStyle = 'rgba(140,90,40,.45)'; g.lineWidth = lw * .8; for (let i = 0; i < 10; i++) { const a = R() * TAU, d = R() * .6; g.beginPath(); g.moveTo(x + Math.cos(a) * rx * d, y + s.top * W + Math.sin(a) * ry * d); g.lineTo(x + Math.cos(a + .5) * rx * (d + .2), y + s.top * W + Math.sin(a + .5) * ry * (d + .2)); g.stroke(); } }
        break;
      }
      case 'cookie': {
        paint(g, side(x, ty, rx, ry, h, seed), '#c98d4a', { lw, seed });
        paint(g, ell(x, ty, rx, ry, 0, TAU, 0, seed + 1), '#e2ad69', { lw, seed: seed + 1 });
        for (let i = 0; i < 9; i++) { const a = R() * TAU, d = Math.sqrt(R()) * .8; paint(g, ell(x + Math.cos(a) * d * rx, ty + Math.sin(a) * d * ry, W * .025, W * .016, 0, TAU, 5, seed + i), '#5e3a2a', { lw: lw * .5, line: false, flat: true }); }
        break;
      }
      case 'roll': {
        paint(g, [...ell(x - rx + h * .45, ty + h * .35, h * .45, h * .65, Math.PI / 2, Math.PI * 1.5, 0, seed), ...ell(x + rx - h * .45, ty + h * .35, h * .45, h * .65, -Math.PI / 2, Math.PI / 2, 0, seed + 1)], '#d9a05a', { lw, seed });
        const ex = x + rx - h * .45, ecy = ty + h * .35;
        paint(g, ell(ex, ecy, h * .42, h * .62, 0, TAU, 0, seed + 2), '#f4dcae', { lw, seed: seed + 2 });
        const sp = []; for (let t = 0; t < 1; t += .03) { const a = t * TAU * 2.2, rr = .85 * (1 - t); sp.push([ex + Math.cos(a) * rr * h * .4, ecy + Math.sin(a) * rr * h * .6]); }
        g.save(); trace(g, sp, false); g.strokeStyle = creamCol; g.lineWidth = h * .12; g.lineCap = 'round'; g.stroke(); g.restore();
        stroke(g, sp, tone(creamCol, -.4, .6), lw * .7);
        paint(g, ell(x - h * .1, ty - ry * .2, rx * .82, ry * .9, 0, TAU, 0, seed + 3), tone(creamCol, .15), { lw: lw * .8, seed: seed + 3 });
        break;
      }
      case 'macaron': {
        const r = W * .3;
        paint(g, ell(x, y - W * .08, r, r * .34, 0, TAU, 0, seed), creamCol, { lw, seed });
        for (let i = 0; i < 11; i++) { const a = Math.PI * (i / 10); paint(g, ell(x - Math.cos(a) * r * .95, y - W * .05, W * .022, W * .016, 0, TAU, 6, seed + i), tone(creamCol, -.08), { lw: lw * .5, line: false, flat: true }); }
        paint(g, ell(x, y - W * .17, r * .92, W * .05, 0, TAU, 0, seed + 1), '#fbf1e2', { lw: lw * .8, seed: seed + 1 });
        paint(g, ell(x, y - W * .27, r, r * .42, 0, TAU, 0, seed + 2), creamCol, { lw, seed: seed + 2, gloss: true });
        break;
      }
    }
  }
  // 纸杯蛋糕顶上一圈圈的奶油
  function rosetteRing(g, x, y, rw, rh, col, seed, lw) { paint(g, ell(x, y, rw, rh, 0, TAU, 0, seed), col, { lw, seed }); stroke(g, ell(x, y + rh * .2, rw * .92, rh * .7, .3, Math.PI - .3, 0, seed), tone(col, -.3, .6), lw * .8); }

  // 一整块甜点：跟 ART.dessert 一样的参数
  function dessert(g, r, x, y, W, { plate: withPlate = true, sparkles = true } = {}) {
    const creamCol = (CREAMS[r.cream] || CREAMS.plain).color, seed = r.seed || 1;
    if (withPlate) plate(g, x, y + W * .02, W);
    if (STYLE !== 'paper') { g.save(); g.fillStyle = 'rgba(80,55,40,.16)'; g.beginPath(); g.ellipse(x, y, W * .4, W * .1, 0, 0, TAU); g.fill(); g.restore(); }
    body(g, r.base, x, y, W, creamCol, seed);
    if (r.dust) { const R = rng(seed + 7); g.fillStyle = 'rgba(255,255,255,.9)'; for (let i = 0; i < 70; i++) { const a = R() * TAU, d = Math.sqrt(R()); const [px, py] = topPoint(r.base, x, y, W, Math.cos(a) * d * .95, Math.sin(a) * d * .95); g.beginPath(); g.arc(px, py, W * .006, 0, TAU); g.fill(); } }
    for (const d of r.drizzle || []) {
      const pts = d.pts.map(([u, v]) => topPoint(r.base, x, y, W, u, v));
      g.save(); trace(g, pts, false); g.lineCap = 'round'; g.lineJoin = 'round'; g.strokeStyle = STYLE === 'candy' ? '#5b3b30' : tone(d.c || '#6b4a3a', -.3); g.lineWidth = W * .03; g.stroke(); g.strokeStyle = d.c || '#6b4a3a'; g.lineWidth = W * .021; g.stroke(); g.restore();
      if (STYLE !== 'paper') stroke(g, pts, 'rgba(255,255,255,.45)', W * .005);
    }
    const draws = [];
    let rs = 0;
    for (const p of r.pipes || []) { let last = null; for (const [u, v] of p.pts) { const q = topPoint(r.base, x, y, W, u, v); if (last && Math.hypot(q[0] - last[0], q[1] - last[1]) < W * .045) continue; last = q; const k = rs++; draws.push({ y: q[1], f: () => rosette(g, q[0], q[1] - W * .02, W * .05, p.c || creamCol, seed + k) }); } }
    (r.items || []).forEach((it, i) => { const [px, py] = topPoint(r.base, x, y, W, it.u, it.v); draws.push({ y: py, f: () => topping(g, it.t, px, py - W * .03, W * .14 * (it.s || 1), it.a || 0, seed + i * 7) }); });
    draws.sort((a, b) => a.y - b.y).forEach((d) => d.f());
    if (sparkles && W > 60) { const R = rng(seed + 3); for (let i = 0; i < 5; i++) { const a = -Math.PI * (.1 + R() * .8), d = W * (.5 + R() * .2); sparkle(g, x + Math.cos(a) * d, y - W * .3 + Math.sin(a) * d * .7, W * (.025 + R() * .025), i); } }
  }

  // ———— 做完甜点的分享海报（剪纸风）————
  // 一整块底色，上面一句英文、一句中文（按口味挑），中间是剪纸风的甜点，底下一条格纹 / 波点，角上一张手写体小标签
  const LINES = {
    sweet: ['the sky turns pink|for three bites.', '天空被三口甜点|涂成了粉色。'],
    cute: ['small and round,|like a good day.', '小小的、圆圆的，|像很好的一天。'],
    fruity: ['a little sour,|then all of summer.', '先是一点酸，|然后是一整个夏天。'],
    sour: ['bright and sharp,|like a window opened.', '亮亮的、酸酸的，|像推开了一扇窗。'],
    rich: ['slow and deep,|like a rainy afternoon.', '慢慢的、深深的，|像一个下雨的下午。'],
    bitter: ['bitter first,|sweet at the end.', '先苦一点，|最后是甜的。'],
    floral: ['petals on the tongue,|spring in the mouth.', '舌尖落了花瓣，|嘴里是春天。'],
    fresh: ['cool as morning,|light as a breeze.', '像清晨一样凉，|像风一样轻。'],
    classic: ['like a sunday|in grandma\u2019s kitchen.', '像星期天，|外婆的厨房。'],
    crunchy: ['a soft crack,|then golden crumbs.', '轻轻一声脆，|落下金色的碎屑。'],
  };
  const POSTER_BG = { sweet: '#d9668a', cute: '#e48aa4', fruity: '#e0675f', sour: '#e2bf45', rich: '#8a5a3c', bitter: '#6f7f45', floral: '#8c78b8', fresh: '#7fb7a6', classic: '#c9a06a', crunchy: '#d99a45' };
  function poster(g, r, W, H, { tag = null, pattern = 0 } = {}) {
    const keep = STYLE; STYLE = 'paper';
    const tags = Object.entries(r.tags || {}).sort((a, b) => b[1] - a[1]).map((e) => e[0]).filter((t) => LINES[t]);
    const t = tag || tags[0] || 'sweet', bg = POSTER_BG[t], [en, zh] = LINES[t];
    g.save();
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    // 底下一条：格纹或者波点
    const by = H * .78;
    g.fillStyle = '#f6efe4'; g.fillRect(0, by, W, H - by);
    g.strokeStyle = tone(bg, -.05, .7); g.fillStyle = tone(bg, -.05, .7); g.lineWidth = W * .004;
    if (pattern % 2 === 0) { const st = W * .055; for (let x = -H; x < W + H; x += st) { g.beginPath(); g.moveTo(x, by); g.lineTo(x + (H - by), H); g.stroke(); g.beginPath(); g.moveTo(x, H); g.lineTo(x + (H - by), by); g.stroke(); } }
    else { const st = W * .045; for (let y = by + st / 2, i = 0; y < H; y += st, i++) for (let x = (i % 2) * st / 2 + st / 4; x < W; x += st) { g.beginPath(); g.arc(x, y, W * .006, 0, TAU); g.fill(); } }
    // 纸纹
    g.globalCompositeOperation = 'multiply'; g.globalAlpha = .18; g.fillStyle = grain(g); g.fillRect(0, 0, W, H); g.globalCompositeOperation = 'source-over'; g.globalAlpha = 1;
    // 字
    const pad = W * .1;
    g.fillStyle = '#fbf7f1'; g.textAlign = 'left'; g.textBaseline = 'alphabetic';
    g.font = `italic ${W * .082}px Georgia, "Times New Roman", serif`;
    en.split('|').forEach((l, i) => g.fillText(l, pad, H * .12 + i * W * .095));
    g.font = `${W * .05}px "Songti SC", "STSong", serif`;
    zh.split('|').forEach((l, i) => g.fillText(l, pad, H * .12 + en.split('|').length * W * .095 + W * .03 + i * W * .068));
    // 碎纸屑
    const R = rng((r.seed || 1) + 9);
    for (let i = 0; i < 7; i++) sparkle(g, W * (.15 + R() * .7), H * (.36 + R() * .32), W * (.012 + R() * .014), i);
    // 一把剪纸的小勺子，斜斜地从右上角伸进来
    g.save(); g.translate(W * .8, H * .36); g.rotate(-.7);
    paint(g, [[-W * .012, 0], [W * .012, 0], [W * .016, W * .3], [-W * .016, W * .3]], '#fbf7f1', { lw: W / 300, flat: true });
    paint(g, ell(0, -W * .05, W * .055, W * .075, 0, TAU, 0, 3), '#fbf7f1', { lw: W / 300, flat: true });
    paint(g, ell(-W * .01, -W * .06, W * .03, W * .045, 0, TAU, 0, 4), tone(bg, .55), { lw: W / 300, flat: true });
    g.restore();
    // 甜点：剪纸风，大大的，压在格纹上
    const DW = W * .92;
    dessert(g, r, W * .5, by + W * .06, DW, { plate: true, sparkles: false });
    // 手写体的小标签
    g.save(); g.translate(W * .72, H * .5); g.rotate(-.12);
    paint(g, [[-W * .13, -W * .04], [W * .13, -W * .05], [W * .14, W * .04], [-W * .12, W * .05]], '#fbf7f1', { lw: W / 300, flat: true });
    g.fillStyle = tone(bg, -.25); g.font = `italic ${W * .036}px "Snell Roundhand", "Brush Script MT", cursive`; g.textAlign = 'center';
    g.fillText(r.name || '', 0, W * .012);
    g.restore();
    g.fillStyle = 'rgba(251,247,241,.85)'; g.font = `${W * .026}px Georgia, serif`; g.textAlign = 'right'; g.fillText('qi · patisserie', W - pad * .6, H * .97);
    g.restore();
    STYLE = keep;
  }

  return { TAU, style, setStyle, poster, LINES, hex, rgba, tone, rng, ell, side, trace, paint, stroke, sparkle, topping, dessert, topPoint, SHAPE, plate, rosette, grain };
})();
