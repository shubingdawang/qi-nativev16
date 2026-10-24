// 甜品屋的画：甜点（八种坯底、奶油、裱花、淋酱、糖粉、十几种装饰）、人物（她、clawd、客人）、店里的场景。
// 全用 canvas 一笔一笔画：渐变打光、柔和的影子、细节（草莓籽、蓝莓的花萼、柠檬的瓣、千层的层）。
'use strict';

const ART = (() => {
  const TAU = Math.PI * 2;
  // 颜色工具
  const hex = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const rgb = (c, a = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;
  const shade = (h, k, a = 1) => { const c = hex(h); return rgb(k >= 0 ? c.map((v) => v + (255 - v) * k) : c.map((v) => v * (1 + k)), a); };
  // 同一个种子永远同一个随机数（同一块甜点每次画都一样）
  const rng = (seed) => { let s = (seed * 9301 + 49297) % 233280 || 1; return () => (s = (s * 9301 + 49297) % 233280) / 233280; };

  function ellipse(g, x, y, rx, ry) { g.beginPath(); g.ellipse(x, y, Math.max(.1, rx), Math.max(.1, ry), 0, 0, TAU); }
  function rr(g, x, y, w, h, r) { g.beginPath(); g.roundRect ? g.roundRect(x, y, w, h, r) : (g.moveTo(x + r, y), g.arcTo(x + w, y, x + w, y + h, r), g.arcTo(x + w, y + h, x, y + h, r), g.arcTo(x, y + h, x, y, r), g.arcTo(x, y, x + w, y, r), g.closePath()); }
  function softShadow(g, x, y, rx, ry, a = .18) {
    const gr = g.createRadialGradient(x, y, 0, x, y, rx);
    gr.addColorStop(0, `rgba(80,55,40,${a})`); gr.addColorStop(1, 'rgba(80,55,40,0)');
    g.save(); g.translate(x, y); g.scale(1, ry / rx); g.translate(-x, -y); g.fillStyle = gr; g.beginPath(); g.arc(x, y, rx, 0, TAU); g.fill(); g.restore();
  }

  // ———————————————— 装饰 ————————————————
  // 每个装饰画在 (0,0)，大小 k（大约一颗草莓的宽），已经旋转好
  const TOP = {
    strawberry(g, k) {
      const gr = g.createRadialGradient(-k * .2, -k * .25, k * .05, 0, 0, k * .75);
      gr.addColorStop(0, '#f08a98'); gr.addColorStop(.55, '#d9566b'); gr.addColorStop(1, '#a8394c');
      g.fillStyle = gr; g.beginPath();
      g.moveTo(0, k * .62); g.bezierCurveTo(-k * .62, k * .2, -k * .55, -k * .42, 0, -k * .4); g.bezierCurveTo(k * .55, -k * .42, k * .62, k * .2, 0, k * .62); g.fill();
      g.fillStyle = '#f6dc8e';
      for (const [a, b] of [[-.2, -.05], [.18, -.1], [0, .15], [-.28, .2], [.27, .18], [-.08, .38], [.1, .4], [-.32, -.22], [.32, -.2]]) { ellipse(g, a * k, b * k, k * .035, k * .055); g.fill(); }
      g.fillStyle = '#6f9a58';
      for (let i = 0; i < 5; i++) { g.save(); g.rotate(-Math.PI / 2 + (i - 2) * .55); g.beginPath(); g.ellipse(k * .2, -0, k * .2, k * .07, 0, 0, TAU); g.restore(); g.save(); g.translate(0, -k * .38); g.rotate((i - 2) * .6); ellipse(g, 0, -k * .1, k * .07, k * .2); g.fill(); g.restore(); }
      g.fillStyle = 'rgba(255,255,255,.55)'; ellipse(g, -k * .22, -k * .12, k * .07, k * .13); g.fill();
    },
    halfberry(g, k) {
      g.fillStyle = '#c9455a'; g.beginPath(); g.moveTo(0, k * .55); g.bezierCurveTo(-k * .58, k * .15, -k * .5, -k * .4, 0, -k * .38); g.bezierCurveTo(k * .5, -k * .4, k * .58, k * .15, 0, k * .55); g.fill();
      g.fillStyle = '#f4b7bf'; g.beginPath(); g.moveTo(0, k * .45); g.bezierCurveTo(-k * .46, k * .12, -k * .4, -k * .3, 0, -k * .29); g.bezierCurveTo(k * .4, -k * .3, k * .46, k * .12, 0, k * .45); g.fill();
      g.strokeStyle = 'rgba(255,255,255,.8)'; g.lineWidth = k * .05; g.beginPath(); g.moveTo(0, -k * .22); g.lineTo(0, k * .32); g.stroke();
      for (const s of [-1, 1]) { g.beginPath(); g.moveTo(0, -k * .1); g.quadraticCurveTo(s * k * .22, 0, s * k * .18, k * .2); g.stroke(); }
    },
    blueberry(g, k) {
      const r = k * .3, gr = g.createRadialGradient(-r * .35, -r * .4, r * .1, 0, 0, r);
      gr.addColorStop(0, '#8a96c4'); gr.addColorStop(.6, '#4d5a8c'); gr.addColorStop(1, '#2f3760');
      g.fillStyle = gr; g.beginPath(); g.arc(0, 0, r, 0, TAU); g.fill();
      g.fillStyle = 'rgba(210,215,235,.35)'; g.beginPath(); g.arc(-r * .2, -r * .25, r * .55, 0, TAU); g.fill();   // 果霜
      g.strokeStyle = '#2a2f50'; g.lineWidth = r * .14;
      for (let i = 0; i < 5; i++) { const a = i / 5 * TAU; g.beginPath(); g.moveTo(0, -r * .1); g.lineTo(Math.cos(a) * r * .28, -r * .1 + Math.sin(a) * r * .28); g.stroke(); }
    },
    mint(g, k) {
      for (const s of [-1, 1]) {
        g.save(); g.rotate(s * .55);
        const gr = g.createLinearGradient(0, 0, 0, -k * .6); gr.addColorStop(0, '#6f9a6a'); gr.addColorStop(1, '#a9cfa0');
        g.fillStyle = gr; g.beginPath(); g.moveTo(0, 0); g.bezierCurveTo(-k * .26, -k * .18, -k * .2, -k * .5, 0, -k * .62); g.bezierCurveTo(k * .2, -k * .5, k * .26, -k * .18, 0, 0); g.fill();
        g.strokeStyle = 'rgba(70,110,70,.6)'; g.lineWidth = k * .025; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -k * .55); g.stroke();
        for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(0, -k * .14 * i); g.lineTo(-k * .1, -k * .14 * i - k * .07); g.moveTo(0, -k * .14 * i); g.lineTo(k * .1, -k * .14 * i - k * .07); g.stroke(); }
        g.restore();
      }
    },
    lemon(g, k) {
      const r = k * .42;
      g.fillStyle = '#e6c24e'; g.beginPath(); g.arc(0, 0, r, 0, TAU); g.fill();
      g.fillStyle = '#fbf3cf'; g.beginPath(); g.arc(0, 0, r * .86, 0, TAU); g.fill();
      for (let i = 0; i < 8; i++) { const a = i / 8 * TAU; g.fillStyle = '#f3dc7a'; g.beginPath(); g.moveTo(Math.cos(a + .08) * r * .1, Math.sin(a + .08) * r * .1); g.arc(0, 0, r * .76, a + .08, a + TAU / 8 - .08); g.closePath(); g.fill(); }
      g.fillStyle = 'rgba(255,255,255,.5)'; g.beginPath(); g.arc(-r * .3, -r * .3, r * .18, 0, TAU); g.fill();
    },
    mango(g, k) {
      const s = k * .5, gr = g.createLinearGradient(-s / 2, -s / 2, s / 2, s / 2);
      gr.addColorStop(0, '#f8cf6a'); gr.addColorStop(1, '#e09a32');
      g.fillStyle = gr; rr(g, -s / 2, -s / 2, s, s, s * .22); g.fill();
      g.fillStyle = 'rgba(255,255,255,.45)'; rr(g, -s * .35, -s * .38, s * .3, s * .14, s * .07); g.fill();
    },
    peach(g, k) {
      g.fillStyle = '#f6c6ae'; g.beginPath(); g.arc(0, k * .2, k * .55, Math.PI * 1.15, Math.PI * 1.85); g.arc(0, k * .38, k * .36, Math.PI * 1.82, Math.PI * 1.18, true); g.fill();
      g.strokeStyle = '#d9606a'; g.lineWidth = k * .07; g.beginPath(); g.arc(0, k * .2, k * .53, Math.PI * 1.17, Math.PI * 1.83); g.stroke();
      g.fillStyle = 'rgba(255,255,255,.4)'; ellipse(g, -k * .12, -k * .22, k * .1, k * .04); g.fill();
    },
    curl(g, k) {
      g.lineCap = 'round';
      for (let i = 0; i < 3; i++) {
        g.strokeStyle = i === 1 ? '#8a6150' : '#5a3a2e'; g.lineWidth = k * (.16 - i * .03);
        g.beginPath(); for (let t = 0; t <= 1.001; t += .05) { const x = (t - .5) * k * 1.1, y = Math.sin(t * Math.PI * 3) * k * .12 * (1 - i * .2); t ? g.lineTo(x, y + i * k * .05) : g.moveTo(x, y + i * k * .05); } g.stroke();
      }
      g.strokeStyle = 'rgba(255,240,230,.35)'; g.lineWidth = k * .03; g.beginPath(); g.moveTo(-k * .45, -k * .06); g.lineTo(k * .2, -k * .1); g.stroke();
    },
    nut(g, k) {
      const gr = g.createLinearGradient(0, -k * .3, 0, k * .3); gr.addColorStop(0, '#ead2ae'); gr.addColorStop(1, '#c99a6a');
      g.fillStyle = gr; g.beginPath(); g.moveTo(-k * .4, 0); g.quadraticCurveTo(0, -k * .32, k * .4, 0); g.quadraticCurveTo(0, k * .28, -k * .4, 0); g.fill();
      g.strokeStyle = '#a77a4e'; g.lineWidth = k * .04; g.stroke();
    },
    chestnut(g, k) {
      const gr = g.createRadialGradient(-k * .12, -k * .15, k * .04, 0, 0, k * .45);
      gr.addColorStop(0, '#c79065'); gr.addColorStop(.6, '#8a5a3c'); gr.addColorStop(1, '#5e3a26');
      g.fillStyle = gr; g.beginPath(); g.moveTo(0, -k * .42); g.bezierCurveTo(k * .45, -k * .2, k * .42, k * .38, 0, k * .36); g.bezierCurveTo(-k * .42, k * .38, -k * .45, -k * .2, 0, -k * .42); g.fill();
      g.fillStyle = 'rgba(255,240,220,.6)'; ellipse(g, -k * .12, -k * .14, k * .07, k * .12); g.fill();
      g.fillStyle = '#d8c39f'; ellipse(g, 0, k * .26, k * .2, k * .08); g.fill();
    },
    sakura(g, k) {
      for (let i = 0; i < 5; i++) {
        g.save(); g.rotate(i / 5 * TAU);
        const gr = g.createLinearGradient(0, 0, 0, -k * .5); gr.addColorStop(0, '#e9a4b4'); gr.addColorStop(1, '#fbe1e6');
        g.fillStyle = gr; g.beginPath(); g.moveTo(0, 0); g.bezierCurveTo(-k * .24, -k * .14, -k * .22, -k * .44, -k * .06, -k * .48); g.lineTo(0, -k * .42); g.lineTo(k * .06, -k * .48); g.bezierCurveTo(k * .22, -k * .44, k * .24, -k * .14, 0, 0); g.fill();
        g.restore();
      }
      g.fillStyle = '#d97a8e'; for (let i = 0; i < 5; i++) { const a = i / 5 * TAU + .3; g.beginPath(); g.arc(Math.cos(a) * k * .1, Math.sin(a) * k * .1, k * .03, 0, TAU); g.fill(); }
      g.fillStyle = '#f2d06a'; g.beginPath(); g.arc(0, 0, k * .05, 0, TAU); g.fill();
    },
    petal(g, k) {
      const gr = g.createLinearGradient(-k * .3, 0, k * .3, 0); gr.addColorStop(0, '#c9707f'); gr.addColorStop(1, '#efb3bf');
      g.fillStyle = gr; g.beginPath(); g.moveTo(-k * .35, k * .1); g.bezierCurveTo(-k * .3, -k * .35, k * .3, -k * .4, k * .38, 0); g.bezierCurveTo(k * .2, k * .25, -k * .15, k * .25, -k * .35, k * .1); g.fill();
      g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = k * .03; g.beginPath(); g.moveTo(-k * .2, k * .02); g.quadraticCurveTo(0, -k * .12, k * .25, -k * .02); g.stroke();
    },
    sprinkle(g, k) {
      const cols = ['#f0a8c0', '#a9d0e8', '#f1dca0', '#b9d9a8', '#c7b2e0', '#fbf6ef'];
      g.lineCap = 'round'; g.lineWidth = k * .1;
      for (let i = 0; i < 7; i++) { const a = i * 2.3, d = (i % 3) * k * .14; g.strokeStyle = cols[i % cols.length]; g.beginPath(); g.moveTo(Math.cos(a) * d - Math.cos(a * 1.7) * k * .1, Math.sin(a) * d - Math.sin(a * 1.7) * k * .1); g.lineTo(Math.cos(a) * d + Math.cos(a * 1.7) * k * .1, Math.sin(a) * d + Math.sin(a * 1.7) * k * .1); g.stroke(); }
    },
    pearl(g, k) {
      for (const [x, y, r] of [[0, 0, .16], [k * .22, k * .1, .11], [-k * .18, k * .14, .1]]) {
        const rr2 = k * r, gr = g.createRadialGradient(x - rr2 * .4, y - rr2 * .4, rr2 * .1, x, y, rr2);
        gr.addColorStop(0, '#ffffff'); gr.addColorStop(.7, '#e9e4ee'); gr.addColorStop(1, '#b9b2c4');
        g.fillStyle = gr; g.beginPath(); g.arc(x, y, rr2, 0, TAU); g.fill();
      }
    },
    gold(g, k) {
      const gr = g.createLinearGradient(-k * .3, -k * .3, k * .3, k * .3); gr.addColorStop(0, '#f6e3a4'); gr.addColorStop(.5, '#d8b45a'); gr.addColorStop(1, '#f3dc94');
      g.fillStyle = gr; g.beginPath();
      const pts = [[-.3, -.1], [-.1, -.32], [.12, -.2], [.32, -.28], [.26, .02], [.34, .22], [.06, .18], [-.12, .3], [-.22, .1]];
      pts.forEach(([x, y], i) => (i ? g.lineTo(x * k, y * k) : g.moveTo(x * k, y * k))); g.closePath(); g.fill();
    },
  };
  function topping(g, t, x, y, k, a = 0) {
    const f = TOP[t]; if (!f) return;
    g.save(); g.translate(x, y);
    g.save(); g.translate(k * .04, k * .1); g.scale(1, .5); g.fillStyle = 'rgba(80,50,40,.12)'; g.beginPath(); g.arc(0, 0, k * .38, 0, TAU); g.fill(); g.restore();   // 落在奶油上的小影子
    g.rotate(a); f(g, k); g.restore();
  }

  // ———————————————— 甜点 ————————————————
  // 每种坯底的形状：宽 W，顶面（放装饰、裱花的那个椭圆）中心偏多少、多大
  const SHAPE = {
    sponge:  { top: -.34, rx: .42, ry: .15, h: .32 },
    crepe:   { top: -.36, rx: .42, ry: .15, h: .34 },
    tart:    { top: -.13, rx: .44, ry: .16, h: .12 },
    cupcake: { top: -.6, rx: .26, ry: .1, h: .6 },
    choux:   { top: -.44, rx: .3, ry: .12, h: .42 },
    cookie:  { top: -.07, rx: .4, ry: .15, h: .07 },
    roll:    { top: -.3, rx: .44, ry: .1, h: .3 },
    macaron: { top: -.34, rx: .3, ry: .11, h: .32 },
  };
  // 顶面上的点 (u, v ∈ -1..1) 落在画面上哪儿
  function topPoint(base, x, y, W, u, v) {
    const s = SHAPE[base] || SHAPE.sponge;
    return [x + u * s.rx * W, y + s.top * W + v * s.ry * W];
  }
  function cylinder(g, x, y, W, s, side, topCol) {
    const rx = s.rx * W, ry = s.ry * W, h = s.h * W, ty = y + s.top * W;
    const gr = g.createLinearGradient(x - rx, 0, x + rx, 0);
    gr.addColorStop(0, shade(side, -.12)); gr.addColorStop(.35, shade(side, .08)); gr.addColorStop(.7, side); gr.addColorStop(1, shade(side, -.18));
    g.fillStyle = gr; g.beginPath(); g.moveTo(x - rx, ty); g.lineTo(x - rx, ty + h); g.ellipse(x, ty + h, rx, ry, 0, Math.PI, 0, true); g.lineTo(x + rx, ty); g.closePath(); g.fill();
    const tg = g.createRadialGradient(x - rx * .3, ty - ry * .4, rx * .1, x, ty, rx * 1.1);
    tg.addColorStop(0, shade(topCol, .3)); tg.addColorStop(1, shade(topCol, -.04));
    g.fillStyle = tg; ellipse(g, x, ty, rx, ry); g.fill();
  }
  function plate(g, x, y, W) {
    softShadow(g, x, y + W * .05, W * .62, W * .14, .2);
    const gr = g.createRadialGradient(x, y - W * .02, W * .1, x, y, W * .6);
    gr.addColorStop(0, '#ffffff'); gr.addColorStop(.75, '#f4efe8'); gr.addColorStop(1, '#ddd4c8');
    g.fillStyle = gr; ellipse(g, x, y, W * .58, W * .17); g.fill();
    g.strokeStyle = 'rgba(200,169,108,.55)'; g.lineWidth = Math.max(1, W * .012); ellipse(g, x, y, W * .5, W * .14); g.stroke();
  }
  function baseBody(g, base, x, y, W, creamCol, seed) {
    const s = SHAPE[base] || SHAPE.sponge, R = rng(seed);
    const rx = s.rx * W, ry = s.ry * W, ty = y + s.top * W;
    switch (base) {
      case 'sponge': {
        cylinder(g, x, y, W, s, creamCol, creamCol);
        // 侧面露出一道蛋糕胚的切面纹理（奶油抹面没抹满的那种）
        g.strokeStyle = shade(creamCol, -.08, .7); g.lineWidth = W * .006;
        for (let i = 0; i < 9; i++) { const xx = x - rx + (i + .5) * rx * 2 / 9; g.beginPath(); g.moveTo(xx, ty + s.h * W * .2); g.lineTo(xx + W * .01, ty + s.h * W * .95); g.stroke(); }
        break;
      }
      case 'crepe': {
        const h = s.h * W, n = 14;
        for (let i = n - 1; i >= 0; i--) {
          const yy = ty + h * (i + 1) / n, col = i % 2 ? creamCol : '#e6c08e';
          const gr = g.createLinearGradient(x - rx, 0, x + rx, 0); gr.addColorStop(0, shade(col, -.15)); gr.addColorStop(.4, shade(col, .1)); gr.addColorStop(1, shade(col, -.2));
          g.fillStyle = gr; g.beginPath(); g.moveTo(x - rx, yy - h / n); g.lineTo(x - rx, yy); g.ellipse(x, yy, rx, ry, 0, Math.PI, 0, true); g.lineTo(x + rx, yy - h / n); g.closePath(); g.fill();
        }
        const tg = g.createRadialGradient(x - rx * .3, ty - ry * .4, rx * .1, x, ty, rx * 1.1); tg.addColorStop(0, '#f1d6a6'); tg.addColorStop(1, '#d9b07a');
        g.fillStyle = tg; ellipse(g, x, ty, rx, ry); g.fill();
        g.fillStyle = 'rgba(160,100,50,.25)'; for (let i = 0; i < 40; i++) { const a = R() * TAU, d = Math.sqrt(R()); ellipse(g, x + Math.cos(a) * d * rx * .9, ty + Math.sin(a) * d * ry * .9, W * .008, W * .004); g.fill(); }
        break;
      }
      case 'tart': {
        const h = s.h * W;
        cylinder(g, x, y, W, s, '#d9a865', '#d9a865');
        // 一圈波浪花边
        g.fillStyle = '#e8bf80';
        for (let i = 0; i < 26; i++) { const a = i / 26 * TAU, px = x + Math.cos(a) * rx, py = ty + Math.sin(a) * ry; if (Math.sin(a) < -.2) continue; ellipse(g, px, py + h * .5, W * .028, h * .55); g.fill(); }
        const fg = g.createRadialGradient(x - rx * .3, ty - ry * .3, 1, x, ty, rx); fg.addColorStop(0, shade(creamCol, .25)); fg.addColorStop(1, shade(creamCol, -.05));
        g.fillStyle = '#c99050'; ellipse(g, x, ty, rx, ry); g.fill();
        g.fillStyle = fg; ellipse(g, x, ty + ry * .06, rx * .88, ry * .84); g.fill();
        break;
      }
      case 'cupcake': {
        // 褶皱纸托
        const by = y, cy = y - W * .3, bw = W * .26, tw = W * .34;
        const lg = g.createLinearGradient(x - tw, 0, x + tw, 0); lg.addColorStop(0, '#e0b9b6'); lg.addColorStop(.5, '#f6dcd8'); lg.addColorStop(1, '#d4a8a6');
        g.fillStyle = lg; g.beginPath(); g.moveTo(x - tw, cy); g.lineTo(x - bw, by); g.ellipse(x, by, bw, W * .06, 0, Math.PI, 0, true); g.lineTo(x + tw, cy); g.closePath(); g.fill();
        g.strokeStyle = 'rgba(180,120,120,.45)'; g.lineWidth = W * .008;
        for (let i = 1; i < 10; i++) { const t = i / 10; g.beginPath(); g.moveTo(x - tw + t * tw * 2, cy); g.lineTo(x - bw + t * bw * 2, by + Math.sin(t * Math.PI) * W * .05); g.stroke(); }
        // 蛋糕顶从纸托里鼓出来，上面一大坨旋转的奶油
        g.fillStyle = '#d9a865'; ellipse(g, x, cy, tw * 1.02, W * .09); g.fill();
        for (let i = 0; i < 4; i++) {
          const yy = cy - W * (.05 + i * .085), rw = tw * (1 - i * .2);
          const cg = g.createLinearGradient(x - rw, 0, x + rw, 0); cg.addColorStop(0, shade(creamCol, -.12)); cg.addColorStop(.4, shade(creamCol, .2)); cg.addColorStop(1, shade(creamCol, -.15));
          g.fillStyle = cg; ellipse(g, x, yy, rw, W * .075); g.fill();
          g.strokeStyle = shade(creamCol, -.15, .6); g.lineWidth = W * .007; g.beginPath(); g.ellipse(x, yy + W * .01, rw * .92, W * .055, 0, .2, Math.PI - .2); g.stroke();
        }
        g.fillStyle = shade(creamCol, .25); ellipse(g, x, y + s.top * W, rx, ry); g.fill();
        break;
      }
      case 'choux': {
        const r = W * .3, cy = y - W * .22;
        const pg = g.createRadialGradient(x - r * .3, cy - r * .5, r * .1, x, cy, r * 1.1);
        pg.addColorStop(0, '#f0c98a'); pg.addColorStop(.6, '#d49b55'); pg.addColorStop(1, '#a8703a');
        g.fillStyle = pg; ellipse(g, x, cy, r, r * .78); g.fill();
        // 酥皮的裂纹
        g.strokeStyle = 'rgba(140,90,40,.45)'; g.lineWidth = W * .007;
        for (let i = 0; i < 14; i++) { const a = R() * TAU, d = R() * .7; g.beginPath(); g.moveTo(x + Math.cos(a) * r * d, cy + Math.sin(a) * r * d * .7); g.lineTo(x + Math.cos(a + .5) * r * (d + .15), cy + Math.sin(a + .5) * r * (d + .15) * .7); g.stroke(); }
        // 中间横切开，挤出一圈奶油
        for (let i = 0; i < 11; i++) { const a = Math.PI + i / 10 * Math.PI, px = x + Math.cos(a) * r * .95; g.fillStyle = shade(creamCol, i % 2 ? .1 : -.02); ellipse(g, px, cy + W * .02 + Math.abs(Math.sin(a)) * 0, W * .06, W * .05); g.fill(); }
        const cg = g.createRadialGradient(x - r * .3, y + s.top * W - r * .3, 1, x, y + s.top * W, r);
        cg.addColorStop(0, '#f2cf92'); cg.addColorStop(1, '#c98d4a');
        g.fillStyle = cg; ellipse(g, x, y + s.top * W, rx, ry * 1.6); g.fill();
        break;
      }
      case 'cookie': {
        cylinder(g, x, y, W, s, '#c98d4a', '#e2b06e');
        g.fillStyle = 'rgba(120,70,30,.35)'; for (let i = 0; i < 26; i++) { const a = R() * TAU, d = Math.sqrt(R()); ellipse(g, x + Math.cos(a) * d * rx * .85, ty + Math.sin(a) * d * ry * .85, W * .012, W * .007); g.fill(); }
        g.fillStyle = 'rgba(255,240,210,.35)'; ellipse(g, x - rx * .3, ty - ry * .3, rx * .4, ry * .35); g.fill();
        break;
      }
      case 'roll': {
        const h = s.h * W, ex = x + rx;
        const gr = g.createLinearGradient(0, ty - ry, 0, ty + h); gr.addColorStop(0, '#e8c088'); gr.addColorStop(1, '#c08a4c');
        g.fillStyle = gr; rr(g, x - rx, ty - ry, rx * 2, h + ry, h * .45); g.fill();
        // 切面：一圈圈卷起来的蛋糕和奶油
        const cy = ty + h * .35, R0 = h * .62;
        g.fillStyle = '#f4dcae'; ellipse(g, ex - R0 * .35, cy, R0 * .5, R0); g.fill();
        g.strokeStyle = creamCol; g.lineWidth = R0 * .18; g.beginPath();
        for (let t = 0; t < 1; t += .02) { const a = t * TAU * 2.2, rr2 = R0 * .85 * (1 - t); const px = ex - R0 * .35 + Math.cos(a) * rr2 * .5, py = cy + Math.sin(a) * rr2; t ? g.lineTo(px, py) : g.moveTo(px, py); }
        g.stroke();
        g.fillStyle = shade(creamCol, .2, .9); ellipse(g, x, ty, rx * .95, ry); g.fill();
        break;
      }
      case 'macaron': {
        const r = W * .3, shell = creamCol;
        for (const [yy, top] of [[y - W * .08, false], [y - W * .28, true]]) {
          const gr = g.createRadialGradient(x - r * .3, yy - r * .3, 1, x, yy, r * 1.1);
          gr.addColorStop(0, shade(shell, .35)); gr.addColorStop(1, shade(shell, -.12));
          g.fillStyle = gr; ellipse(g, x, yy, r, r * (top ? .42 : .34)); g.fill();
          // 裙边：一圈小气孔
          g.fillStyle = shade(shell, -.08); for (let i = 0; i < 18; i++) { const a = i / 18 * Math.PI; ellipse(g, x - Math.cos(a) * r * .97, yy + W * .03, W * .018, W * .014); g.fill(); }
        }
        g.fillStyle = '#fbf3e6'; ellipse(g, x, y - W * .18, r * .92, W * .045); g.fill();
        g.fillStyle = shade(shell, .3); ellipse(g, x, y + s.top * W, rx, ry); g.fill();
        break;
      }
    }
  }
  // 裱花：沿着她画的线，一颗颗挤出来的奶油花（带螺纹和高光）
  function rosette(g, x, y, r, col) {
    const gr = g.createRadialGradient(x - r * .35, y - r * .4, r * .1, x, y, r);
    gr.addColorStop(0, shade(col, .45)); gr.addColorStop(.7, col); gr.addColorStop(1, shade(col, -.18));
    g.fillStyle = gr; ellipse(g, x, y, r, r * .78); g.fill();
    g.strokeStyle = shade(col, -.2, .55); g.lineWidth = Math.max(.6, r * .12);
    g.beginPath(); for (let t = 0; t < 1; t += .05) { const a = t * TAU * 1.6, rr2 = r * .85 * (1 - t); const px = x + Math.cos(a) * rr2, py = y + Math.sin(a) * rr2 * .75; t ? g.lineTo(px, py) : g.moveTo(px, py); } g.stroke();
  }
  // 一块完整的甜点。r = { base, cream, items:[{t,u,v,a}], pipes:[{c,pts:[[u,v]]}], drizzle:[{c,pts}], dust, seed }
  function dessert(g, r, x, y, W, { plate: withPlate = true } = {}) {
    const creamCol = (CREAMS[r.cream] || CREAMS.plain).color;
    if (withPlate) plate(g, x, y + W * .02, W);
    softShadow(g, x, y, W * .42, W * .12, .22);
    baseBody(g, r.base, x, y, W, creamCol, r.seed || 1);
    const s = SHAPE[r.base] || SHAPE.sponge;
    // 糖粉（先撒，装饰压在上面）
    if (r.dust) { const R = rng((r.seed || 1) + 7); g.fillStyle = 'rgba(255,255,255,.85)'; for (let i = 0; i < 90; i++) { const a = R() * TAU, d = Math.sqrt(R()); const [px, py] = topPoint(r.base, x, y, W, Math.cos(a) * d * .95, Math.sin(a) * d * .95); g.beginPath(); g.arc(px, py, W * .006, 0, TAU); g.fill(); } }
    // 淋酱：光亮的一道道
    for (const d of r.drizzle || []) {
      g.lineCap = 'round'; g.lineJoin = 'round';
      g.strokeStyle = d.c || '#6b4a3a'; g.lineWidth = W * .022; g.beginPath();
      d.pts.forEach(([u, v], i) => { const [px, py] = topPoint(r.base, x, y, W, u, v); i ? g.lineTo(px, py) : g.moveTo(px, py); }); g.stroke();
      g.strokeStyle = 'rgba(255,255,255,.35)'; g.lineWidth = W * .006; g.stroke();
    }
    // 裱花 + 装饰按前后排好（靠后的先画）
    const draws = [];
    for (const p of r.pipes || []) {
      let last = null;
      for (const [u, v] of p.pts) {
        const q = topPoint(r.base, x, y, W, u, v);
        if (last && Math.hypot(q[0] - last[0], q[1] - last[1]) < W * .045) continue;
        last = q; draws.push({ y: q[1], f: () => rosette(g, q[0], q[1] - W * .02, W * .05, p.c || creamCol) });
      }
    }
    for (const it of r.items || []) {
      const [px, py] = topPoint(r.base, x, y, W, it.u, it.v);
      draws.push({ y: py, f: () => topping(g, it.t, px, py - W * .03, W * .14 * (it.s || 1), it.a || 0) });
    }
    draws.sort((a, b) => a.y - b.y).forEach((d) => d.f());
  }

  // ———————————————— 人物 ————————————————
  // 客人：Q 版，大头、小身子。look = {hair, top, bottom, skin, style}，mood: happy / think / sad
  function person(g, look, x, y, k, { t = 0, walk = false, mood = 'idle', facing = 1, eating = false } = {}) {
    const bob = walk ? Math.abs(Math.sin(t * 9)) * 2.2 * k : Math.sin(t * 2) * .6 * k;
    const sw = walk ? Math.sin(t * 9) * 5 * k : 0;
    softShadow(g, x, y, 18 * k, 5 * k, .2);
    g.save(); g.translate(x, y - bob); g.scale(facing, 1);
    // 腿
    g.fillStyle = look.legs || '#5a4a48';
    rr(g, -9 * k + sw * .3, -22 * k, 7 * k, 22 * k, 3 * k); g.fill(); rr(g, 2 * k - sw * .3, -22 * k, 7 * k, 22 * k, 3 * k); g.fill();
    g.fillStyle = '#4a3a33'; ellipse(g, -5.5 * k + sw * .3, -1 * k, 5 * k, 2.6 * k); g.fill(); ellipse(g, 5.5 * k - sw * .3, -1 * k, 5 * k, 2.6 * k); g.fill();
    // 下装（裙子 / 裤子）
    g.fillStyle = look.bottom; g.beginPath(); g.moveTo(-12 * k, -38 * k); g.lineTo(-15 * k, -20 * k); g.quadraticCurveTo(0, -17 * k, 15 * k, -20 * k); g.lineTo(12 * k, -38 * k); g.closePath(); g.fill();
    // 上衣
    const tg = g.createLinearGradient(-14 * k, 0, 14 * k, 0); tg.addColorStop(0, shade(look.top, -.1)); tg.addColorStop(.45, shade(look.top, .12)); tg.addColorStop(1, shade(look.top, -.14));
    g.fillStyle = tg; rr(g, -13 * k, -58 * k, 26 * k, 24 * k, 9 * k); g.fill();
    // 手臂
    g.fillStyle = shade(look.top, -.06);
    g.save(); g.translate(-12 * k, -54 * k); g.rotate(.25 + (walk ? -sw * .03 : 0)); rr(g, -4 * k, 0, 7 * k, 17 * k, 3.5 * k); g.fill(); g.fillStyle = look.skin || '#f6dccd'; ellipse(g, 0, 18 * k, 3.6 * k, 3.6 * k); g.fill(); g.restore();
    g.fillStyle = shade(look.top, -.06);
    g.save(); g.translate(12 * k, -54 * k); g.rotate(-.25 + (walk ? sw * .03 : 0) + (eating ? -1.6 : 0)); rr(g, -3 * k, 0, 7 * k, 17 * k, 3.5 * k); g.fill(); g.fillStyle = look.skin || '#f6dccd'; ellipse(g, 0, 18 * k, 3.6 * k, 3.6 * k); g.fill(); g.restore();
    // 头
    const hy = -78 * k, hr = 21 * k;
    if (look.style === 'long' || look.style === 'pony') { g.fillStyle = shade(look.hair, -.05); rr(g, -hr * 1.02, hy - hr * .2, hr * 2.04, hr * (look.style === 'long' ? 1.9 : 1.2), hr * .7); g.fill(); }
    const sg = g.createRadialGradient(-hr * .3, hy - hr * .2, hr * .2, 0, hy, hr * 1.1);
    sg.addColorStop(0, '#fbe9df'); sg.addColorStop(1, look.skin || '#f3d3c2');
    g.fillStyle = sg; ellipse(g, 0, hy, hr, hr * .96); g.fill();
    // 头发：后脑一片 + 刘海（几缕弧线）
    const hg = g.createLinearGradient(0, hy - hr, 0, hy); hg.addColorStop(0, shade(look.hair, .12)); hg.addColorStop(1, look.hair);
    g.fillStyle = hg; g.beginPath(); g.arc(0, hy - hr * .05, hr * 1.04, Math.PI * 1.02, Math.PI * 1.98); g.closePath(); g.fill();
    g.beginPath(); g.moveTo(-hr * 1.02, hy - hr * .05);
    for (let i = 0; i <= 6; i++) { const px = -hr + i * hr / 3, py = hy - hr * (.28 + (i % 2 ? .0 : .14)); g.quadraticCurveTo(px - hr * .16, hy - hr * .55, px, py); }
    g.lineTo(hr * 1.02, hy - hr * .05); g.closePath(); g.fill();
    if (look.style === 'bun') { g.beginPath(); g.arc(0, hy - hr * 1.12, hr * .38, 0, TAU); g.fill(); }
    if (look.style === 'pony') { g.beginPath(); g.ellipse(hr * .95, hy + hr * .1, hr * .25, hr * .6, -.4, 0, TAU); g.fill(); }
    if (look.style === 'short') { g.fillStyle = look.hair; ellipse(g, -hr * .92, hy - hr * .05, hr * .14, hr * .35); g.fill(); ellipse(g, hr * .92, hy - hr * .05, hr * .14, hr * .35); g.fill(); }
    // 脸
    g.fillStyle = '#3a2a26';
    if (mood === 'happy') { g.lineWidth = 2 * k; g.strokeStyle = '#3a2a26'; for (const s of [-1, 1]) { g.beginPath(); g.arc(s * hr * .36, hy + hr * .12, hr * .12, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); } }
    else for (const s of [-1, 1]) { ellipse(g, s * hr * .36, hy + hr * .1, hr * .1, hr * .14); g.fill(); g.fillStyle = '#fff'; ellipse(g, s * hr * .36 + hr * .03, hy + hr * .04, hr * .04, hr * .05); g.fill(); g.fillStyle = '#3a2a26'; }
    g.fillStyle = 'rgba(240,150,150,.45)'; ellipse(g, -hr * .56, hy + hr * .36, hr * .15, hr * .09); g.fill(); ellipse(g, hr * .56, hy + hr * .36, hr * .15, hr * .09); g.fill();
    g.strokeStyle = '#a5524e'; g.lineWidth = 1.6 * k; g.beginPath();
    if (mood === 'sad') g.arc(0, hy + hr * .55, hr * .14, Math.PI * 1.15, Math.PI * 1.85);
    else if (mood === 'think') { g.moveTo(-hr * .1, hy + hr * .45); g.lineTo(hr * .1, hy + hr * .45); }
    else g.arc(0, hy + hr * .32, hr * .15, Math.PI * .15, Math.PI * .85);
    g.stroke();
    // 小配件
    if (look.glasses) { g.strokeStyle = '#4a3a33'; g.lineWidth = 1.4 * k; for (const s of [-1, 1]) { g.beginPath(); g.arc(s * hr * .36, hy + hr * .1, hr * .2, 0, TAU); g.stroke(); } g.beginPath(); g.moveTo(-hr * .16, hy + hr * .1); g.lineTo(hr * .16, hy + hr * .1); g.stroke(); }
    if (look.bow) { g.fillStyle = look.bow; for (const s of [-1, 1]) { g.beginPath(); g.ellipse(hr * .55 + s * hr * .2, hy - hr * .78, hr * .2, hr * .13, s * .4, 0, TAU); g.fill(); } }
    if (look.cap) { g.fillStyle = look.cap; g.beginPath(); g.arc(0, hy - hr * .25, hr * 1.02, Math.PI * 1.05, Math.PI * 1.95); g.fill(); ellipse(g, hr * .7, hy - hr * .28, hr * .55, hr * .14); g.fill(); }
    g.restore();
  }

  // 她：店里的甜点师。棕色辫子、粉色蝴蝶结、粉毛衣、米白围裙（站在柜台后，只露上半身也行）
  function baker(g, x, y, k, t = 0, { mood = 'idle', busy = false } = {}) {
    const bob = Math.sin(t * 2.2) * .8 * k;
    softShadow(g, x, y, 20 * k, 5 * k, .18);
    g.save(); g.translate(x, y - bob);
    // 身子：粉毛衣 + 围裙
    g.fillStyle = '#6f4337'; rr(g, -9 * k, -20 * k, 7 * k, 20 * k, 3 * k); g.fill(); rr(g, 2 * k, -20 * k, 7 * k, 20 * k, 3 * k); g.fill();
    g.fillStyle = '#f7efe6'; g.beginPath(); g.moveTo(-13 * k, -40 * k); g.lineTo(-16 * k, -18 * k); g.quadraticCurveTo(0, -15 * k, 16 * k, -18 * k); g.lineTo(13 * k, -40 * k); g.fill();
    const tg = g.createLinearGradient(-14 * k, 0, 14 * k, 0); tg.addColorStop(0, '#dc94a2'); tg.addColorStop(.45, '#f2b8c2'); tg.addColorStop(1, '#d48a99');
    g.fillStyle = tg; rr(g, -14 * k, -62 * k, 28 * k, 26 * k, 10 * k); g.fill();
    g.fillStyle = '#fbf6ee'; rr(g, -9 * k, -56 * k, 18 * k, 36 * k, 4 * k); g.fill();   // 围裙
    g.strokeStyle = '#e8c4c8'; g.lineWidth = 1.2 * k; g.beginPath(); g.moveTo(-9 * k, -46 * k); g.lineTo(9 * k, -46 * k); g.stroke();
    g.fillStyle = '#f2b8c2'; ellipse(g, 0, -38 * k, 4 * k, 3 * k); g.fill();
    // 手（忙的时候一上一下）
    for (const s of [-1, 1]) {
      g.save(); g.translate(s * 13 * k, -57 * k); g.rotate(s * -.3 + (busy ? Math.sin(t * 10 + s) * .4 : 0));
      g.fillStyle = '#e8a6b2'; rr(g, -3.5 * k, 0, 7 * k, 16 * k, 3.5 * k); g.fill(); g.fillStyle = '#f8dfd2'; ellipse(g, 0, 17 * k, 3.6 * k, 3.6 * k); g.fill(); g.restore();
    }
    // 头
    const hy = -84 * k, hr = 22 * k;
    for (const s of [-1, 1]) {   // 两条辫子
      g.fillStyle = '#5b3a2e';
      for (let i = 0; i < 4; i++) { ellipse(g, s * hr * .95, hy + hr * (.35 + i * .32), hr * (.22 - i * .02), hr * .2); g.fill(); }
      g.fillStyle = '#f08ea0'; ellipse(g, s * hr * .95, hy + hr * 1.62, hr * .14, hr * .07); g.fill();
    }
    const sg = g.createRadialGradient(-hr * .3, hy - hr * .2, hr * .2, 0, hy, hr * 1.1); sg.addColorStop(0, '#fcece3'); sg.addColorStop(1, '#f5d6c6');
    g.fillStyle = sg; ellipse(g, 0, hy, hr, hr * .96); g.fill();
    const hg = g.createLinearGradient(0, hy - hr, 0, hy); hg.addColorStop(0, '#7a4f3e'); hg.addColorStop(1, '#5b3a2e');
    g.fillStyle = hg; g.beginPath(); g.arc(0, hy - hr * .05, hr * 1.05, Math.PI * 1.0, Math.PI * 2.0); g.closePath(); g.fill();
    g.beginPath(); g.moveTo(-hr * 1.04, hy);
    for (let i = 0; i <= 8; i++) { const px = -hr + i * hr / 4, py = hy - hr * (.18 + (i % 2 ? 0 : .12)); g.quadraticCurveTo(px - hr * .12, hy - hr * .5, px, py); }
    g.lineTo(hr * 1.04, hy); g.closePath(); g.fill();
    // 蝴蝶结
    g.fillStyle = '#f08ea0'; for (const s of [-1, 1]) { g.beginPath(); g.ellipse(hr * .55 + s * hr * .24, hy - hr * .82, hr * .24, hr * .15, s * .35, 0, TAU); g.fill(); }
    g.fillStyle = '#e57d91'; ellipse(g, hr * .55, hy - hr * .82, hr * .08, hr * .08); g.fill();
    // 脸：大眼睛、腮红
    for (const s of [-1, 1]) {
      if (mood === 'happy') { g.strokeStyle = '#3a2a26'; g.lineWidth = 2 * k; g.beginPath(); g.arc(s * hr * .37, hy + hr * .14, hr * .13, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); continue; }
      g.fillStyle = '#5a3426'; ellipse(g, s * hr * .37, hy + hr * .12, hr * .14, hr * .18); g.fill();
      g.fillStyle = '#2a1a16'; ellipse(g, s * hr * .37, hy + hr * .15, hr * .07, hr * .1); g.fill();
      g.fillStyle = '#fff'; ellipse(g, s * hr * .37 + hr * .05, hy + hr * .05, hr * .05, hr * .06); g.fill();
      g.strokeStyle = '#2b1d18'; g.lineWidth = 1.6 * k; g.beginPath(); g.arc(s * hr * .37, hy + hr * .14, hr * .19, Math.PI * 1.15, Math.PI * 1.85); g.stroke();
    }
    g.fillStyle = 'rgba(240,150,150,.5)'; ellipse(g, -hr * .58, hy + hr * .4, hr * .16, hr * .09); g.fill(); ellipse(g, hr * .58, hy + hr * .4, hr * .16, hr * .09); g.fill();
    g.strokeStyle = '#b9605e'; g.lineWidth = 1.6 * k; g.beginPath(); g.arc(0, hy + hr * .36, hr * .13, Math.PI * .15, Math.PI * .85); g.stroke();
    g.restore();
  }

  // clawd：橙色的小方块，眼睛那么高两侧各一块扁扁的手，底下四根小腿（跟 2D 里一样），头上一顶小厨师帽
  function clawd(g, x, y, k, t = 0, { job = null, walk = false, mood = 'idle', facing = 1 } = {}) {
    const C = '#dd7a5c', CL = '#ec9576', CD = '#c86a4e';
    const bob = walk ? Math.abs(Math.sin(t * 10)) * 2.5 * k : Math.sin(t * 2.6) * .7 * k;
    softShadow(g, x, y, 22 * k, 5 * k, .2);
    g.save(); g.translate(x, y); g.scale(facing, 1);
    const legs = [-15, -6, 6, 15];
    legs.forEach((lx, i) => { const up = walk ? Math.max(0, Math.sin(t * 10 + i * Math.PI / 2)) * 2.5 * k : 0; g.fillStyle = i % 2 ? CD : C; rr(g, lx * k - 2.5 * k, -11 * k - up, 5 * k, 11 * k, 1.6 * k); g.fill(); });
    g.translate(0, -bob);
    const bg = g.createLinearGradient(0, -40 * k, 0, -9 * k); bg.addColorStop(0, CL); bg.addColorStop(1, C);
    g.fillStyle = bg; rr(g, -22 * k, -40 * k, 44 * k, 31 * k, 8 * k); g.fill();
    g.fillStyle = 'rgba(255,255,255,.18)'; rr(g, -18 * k, -38 * k, 22 * k, 6 * k, 3 * k); g.fill();
    // 手：两侧眼睛那么高的扁方块（招呼客人的时候挥一挥）
    const wave = job === 'greet' ? Math.sin(t * 8) * .5 : 0;
    g.fillStyle = C;
    g.save(); g.translate(-22 * k, -29 * k); rr(g, -7 * k, -5 * k, 8 * k, 10 * k, 2.5 * k); g.fill(); g.restore();
    g.save(); g.translate(22 * k, -29 * k); g.rotate(-wave); rr(g, -1 * k, -5 * k, 8 * k, 10 * k, 2.5 * k); g.fill(); g.restore();
    // 眼睛：竖着的小药丸
    g.fillStyle = '#1d1614';
    if (mood === 'happy') { g.strokeStyle = '#1d1614'; g.lineWidth = 2 * k; for (const s of [-1, 1]) { g.beginPath(); g.arc(s * 8 * k, -26 * k, 3 * k, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); } }
    else for (const s of [-1, 1]) { rr(g, s * 8 * k - 2.2 * k, -31 * k, 4.4 * k, 9 * k, 2.2 * k); g.fill(); g.fillStyle = '#fff'; ellipse(g, s * 8 * k + .8 * k, -29 * k, 1 * k, 1.3 * k); g.fill(); g.fillStyle = '#1d1614'; }
    g.fillStyle = 'rgba(255,170,150,.6)'; ellipse(g, -14 * k, -20 * k, 3 * k, 1.8 * k); g.fill(); ellipse(g, 14 * k, -20 * k, 3 * k, 1.8 * k); g.fill();
    // 厨师帽
    g.fillStyle = '#fbf8f2'; rr(g, -10 * k, -46 * k, 20 * k, 7 * k, 2 * k); g.fill();
    for (const [cx, cy, r] of [[-6, -50, 6], [0, -53, 7], [6, -50, 6]]) { g.beginPath(); g.arc(cx * k, cy * k, r * k, 0, TAU); g.fill(); }
    g.strokeStyle = 'rgba(200,190,180,.6)'; g.lineWidth = .8 * k; g.beginPath(); g.moveTo(-10 * k, -42 * k); g.lineTo(10 * k, -42 * k); g.stroke();
    // 干活的家伙
    if (job === 'clean') { g.save(); g.translate(26 * k, -20 * k); g.rotate(.4 + Math.sin(t * 6) * .25); g.fillStyle = '#a77f5c'; rr(g, -1.2 * k, -20 * k, 2.4 * k, 30 * k, 1 * k); g.fill(); g.fillStyle = '#e8d29a'; g.beginPath(); g.moveTo(-6 * k, 10 * k); g.lineTo(6 * k, 10 * k); g.lineTo(4 * k, 18 * k); g.lineTo(-4 * k, 18 * k); g.fill(); g.restore(); }
    if (job === 'cashier') { g.fillStyle = '#c8a96c'; ellipse(g, 0, -12 * k, 8 * k, 2 * k); g.fill(); }
    g.restore();
  }

  // ———————————————— 集市里的食材小图 ————————————————
  const ING = {
    flour(g, k) { const gr = g.createLinearGradient(-k * .4, 0, k * .4, 0); gr.addColorStop(0, '#e6dccb'); gr.addColorStop(.5, '#faf5ec'); gr.addColorStop(1, '#ddd1bd'); g.fillStyle = gr; g.beginPath(); g.moveTo(-k * .32, -k * .3); g.quadraticCurveTo(-k * .45, k * .45, -k * .3, k * .48); g.lineTo(k * .3, k * .48); g.quadraticCurveTo(k * .45, k * .45, k * .32, -k * .3); g.closePath(); g.fill(); g.fillStyle = '#c9b292'; g.beginPath(); g.moveTo(-k * .34, -k * .3); g.lineTo(-k * .2, -k * .45); g.lineTo(k * .2, -k * .45); g.lineTo(k * .34, -k * .3); g.fill(); g.strokeStyle = '#a9b89a'; g.lineWidth = k * .05; g.beginPath(); g.moveTo(-k * .12, k * .05); g.quadraticCurveTo(0, -k * .12, k * .12, k * .05); g.stroke(); g.beginPath(); g.moveTo(0, -k * .05); g.lineTo(0, k * .25); g.stroke(); },
    butter(g, k) { g.fillStyle = '#f3dc90'; rr(g, -k * .42, -k * .12, k * .84, k * .36, k * .06); g.fill(); g.fillStyle = '#f9eab4'; g.beginPath(); g.moveTo(-k * .42, -k * .12); g.lineTo(-k * .26, -k * .28); g.lineTo(k * .5, -k * .28); g.lineTo(k * .42, -k * .12); g.fill(); g.fillStyle = '#fbf7ef'; rr(g, -k * .1, -k * .14, k * .52, k * .4, k * .04); g.fill(); g.fillStyle = '#d9a46c'; g.fillRect(k * .02, k * .02, k * .3, k * .05); },
    egg(g, k) { for (const [x, s2] of [[-k * .18, .9], [k * .16, 1]]) { const gr = g.createRadialGradient(x - k * .08, -k * .12, k * .02, x, 0, k * .36 * s2); gr.addColorStop(0, '#fffaf0'); gr.addColorStop(1, '#ead6b4'); g.fillStyle = gr; g.beginPath(); g.ellipse(x, k * .04, k * .24 * s2, k * .32 * s2, x < 0 ? -.2 : .15, 0, TAU); g.fill(); } },
    sugar(g, k) { for (const [x, y] of [[-k * .2, k * .12], [k * .18, k * .12], [0, -k * .16]]) { g.fillStyle = '#fbfaf6'; rr(g, x - k * .17, y - k * .17, k * .34, k * .34, k * .05); g.fill(); g.fillStyle = '#e9e4da'; g.fillRect(x - k * .17, y + k * .08, k * .34, k * .09); } },
    milk(g, k) { const gr = g.createLinearGradient(-k * .25, 0, k * .25, 0); gr.addColorStop(0, '#e9eef0'); gr.addColorStop(.5, '#ffffff'); gr.addColorStop(1, '#dfe5e8'); g.fillStyle = gr; g.beginPath(); g.moveTo(-k * .1, -k * .48); g.lineTo(k * .1, -k * .48); g.lineTo(k * .1, -k * .32); g.quadraticCurveTo(k * .26, -k * .22, k * .26, -k * .05); g.lineTo(k * .26, k * .46); g.lineTo(-k * .26, k * .46); g.lineTo(-k * .26, -k * .05); g.quadraticCurveTo(-k * .26, -k * .22, -k * .1, -k * .32); g.fill(); g.fillStyle = '#a9c1d9'; g.fillRect(-k * .26, k * .02, k * .52, k * .2); g.fillStyle = '#c8a96c'; g.fillRect(-k * .11, -k * .52, k * .22, k * .07); },
    cream(g, k) { g.fillStyle = '#f6f1e8'; g.fillRect(-k * .28, -k * .2, k * .56, k * .66); g.fillStyle = '#ece4d6'; g.beginPath(); g.moveTo(-k * .28, -k * .2); g.lineTo(0, -k * .45); g.lineTo(k * .28, -k * .2); g.fill(); g.fillStyle = '#e8b4b8'; g.fillRect(-k * .28, k * .05, k * .56, k * .16); g.fillStyle = '#fff'; g.beginPath(); g.arc(0, k * .13, k * .06, 0, TAU); g.fill(); },
    cocoa(g, k) { g.save(); g.rotate(-.25); g.fillStyle = '#6b4a3a'; rr(g, -k * .4, -k * .26, k * .8, k * .52, k * .05); g.fill(); g.strokeStyle = '#4e3428'; g.lineWidth = k * .03; for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(-k * .4 + i * k * .2, -k * .26); g.lineTo(-k * .4 + i * k * .2, k * .26); g.stroke(); } g.beginPath(); g.moveTo(-k * .4, 0); g.lineTo(k * .4, 0); g.stroke(); g.fillStyle = '#c8a96c'; g.beginPath(); g.moveTo(k * .1, -k * .26); g.lineTo(k * .4, -k * .26); g.lineTo(k * .4, k * .26); g.lineTo(k * .25, k * .26); g.fill(); g.restore(); },
    matcha(g, k) { g.fillStyle = '#e8dccb'; g.beginPath(); g.ellipse(0, k * .08, k * .42, k * .14, 0, 0, TAU); g.fill(); g.beginPath(); g.moveTo(-k * .42, k * .08); g.quadraticCurveTo(-k * .38, k * .42, 0, k * .44); g.quadraticCurveTo(k * .38, k * .42, k * .42, k * .08); g.fill(); g.fillStyle = '#93a86e'; g.beginPath(); g.ellipse(0, k * .06, k * .34, k * .1, 0, 0, TAU); g.fill(); g.fillStyle = '#a9bd84'; g.beginPath(); g.arc(-k * .05, k * .02, k * .14, Math.PI, 0); g.fill(); },
    cheese(g, k) { g.fillStyle = '#f4dd8e'; g.beginPath(); g.moveTo(-k * .42, k * .3); g.lineTo(k * .42, k * .3); g.lineTo(k * .42, -k * .02); g.lineTo(-k * .42, k * .12); g.fill(); g.fillStyle = '#f8e9b4'; g.beginPath(); g.moveTo(-k * .42, k * .12); g.lineTo(k * .42, -k * .02); g.lineTo(k * .2, -k * .3); g.fill(); g.fillStyle = '#e6c46a'; for (const [x, y, r] of [[-k * .2, k * .2, .06], [k * .15, k * .14, .05], [k * .3, k * .22, .035]]) { g.beginPath(); g.arc(x, y, k * r, 0, TAU); g.fill(); } },
    caramel(g, k) { g.fillStyle = 'rgba(230,240,240,.85)'; rr(g, -k * .26, -k * .28, k * .52, k * .7, k * .1); g.fill(); g.fillStyle = '#c7894a'; rr(g, -k * .22, -k * .05, k * .44, k * .43, k * .08); g.fill(); g.fillStyle = '#b48a68'; rr(g, -k * .28, -k * .4, k * .56, k * .14, k * .04); g.fill(); g.fillStyle = 'rgba(255,255,255,.5)'; g.fillRect(-k * .16, -k * .2, k * .05, k * .4); },
    goldleaf(g, k) { TOP.gold(g, k * 1.1); },
    nuts(g, k) { TOP.nut(g, k * .9); g.translate(k * .15, k * .18); TOP.nut(g, k * .8); },
    sprinkles(g, k) { TOP.sprinkle(g, k * 1.3); },
    rose(g, k) { TOP.petal(g, k); g.translate(-k * .1, k * .15); g.rotate(.8); TOP.petal(g, k * .8); },
  };
  const ING_TOP = { strawberry: 'strawberry', blueberry: 'blueberry', lemon: 'lemon', mint: 'mint', mango: 'mango', peach: 'peach', sakura: 'sakura', chestnut: 'chestnut' };
  function ingredient(g, key, x, y, k) {
    g.save(); g.translate(x, y);
    if (ING[key]) ING[key](g, k); else if (ING_TOP[key]) TOP[ING_TOP[key]](g, k * 1.1);
    g.restore();
  }

  return { TAU, hex, rgb, shade, rng, ellipse, rr, softShadow, topping, dessert, topPoint, SHAPE, plate, person, baker, clawd, rosette, ingredient };
})();
