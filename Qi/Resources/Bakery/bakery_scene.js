// 店里的场景：一间比手机屏宽的小店（可以左右拖着看），跟甜点一样走 INK，三种画风都能画。
// 场景坐标：宽 760、高 600；墙到 y = 330，往下是地板（z 从 0 靠墙到 1 靠前）。
// 分几层画（游戏那边按层缓存，不用每帧重画）：
//   sky        窗外的天（会变：时间、天气、雨雪）
//   background 墙、石膏线、护墙板、窗框窗帘（窗玻璃那块是空的，露出后面的天）、门、吊灯壁灯、架子、黑板、藤蔓、地板、地毯
//   counterBack / 她 / front  收银台后面那一截 → 她 → 柜台正面和展示柜（展示柜里的甜点跟着卖的变）
'use strict';

const SCENE = (() => {
  const { TAU, ell, paint, stroke, tone, rng, sparkle, trace } = INK;
  const WW = 760, WH = 600, FLOOR = 330;
  const floorY = (z) => FLOOR + 22 + z * 228;
  const depthK = (z) => .82 + .32 * z;
  const CASE = { x: 446, w: 204, top: 296, base: 434 };
  const COUNTER = { x: 658, w: 102, top: 362, base: 442 };
  const WIN = { x: 162, y: 64, w: 146, h: 178 };
  const S = () => INK.style();
  const box = (x, y, w, h) => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
  function rbox(x, y, w, h, r) { const out = []; for (const [cx, cy, a0] of [[x + w - r, y + r, -Math.PI / 2], [x + w - r, y + h - r, 0], [x + r, y + h - r, Math.PI / 2], [x + r, y + r, Math.PI]]) out.push(...ell(cx, cy, r, r, a0, a0 + Math.PI / 2, S() === 'paper' ? 2 : 5, 1)); return out; }
  const archPts = (x, y, w, h) => [[x, y + h], [x, y + w / 2], ...ell(x + w / 2, y + w / 2, w / 2, w / 2, Math.PI, TAU, S() === 'paper' ? 7 : 24, 2), [x + w, y + w / 2], [x + w, y + h]];
  const GOLD = '#d4b06a';

  // ———— 窗外的天 ————
  function sky(g, clock, weather, t) {
    const { x, y, w, h } = WIN, hour = clock / 60;
    const dusk = clamp01((hour - 16.5) / 2);
    const gr = g.createLinearGradient(0, y, 0, y + h);
    const rainy = weather === 'rain' || weather === 'snow' || weather === 'cloudy';
    gr.addColorStop(0, mix(rainy ? '#b9c4cf' : '#a9cbe3', '#e9a88f', dusk)); gr.addColorStop(1, mix(rainy ? '#e3e6ea' : '#eef3f0', '#f6d6b6', dusk));
    g.fillStyle = gr; g.fillRect(x - 4, y - 4, w + 8, h + 8);
    // 街对面：一排小房子、一棵树、路灯
    paint(g, [[x - 4, y + h * .62], [x + 30, y + h * .62], [x + 30, y + h * .5], [x + 44, y + h * .42], [x + 58, y + h * .5], [x + 58, y + h], [x - 4, y + h]], mix('#d8c9bb', '#c9a99a', dusk), { lw: .8, line: S() !== 'story' || true, alpha: .8 });
    paint(g, [[x + 70, y + h * .55], [x + 120, y + h * .55], [x + 120, y + h], [x + 70, y + h]], mix('#e2d4c4', '#d0b0a0', dusk), { lw: .8, alpha: .8 });
    for (let i = 0; i < 3; i++) paint(g, box(x + 78 + i * 13, y + h * .62, 7, 9), dusk > .5 ? '#f6d68f' : '#b9c9d6', { lw: .5, flat: true, alpha: .9 });
    paint(g, ell(x + 64, y + h * .6, 16, 18, 0, TAU, 0, 5), mix('#9bb486', '#8a9a74', dusk), { lw: .8, alpha: .85 });
    if (!rainy) paint(g, ell(x + w * .78, y + h * .2, 10, 10, 0, TAU, 0, 6), dusk > .5 ? '#f6c9a0' : '#fff4d6', { lw: .6, flat: true, line: false, alpha: .95 });
    if (rainy) for (const [cx, cy] of [[.3, .18], [.72, .3]]) paint(g, [...ell(x + w * cx - 10 + Math.sin(t * .1) * 6, y + h * cy, 10, 7, Math.PI * .6, Math.PI * 2.4, 0, 7), ...ell(x + w * cx + 6 + Math.sin(t * .1) * 6, y + h * cy - 3, 12, 9, Math.PI, TAU, 0, 8)], '#ffffff', { lw: .6, flat: true, alpha: .85 });
    if (weather === 'rain') { g.strokeStyle = 'rgba(120,140,170,.55)'; g.lineWidth = 1; for (let i = 0; i < 26; i++) { const px = x + ((i * 37 + t * 60) % w), py = y + ((i * 53 + t * 220) % h); g.beginPath(); g.moveTo(px, py); g.lineTo(px - 3, py + 9); g.stroke(); } }
    if (weather === 'snow') { g.fillStyle = 'rgba(255,255,255,.95)'; for (let i = 0; i < 30; i++) { const px = x + ((i * 41 + Math.sin(t + i) * 8) % w + w) % w, py = y + ((i * 29 + t * 25) % h); g.beginPath(); g.arc(px, py, 1.6, 0, TAU); g.fill(); } }
  }
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  function mix(a, b, t) { const A = INK.hex(a), B = INK.hex(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); }

  // ———— 墙 ————
  function wall(g, wp) {
    g.fillStyle = wp.a; g.fillRect(0, 0, WW, FLOOR);
    g.save(); g.beginPath(); g.rect(0, 22, WW, 228); g.clip();
    const R = rng(3);
    if (wp.kind === 'stripe') { for (let x = 0; x < WW; x += 34) { paint(g, box(x, 0, 13, 260), wp.b, { lw: .6, flat: true, line: false }); if (S() !== 'paper') stroke(g, [[x + 16, 22], [x + 16, 250]], 'rgba(255,255,255,.45)', .8); } }
    if (wp.kind === 'check') { g.globalAlpha = .55; for (let x = 0; x < WW; x += 44) g.fillStyle = wp.b, g.fillRect(x, 0, 12, 260); for (let y = 22; y < 252; y += 44) g.fillRect(0, y, WW, 12); g.globalAlpha = 1; }
    if (wp.kind === 'dot') { g.fillStyle = wp.b; for (let y = 34; y < 252; y += 28) for (let x = (y / 28 % 2) * 14 + 10; x < WW; x += 28) { g.beginPath(); g.arc(x, y, 3.2, 0, TAU); g.fill(); } }
    if (wp.kind === 'floral' || wp.kind === 'damask') {
      for (let y = 46; y < 252; y += 52) for (let x = (Math.round(y / 52) % 2) * 32 + 18; x < WW; x += 64) {
        if (wp.kind === 'floral') { for (let i = 0; i < 5; i++) { const a = i / 5 * TAU; paint(g, ell(x + Math.cos(a) * 5, y + Math.sin(a) * 5, 4, 4, 0, TAU, 6, i), tone(wp.b, .1), { lw: .5, flat: true, line: S() === 'story' }); } paint(g, ell(x, y, 2.4, 2.4, 0, TAU, 5, 1), '#e9d9a6', { lw: .4, flat: true }); stroke(g, [[x + 6, y + 6], [x + 13, y + 10 + R() * 3], [x + 19, y + 7]], '#b9c7a6', 1.2); paint(g, ell(x + 15, y + 12, 4, 2, .5, .5 + TAU, 6, 2), '#b9c7a6', { lw: .4, flat: true, line: false }); }
        else paint(g, [[x, y - 24], [x + 14, y - 10], [x + 18, y], [x + 14, y + 10], [x, y + 24], [x - 14, y + 10], [x - 18, y], [x - 14, y - 10]], tone(wp.b, 0, .7), { lw: .5, flat: true, line: false });
      }
    }
    g.restore();
    // 顶上的石膏线：一道宽线脚 + 一排齿饰
    paint(g, box(0, 0, WW, 20), '#f6efe4', { lw: .8, flat: true });
    for (let x = 6; x < WW; x += 14) paint(g, box(x, 20, 7, 6), '#efe4d4', { lw: .5, flat: true, line: S() !== 'paper' });
    paint(g, box(0, 26, WW, 3), GOLD, { lw: .5, flat: true, gloss: true });
    // 护墙板：一块块嵌板，金色内框
    paint(g, box(0, 250, WW, FLOOR - 250), '#f3eadc', { lw: .8 });
    paint(g, box(0, 246, WW, 6), '#e3d3bb', { lw: .6, flat: true });
    paint(g, box(0, 244, WW, 2.5), GOLD, { lw: .4, flat: true, line: false });
    for (let x = 12; x < WW; x += 66) { paint(g, rbox(x, 260, 52, 56, 4), '#f6efe4', { lw: .7, flat: true }); if (S() !== 'paper') { g.strokeStyle = 'rgba(212,176,106,.7)'; g.lineWidth = 1; trace(g, rbox(x + 5, 265, 42, 46, 3)); g.stroke(); } }
    paint(g, box(0, FLOOR - 9, WW, 9), '#d9c3a3', { lw: .7, flat: true });
  }
  // 窗：拱形窗框、窗格，挖空玻璃那块（露出后面画的天），蕾丝窗帘、流苏绑带、上面的帘头，窗台花箱
  function windowFrame(g) {
    const { x, y, w, h } = WIN;
    g.save(); g.globalCompositeOperation = 'destination-out'; trace(g, archPts(x, y, w, h)); g.fill(); g.restore();
    // 窗框和窗格
    g.save(); g.lineJoin = 'round';
    trace(g, archPts(x, y, w, h)); g.strokeStyle = '#fbf7f1'; g.lineWidth = 10; g.stroke();
    if (S() !== 'paper') { g.strokeStyle = S() === 'candy' ? '#5b3b30' : 'rgba(150,120,90,.7)'; g.lineWidth = S() === 'candy' ? 2 : 1; trace(g, archPts(x - 5, y - 5, w + 10, h + 5)); g.stroke(); }
    g.strokeStyle = '#fbf7f1'; g.lineWidth = 4;
    g.beginPath(); g.moveTo(x + w / 2, y + 4); g.lineTo(x + w / 2, y + h); for (const yy of [y + h * .52, y + h * .78]) { g.moveTo(x, yy); g.lineTo(x + w, yy); } g.stroke();
    g.beginPath(); g.arc(x + w / 2, y + w / 2, w * .22, Math.PI, TAU); g.stroke();
    g.restore();
    // 窗帘：两边垂下来，下面挽起，边上一溜蕾丝
    for (const s of [-1, 1]) {
      const cx = s < 0 ? x - 4 : x + w + 4, dir = -s;
      const pts = [[cx - 18 * dir, y - 14], [cx + 30 * dir, y - 14], [cx + 26 * dir, y + 60], [cx + 8 * dir, y + 112], [cx + 4 * dir, y + 150], [cx + 10 * dir, y + h + 10], [cx - 20 * dir, y + h + 10], [cx - 20 * dir, y - 14]];
      paint(g, pts, '#f4dfdc', { lw: 1, seed: 20 + s });
      if (S() !== 'paper') for (let i = 0; i < 4; i++) stroke(g, [[cx + (i * 7 - 8) * dir, y - 10], [cx + (i * 5 - 6) * dir, y + 100], [cx + (i * 4 - 10) * dir, y + h + 6]], 'rgba(200,150,150,.5)', .8);
      for (let i = 0; i < 16; i++) { const t = i / 15, px = cx + (30 - 22 * t) * dir + (t > .55 ? -10 * dir * (t - .55) : 0), py = y - 14 + t * (h + 24); paint(g, ell(px, py, 3, 3, 0, TAU, 6, i), '#fbf8f2', { lw: .5, flat: true, line: S() === 'story' }); }
      // 流苏绑带
      paint(g, ell(cx + 8 * dir, y + 112, 9, 4, 0, TAU, 0, 30), GOLD, { lw: .7, gloss: true, flat: true });
      paint(g, [[cx + 8 * dir - 2, y + 115], [cx + 8 * dir + 2, y + 115], [cx + 8 * dir + 4, y + 130], [cx + 8 * dir - 4, y + 130]], tone(GOLD, -.1), { lw: .5, flat: true });
    }
    // 帘头：一道弧形的荷叶边帘头 + 金色帘杆
    paint(g, box(x - 40, y - 22, w + 80, 5), GOLD, { lw: .5, gloss: true, flat: true });
    for (const s of [-1, 1]) paint(g, ell(s < 0 ? x - 42 : x + w + 42, y - 19.5, 5, 5, 0, TAU, 0, 31), GOLD, { lw: .5, gloss: true, flat: true });
    const val = [[x - 36, y - 18], [x + w + 36, y - 18]]; for (let i = 6; i >= 0; i--) { const px = x - 36 + i / 6 * (w + 72); val.push([px, y - 2 + (i % 2 ? 0 : 10)]); }
    paint(g, val, '#ecc9c8', { lw: 1, seed: 33 });
    // 窗台和花箱，花开得满出来
    paint(g, box(x - 14, y + h, w + 28, 9), '#f3ece2', { lw: .8 });
    paint(g, rbox(x + 2, y + h - 20, w - 4, 20, 4), '#b48a68', { lw: 1, seed: 34 });
    const R = rng(4);
    for (let i = 0; i < 13; i++) { const fx = x + 8 + i * (w - 16) / 12, fy = y + h - 22 - R() * 8; paint(g, ell(fx, fy + 4, 7, 5, 0, TAU, 0, i), i % 2 ? '#8fae7c' : '#7d9d6c', { lw: .6, flat: true }); }
    for (let i = 0; i < 11; i++) { const fx = x + 12 + i * (w - 24) / 10 + (R() - .5) * 4, fy = y + h - 26 - R() * 10, c = ['#f3c4cf', '#fff6e0', '#e8b4b8', '#c7bcd8'][i % 4]; for (let p = 0; p < 5; p++) { const a = p / 5 * TAU; paint(g, ell(fx + Math.cos(a) * 2.6, fy + Math.sin(a) * 2.6, 2.4, 2.4, 0, TAU, 5, p), c, { lw: .35, flat: true, line: S() !== 'paper' }); } paint(g, ell(fx, fy, 1.3, 1.3, 0, TAU, 5, 1), '#f1dca0', { lw: .3, flat: true, line: false }); }
    for (let i = 0; i < 4; i++) stroke(g, [[x + 14 + i * 38, y + h - 2], [x + 10 + i * 38, y + h + 14], [x + 16 + i * 38, y + h + 24]], '#8fae7c', 1.2);
  }
  // 门：上面一扇小拱窗，门上一个花环，铜把手、门铃，门口一块小地垫
  function door(g, openK, t) {
    const x = 24, y = 104, w = 86, h = FLOOR - 104;
    paint(g, [[x - 10, y + h], [x - 10, y + 10], ...ell(x + w / 2, y + 10, w / 2 + 10, 26, Math.PI, TAU, 0, 40), [x + w + 10, y + 10], [x + w + 10, y + h]], '#efe4d4', { lw: 1 });
    paint(g, box(x, y, w, h), '#3e3a3a', { lw: .8, flat: true, line: false });
    g.fillStyle = 'rgba(205,220,228,.95)'; g.fillRect(x, y, w, h * .55);
    const dw = w * (1 - openK * .78);
    paint(g, box(x, y, dw, h), '#a9b89a', { lw: 1, seed: 41 });
    paint(g, rbox(x + dw * .14, y + 12, dw * .72, h * .44, 8), '#dcebf0', { lw: .8, gloss: true, seed: 42 });
    stroke(g, [[x + dw / 2, y + 12], [x + dw / 2, y + 12 + h * .44]], '#fbf7f1', 2.5);
    paint(g, rbox(x + dw * .14, y + h * .6, dw * .72, h * .32, 4), tone('#a9b89a', -.06), { lw: .7, flat: true });
    paint(g, ell(x + dw - 10, y + h * .58, 3.8, 3.8, 0, TAU, 0, 43), GOLD, { lw: .5, gloss: true, flat: true });
    if (openK < .3) { // 门上的花环
      const cx = x + dw / 2, cy = y + h * .3;
      for (let i = 0; i < 16; i++) { const a = i / 16 * TAU; g.save(); g.translate(cx + Math.cos(a) * 15, cy + Math.sin(a) * 15); g.rotate(a + 1.2); paint(g, ell(0, 0, 6, 3, 0, TAU, 6, i), i % 2 ? '#8fae7c' : '#6f9a6a', { lw: .4, flat: true }); g.restore(); }
      for (let i = 0; i < 5; i++) { const a = i / 5 * TAU + .3; paint(g, ell(cx + Math.cos(a) * 15, cy + Math.sin(a) * 15, 3.2, 3.2, 0, TAU, 6, i), ['#f3c4cf', '#fff6e0', '#e8b4b8'][i % 3], { lw: .4, flat: true }); }
      for (const s of [-1, 1]) paint(g, [[cx, cy + 15], [cx + s * 9, cy + 20], [cx + s * 6, cy + 27]], '#e8b4b8', { lw: .5, flat: true });
    }
    // 门铃
    const sw = Math.sin(t * 18) * openK * .5;
    g.save(); g.translate(x + w + 3, y - 2); g.rotate(sw);
    stroke(g, [[0, -8], [0, 4]], '#8a7a6a', 1);
    paint(g, [[-6, 14], [-5, 6], [0, 2], [5, 6], [6, 14]], GOLD, { lw: .5, gloss: true, flat: true });
    g.restore();
  }
  // 水晶吊灯 + 两盏壁灯（晚上亮一点）
  function lights(g, clock) {
    const lit = Math.max(.35, Math.min(1, (clock / 60 - 15) / 3));
    const cx = 392;
    stroke(g, [[cx, 0], [cx, 40]], '#8a7a6a', 1.2);
    const glow = g.createRadialGradient(cx, 66, 6, cx, 66, 150); glow.addColorStop(0, `rgba(255,214,150,${.3 * lit})`); glow.addColorStop(1, 'rgba(255,214,150,0)');
    g.fillStyle = glow; g.beginPath(); g.arc(cx, 66, 150, 0, TAU); g.fill();
    paint(g, ell(cx, 62, 42, 9, 0, TAU, 0, 50), GOLD, { lw: .7, gloss: true, flat: true });
    for (let i = 0; i < 5; i++) { const a = Math.PI * (.1 + i * .2), px = cx + Math.cos(a) * 40, py = 62 + Math.sin(a) * 9; stroke(g, [[cx, 50], [px, py - 2]], GOLD, 1.2); paint(g, box(px - 2, py - 14, 4, 12), '#fbf8f2', { lw: .4, flat: true }); paint(g, ell(px, py - 17, 2.2, 4, 0, TAU, 6, i), '#ffd98a', { lw: .3, flat: true, line: false }); }
    for (let i = 0; i < 9; i++) { const a = Math.PI * (.05 + i * .11), px = cx + Math.cos(a) * 36, py = 66 + Math.sin(a) * 8; stroke(g, [[px, py], [px, py + 8 + (i % 2) * 6]], 'rgba(200,190,180,.8)', .6); paint(g, [[px, py + 8 + (i % 2) * 6], [px + 2.4, py + 12 + (i % 2) * 6], [px, py + 17 + (i % 2) * 6], [px - 2.4, py + 12 + (i % 2) * 6]], '#eef4f6', { lw: .3, flat: true, gloss: true }); }
    paint(g, ell(cx, 46, 7, 7, 0, TAU, 0, 51), GOLD, { lw: .5, gloss: true, flat: true });
    for (const sx of [128, 660]) {
      const gl = g.createRadialGradient(sx, 150, 4, sx, 150, 60); gl.addColorStop(0, `rgba(255,214,150,${.28 * lit})`); gl.addColorStop(1, 'rgba(255,214,150,0)'); g.fillStyle = gl; g.beginPath(); g.arc(sx, 150, 60, 0, TAU); g.fill();
      paint(g, ell(sx, 170, 6, 9, 0, TAU, 0, 52), GOLD, { lw: .5, gloss: true, flat: true });
      stroke(g, [[sx, 166], [sx - 8, 158], [sx - 8, 150]], GOLD, 1.4);
      paint(g, [[sx - 16, 150], [sx, 150], [sx - 3, 136], [sx - 13, 136]], '#f6e6d2', { lw: .6, flat: true });
    }
  }
  // 屋顶下挂的一条花叶藤
  function garland(g) {
    const R = rng(8);
    for (let seg = 0; seg < 6; seg++) {
      const x0 = seg * 130 - 10, x1 = x0 + 130;
      const pts = []; for (let i = 0; i <= 12; i++) { const t = i / 12; pts.push([x0 + (x1 - x0) * t, 30 + Math.sin(t * Math.PI) * 18]); }
      stroke(g, pts, '#7f9a5c', 1.4);
      for (let i = 0; i <= 12; i++) { const [px, py] = pts[i]; for (const s of [-1, 1]) { g.save(); g.translate(px, py); g.rotate(s * .8 + (R() - .5) * .4); paint(g, ell(0, s * 4, 5, 2.4, 0, TAU, 6, i), R() < .5 ? '#8fae7c' : '#7d9d6c', { lw: .4, flat: true }); g.restore(); } if (i % 3 === 1) { const c = ['#f3c4cf', '#fff6e0', '#e8b4b8'][(i + seg) % 3]; for (let p = 0; p < 5; p++) { const a = p / 5 * TAU; paint(g, ell(px + Math.cos(a) * 2.8, py + 5 + Math.sin(a) * 2.8, 2.6, 2.6, 0, TAU, 5, p), c, { lw: .35, flat: true }); } } }
    }
  }
  // 架子：雕花托架，上面摆三层点心架、糖果罐、茶壶茶杯、玻璃罩蛋糕、花瓶、书
  function shelves(g, recipes) {
    for (const y of [116, 190]) {
      paint(g, box(462, y, 190, 7), '#c9a27c', { lw: .8 });
      paint(g, box(462, y + 7, 190, 2), GOLD, { lw: .4, flat: true, line: false });
      for (const bx of [474, 640]) paint(g, [[bx - 2, y + 7], [bx + 8 * (bx < 500 ? 1 : -1), y + 7], [bx, y + 26], ...ell(bx + 3 * (bx < 500 ? 1 : -1), y + 18, 4, 4, 0, TAU, 6, 3)], '#b48a68', { lw: .6, flat: true });
    }
    // 上层：糖果罐 ×3、茶壶、一摞茶杯
    const jars = [['#f3c4cf', '#e8a0b0'], ['#f1dca0', '#e2b766'], ['#bfd9c8', '#93bba4']];
    jars.forEach(([a, b], i) => {
      const x = 482 + i * 26;
      paint(g, rbox(x - 10, 82, 20, 34, 6), 'rgba(235,244,246,.85)', { lw: .7, gloss: true });
      const R = rng(i + 3); for (let k = 0; k < 9; k++) paint(g, ell(x - 6 + R() * 12, 96 + R() * 16, 3, 3, 0, TAU, 6, k), k % 2 ? a : b, { lw: .3, flat: true, line: false });
      paint(g, rbox(x - 9, 77, 18, 6, 2), GOLD, { lw: .5, gloss: true, flat: true });
      paint(g, ell(x, 76, 3, 2.5, 0, TAU, 6, 1), GOLD, { lw: .4, flat: true });
    });
    // 茶壶
    const tx = 580; paint(g, ell(tx, 102, 16, 13, 0, TAU, 0, 60), '#fbf8f2', { lw: .8, gloss: true });
    paint(g, [[tx + 14, 100], [tx + 26, 92], [tx + 28, 94], [tx + 17, 106]], '#fbf8f2', { lw: .6, flat: true });
    stroke(g, [[tx - 15, 96], [tx - 24, 98], [tx - 22, 108], [tx - 14, 108]], '#fbf8f2', 2.4);
    paint(g, ell(tx, 89, 9, 3, 0, TAU, 0, 61), GOLD, { lw: .4, flat: true }); paint(g, ell(tx, 86, 3, 3, 0, TAU, 6, 2), GOLD, { lw: .4, flat: true });
    for (let i = 0; i < 3; i++) paint(g, ell(tx + Math.cos(i * 2) * 8, 104 + Math.sin(i * 2) * 4, 3, 2.5, 0, TAU, 6, i), '#e8b4b8', { lw: .3, flat: true });
    for (let i = 0; i < 3; i++) { paint(g, [[612 + i * 2, 116 - i * 9], [636 + i * 2, 116 - i * 9], [632 + i * 2, 108 - i * 9], [616 + i * 2, 108 - i * 9]], '#fbf8f2', { lw: .6, flat: true }); stroke(g, [[614 + i * 2, 112 - i * 9], [634 + i * 2, 112 - i * 9]], '#c9a0b0', .8); }
    // 下层：三层点心架（摆马卡龙）、玻璃罩里一块甜点、一瓶花
    const cx = 498;
    stroke(g, [[cx, 190], [cx, 142]], GOLD, 1.6);
    const mac = ['#f2c3c8', '#bccb9c', '#f1dd8e', '#c7bcd8', '#f5d48a'];
    for (const [ty, r] of [[184, 22], [166, 17], [150, 11]]) { paint(g, ell(cx, ty, r, 3.6, 0, TAU, 0, ty), '#fbf8f2', { lw: .6, flat: true }); for (let i = 0; i < Math.round(r / 6); i++) { const px = cx + (i - (r / 6 - 1) / 2) * 8.5, c = mac[(i + r) % 5]; paint(g, ell(px, ty - 4.5, 3.8, 2.4, 0, TAU, 6, i), c, { lw: .35, flat: true }); paint(g, ell(px, ty - 2, 3.8, 2.4, 0, TAU, 6, i + 1), c, { lw: .35, flat: true }); } }
    paint(g, ell(cx, 143, 2.5, 2.5, 0, TAU, 6, 1), GOLD, { lw: .4, flat: true });
    // 玻璃罩
    paint(g, ell(556, 189, 24, 4, 0, TAU, 0, 70), '#fbf8f2', { lw: .7, flat: true });
    if (recipes[0]) INK.dessert(g, recipes[0], 556, 186, 30, { plate: false, sparkles: false });
    paint(g, [[534, 188], ...ell(556, 164, 22, 26, Math.PI, TAU, 0, 71), [578, 188]], 'rgba(235,244,246,.35)', { lw: .7, gloss: true, flat: true });
    paint(g, ell(556, 137, 3.5, 3.5, 0, TAU, 6, 2), GOLD, { lw: .4, flat: true });
    // 花瓶
    paint(g, [[612, 190], [608, 176], [612, 164], [624, 164], [628, 176], [624, 190]], '#c7d6e0', { lw: .7, gloss: true });
    const R2 = rng(12); for (let i = 0; i < 8; i++) { const fx = 618 + (R2() - .5) * 26, fy = 138 + R2() * 20; stroke(g, [[618, 166], [fx, fy]], '#7f9a5c', 1); const c = ['#f3c4cf', '#fff6e0', '#e8b4b8', '#c7bcd8'][i % 4]; for (let p = 0; p < 5; p++) { const a = p / 5 * TAU; paint(g, ell(fx + Math.cos(a) * 2.6, fy + Math.sin(a) * 2.6, 2.4, 2.4, 0, TAU, 5, p), c, { lw: .35, flat: true }); } }
  }
  // 黑板：金色雕花框，手写的「今日甜点」和价钱，角上画一个小蛋糕
  function chalkboard(g, items) {
    const x = 352, y = 92, w = 92, h = 118;
    paint(g, rbox(x - 7, y - 7, w + 14, h + 14, 8), GOLD, { lw: 1, gloss: true });
    paint(g, rbox(x, y, w, h, 4), '#3f4a44', { lw: .8 });
    for (const [cx, cy] of [[x - 4, y - 4], [x + w + 4, y - 4], [x - 4, y + h + 4], [x + w + 4, y + h + 4]]) paint(g, ell(cx, cy, 5, 5, 0, TAU, 0, 1), tone(GOLD, .1), { lw: .5, gloss: true, flat: true });
    g.fillStyle = '#f6efe6'; g.font = 'italic 600 11px Georgia, serif'; g.textAlign = 'center'; g.fillText('Today’s Sweets', x + w / 2, y + 17);
    g.font = '8.5px "PingFang SC", sans-serif'; g.fillText('今日甜点', x + w / 2, y + 28);
    g.strokeStyle = 'rgba(246,239,230,.55)'; g.lineWidth = .8; g.beginPath(); g.moveTo(x + 14, y + 33); g.quadraticCurveTo(x + w / 2, y + 37, x + w - 14, y + 33); g.stroke();
    g.font = '8px "PingFang SC", sans-serif'; g.textAlign = 'left';
    items.slice(0, 5).forEach((it, i) => { g.fillStyle = 'rgba(246,239,230,.92)'; g.fillText(it.name.slice(0, 6), x + 9, y + 48 + i * 13); g.textAlign = 'right'; g.fillStyle = '#f1dca0'; g.fillText('¥' + it.price, x + w - 8, y + 48 + i * 13); g.textAlign = 'left'; });
    if (!items.length) { g.fillStyle = 'rgba(246,239,230,.6)'; g.textAlign = 'center'; g.fillText('还没有上架', x + w / 2, y + 66); }
    // 粉笔画的小蛋糕
    g.strokeStyle = 'rgba(246,239,230,.75)'; g.lineWidth = .9;
    g.beginPath(); g.ellipse(x + 18, y + h - 22, 9, 3, 0, 0, TAU); g.moveTo(x + 9, y + h - 22); g.lineTo(x + 9, y + h - 12); g.ellipse(x + 18, y + h - 12, 9, 3, 0, Math.PI, 0, true); g.lineTo(x + 27, y + h - 22); g.stroke();
    g.fillStyle = '#f2c3c8'; g.beginPath(); g.arc(x + 18, y + h - 27, 2.2, 0, TAU); g.fill();
    g.fillStyle = 'rgba(246,239,230,.7)'; for (let i = 0; i < 3; i++) g.fillText('✦', x + 38 + i * 16, y + h - 12 + (i % 2) * 4);
  }
  // 地板 + 座位区一块花纹地毯
  function floor(g, fl) {
    const top = FLOOR, h = WH - FLOOR;
    g.fillStyle = fl.a; g.fillRect(0, top, WW, h);
    if (fl.kind === 'plank') for (let i = 0; i < 9; i++) { const y0 = top + Math.pow(i / 9, 1.25) * h, y1 = top + Math.pow((i + 1) / 9, 1.25) * h; g.fillStyle = i % 2 ? fl.a : fl.b; g.fillRect(0, y0, WW, y1 - y0); g.fillStyle = 'rgba(120,85,55,.2)'; g.fillRect(0, y1 - 1, WW, 1); const R = rng(i + 5); for (let k = 0; k < 4; k++) g.fillRect(R() * WW, y0, 1, y1 - y0); }
    if (fl.kind === 'checker' || fl.kind === 'herring') {
      for (let i = 0; i < 8; i++) { const y0 = top + Math.pow(i / 8, 1.25) * h, y1 = top + Math.pow((i + 1) / 8, 1.25) * h, sz = (y1 - y0) * 1.6; for (let x = -sz * 2, j = 0; x < WW + sz; x += sz, j++) { g.fillStyle = (i + j) % 2 ? (fl.kind === 'checker' ? tone(fl.b, .5) : fl.b) : fl.a; g.beginPath(); if (fl.kind === 'checker') { g.moveTo(x + (i - 4) * 4, y0); g.lineTo(x + sz + (i - 4) * 4, y0); g.lineTo(x + sz + (i - 3) * 4, y1); g.lineTo(x + (i - 3) * 4, y1); } else { g.moveTo(x, y0); g.lineTo(x + sz / 2, y0); g.lineTo(x + sz, y1); g.lineTo(x + sz / 2, y1); } g.fill(); } }
    }
    if (fl.kind === 'terrazzo') { const R = rng(9); for (let i = 0; i < 260; i++) { g.fillStyle = ['#cbbfae', '#e3b9a8', '#b9c4ad', '#d9cfc0'][i % 4]; g.beginPath(); g.ellipse(R() * WW, top + R() * h, 2 + R() * 4, 1.2 + R() * 2, 0, 0, TAU); g.fill(); } }
    if (S() !== 'candy') { g.save(); g.globalCompositeOperation = 'multiply'; g.globalAlpha = .15; g.fillStyle = INK.grain(g); g.fillRect(0, top, WW, h); g.restore(); }
    const sg = g.createLinearGradient(0, top, 0, top + 60); sg.addColorStop(0, 'rgba(90,60,40,.24)'); sg.addColorStop(1, 'rgba(90,60,40,0)');
    g.fillStyle = sg; g.fillRect(0, top, WW, 60);
    // 地毯：椭圆的，一圈花边、中间一朵大花
    const rx = 285, ry = floorY(.6), RX = 150, RY = 52;
    paint(g, ell(rx, ry, RX, RY, 0, TAU, 0, 90), '#c9a0a6', { lw: 1 });
    paint(g, ell(rx, ry, RX - 9, RY - 5, 0, TAU, 0, 91), '#f1e3d8', { lw: .7, flat: true });
    paint(g, ell(rx, ry, RX - 16, RY - 9, 0, TAU, 0, 92), '#d9b9bd', { lw: .5, flat: true, line: false });
    paint(g, ell(rx, ry, RX - 22, RY - 12, 0, TAU, 0, 93), '#f6ece4', { lw: .5, flat: true });
    for (let i = 0; i < 8; i++) { const a = i / 8 * TAU; paint(g, ell(rx + Math.cos(a) * 26, ry + Math.sin(a) * 10, 14, 5, a, a + TAU, 0, i), '#e3b9be', { lw: .5, flat: true }); }
    paint(g, ell(rx, ry, 10, 4, 0, TAU, 0, 94), '#c8a96c', { lw: .5, flat: true });
    for (let i = 0; i < 24; i++) { const a = i / 24 * TAU; paint(g, ell(rx + Math.cos(a) * (RX - 4), ry + Math.sin(a) * (RY - 2.5), 3, 1.6, 0, TAU, 5, i), '#f6ece4', { lw: .3, flat: true, line: false }); }
  }
  // 门口的小地垫
  function mat(g) { paint(g, rbox(18, FLOOR + 18, 100, 18, 7), '#c9a27c', { lw: .8 }); if (S() !== 'paper') { g.strokeStyle = 'rgba(255,255,255,.5)'; g.lineWidth = 1; trace(g, rbox(24, FLOOR + 21, 88, 12, 5)); g.stroke(); } }

  function background(g, st) {
    wall(g, WALLPAPERS[st.wallpaper]);
    windowFrame(g);
    garland(g);
    shelves(g, st.recipes);
    floor(g, FLOORS[st.floor]);
    mat(g);
  }

  // ———— 展示柜、收银台 ————
  function caseSlots(n) {
    const cols = n <= 9 ? 3 : 4, rows = Math.ceil(n / cols), out = [];
    const ih = CASE.base - 46 - CASE.top - 16;
    for (let i = 0; i < n; i++) { const c = i % cols, r = Math.floor(i / cols); out.push({ x: CASE.x + 20 + (c + .5) * (CASE.w - 40) / cols, y: CASE.top + 16 + (r + 1) * ih / rows - 6, w: (CASE.w - 40) / cols }); }
    return out;
  }
  // 展示柜：雕花木头柜身、四只弯脚、金边，弧面玻璃里每一层垫着蕾丝纸，甜点上挂小价签
  function displayCase(g, slots, byId) {
    const { x, w, top, base } = CASE;
    g.save(); g.fillStyle = 'rgba(80,55,40,.2)'; g.beginPath(); g.ellipse(x + w / 2, base + 4, w * .58, 12, 0, 0, TAU); g.fill(); g.restore();
    for (const lx of [x + 8, x + w - 8]) paint(g, [[lx - 5, base - 8], [lx + 5, base - 8], [lx + 3 * Math.sign(lx - x - w / 2), base + 2], [lx - 1, base + 4]], '#a77f5c', { lw: .6, flat: true });
    paint(g, rbox(x, base - 46, w, 40, 6), '#d9bf9c', { lw: 1, seed: 100 });
    for (let i = 0; i < 3; i++) { const px = x + 12 + i * (w - 24) / 3; paint(g, rbox(px, base - 38, (w - 24) / 3 - 8, 24, 4), '#cfb18b', { lw: .6, flat: true }); paint(g, ell(px + ((w - 24) / 3 - 8) / 2, base - 26, 5, 3, 0, TAU, 0, i), GOLD, { lw: .4, flat: true, gloss: true }); }
    paint(g, box(x - 3, base - 49, w + 6, 4), GOLD, { lw: .5, gloss: true, flat: true });
    // 玻璃
    const gx = x + 5, gw = w - 10, gt = top, gb = base - 49;
    paint(g, [[gx, gb], [gx, gt + 14], ...ell(gx + gw / 2, gt + 14, gw / 2, 14, Math.PI, TAU, 0, 101), [gx + gw, gb]], 'rgba(232,242,244,.4)', { lw: .8, flat: true, line: false });
    const n = slots.length, pos = caseSlots(n), rows = Math.ceil(n / (n <= 9 ? 3 : 4));
    for (let r = 1; r <= rows; r++) { const yy = top + 16 + r * (base - 46 - top - 16) / rows - 4; paint(g, box(gx + 3, yy, gw - 6, 3), '#fbf8f2', { lw: .4, flat: true }); for (let k = 0; k < 14; k++) paint(g, ell(gx + 8 + k * (gw - 16) / 13, yy + 3.5, 2.4, 1.6, 0, Math.PI, 5, k), '#fbf8f2', { lw: .3, flat: true, line: false }); }
    slots.forEach((s, i) => {
      const p = pos[i];
      if (s && s.n > 0 && byId[s.rid]) {
        const r = byId[s.rid], W = Math.min(46, p.w * .86);
        if (s.n > 1) INK.dessert(g, r, p.x - W * .22, p.y - 3, W * .78, { plate: false, sparkles: false });
        INK.dessert(g, r, p.x + (s.n > 1 ? W * .12 : 0), p.y, W, { plate: false, sparkles: false });
        // 挂着的小价签
        stroke(g, [[p.x + 10, p.y - 4], [p.x + 14, p.y + 2]], '#c8a96c', .6);
        g.save(); g.translate(p.x + 14, p.y + 7); g.rotate(-.1);
        paint(g, [[-12, -5], [12, -5], [14, 0], [12, 5], [-12, 5]], '#fbf7f1', { lw: .5, flat: true });
        g.fillStyle = '#7a5a48'; g.font = '600 7px "PingFang SC", sans-serif'; g.textAlign = 'center'; g.fillText('¥' + s.price + '×' + s.n, 0, 2.5);
        g.restore();
      } else { g.strokeStyle = 'rgba(160,140,120,.35)'; g.setLineDash([3, 3]); g.lineWidth = 1; g.beginPath(); g.ellipse(p.x, p.y - 6, p.w * .3, 6, 0, 0, TAU); g.stroke(); g.setLineDash([]); }
    });
    // 玻璃反光、金边框
    const gl = g.createLinearGradient(gx, gt, gx + gw, gb); gl.addColorStop(0, 'rgba(255,255,255,.4)'); gl.addColorStop(.3, 'rgba(255,255,255,0)'); gl.addColorStop(.55, 'rgba(255,255,255,.14)'); gl.addColorStop(.65, 'rgba(255,255,255,0)');
    g.fillStyle = gl; trace(g, [[gx, gb], [gx, gt + 14], ...ell(gx + gw / 2, gt + 14, gw / 2, 14, Math.PI, TAU, 0, 101), [gx + gw, gb]]); g.fill();
    g.strokeStyle = S() === 'candy' ? '#5b3b30' : GOLD; g.lineWidth = S() === 'candy' ? 2 : 1.6; g.stroke();
    paint(g, ell(gx + gw / 2, gt - 2, 6, 6, 0, TAU, 0, 102), GOLD, { lw: .5, gloss: true, flat: true });
  }
  // 收银台：大理石台面、嵌板柜身，黄铜收银机、小费罐、一个点心罩、一瓶花
  function counterBack(g) {
    const { x, w, top } = COUNTER;
    paint(g, box(x + 4, top - 6, w - 8, 8), '#e8dccb', { lw: .6, flat: true });
  }
  function counterFront(g, recipes) {
    const { x, w, top, base } = COUNTER;
    g.save(); g.fillStyle = 'rgba(80,55,40,.2)'; g.beginPath(); g.ellipse(x + w / 2, base + 4, w * .6, 10, 0, 0, TAU); g.fill(); g.restore();
    paint(g, rbox(x, top + 8, w, base - top - 8, 4), '#efe3d2', { lw: 1, seed: 110 });
    for (let i = 0; i < 2; i++) { const px = x + 8 + i * (w - 16) / 2; paint(g, rbox(px, top + 18, (w - 16) / 2 - 6, base - top - 30, 4), '#e6d6c0', { lw: .6, flat: true }); if (S() !== 'paper') { g.strokeStyle = 'rgba(212,176,106,.8)'; g.lineWidth = 1; trace(g, rbox(px + 4, top + 22, (w - 16) / 2 - 14, base - top - 38, 3)); g.stroke(); } }
    // 大理石台面
    paint(g, rbox(x - 5, top, w + 10, 11, 3), '#f6f2ec', { lw: .8, gloss: true, seed: 111 });
    if (S() !== 'paper') { g.strokeStyle = 'rgba(170,160,150,.45)'; g.lineWidth = .7; g.beginPath(); g.moveTo(x + 6, top + 3); g.quadraticCurveTo(x + 30, top + 8, x + 52, top + 4); g.moveTo(x + 60, top + 7); g.quadraticCurveTo(x + 80, top + 2, x + 98, top + 6); g.stroke(); }
    // 黄铜收银机
    const rx = x + 8;
    paint(g, [[rx, top], [rx + 38, top], [rx + 34, top - 20], [rx + 4, top - 20]], '#c8a35a', { lw: .8, gloss: true, seed: 112 });
    paint(g, rbox(rx + 7, top - 32, 24, 13, 3), '#d8b870', { lw: .6, gloss: true, seed: 113 });
    paint(g, box(rx + 11, top - 29, 16, 6), '#fbf7ec', { lw: .4, flat: true });
    for (let i = 0; i < 8; i++) paint(g, ell(rx + 9 + (i % 4) * 7, top - 14 + Math.floor(i / 4) * 6, 2, 2, 0, TAU, 5, i), '#fbf8f2', { lw: .3, flat: true });
    // 小费罐
    paint(g, rbox(x + 52, top - 16, 13, 16, 3), 'rgba(235,244,246,.85)', { lw: .6, gloss: true });
    paint(g, ell(x + 58.5, top - 4, 5, 2.5, 0, TAU, 5, 1), GOLD, { lw: .3, flat: true });
    g.fillStyle = '#8a6a50'; g.font = '5px sans-serif'; g.textAlign = 'center'; g.fillText('TIPS', x + 58.5, top - 9);
    // 点心罩（里面一块今天的甜点）
    paint(g, ell(x + 86, top - 1, 13, 2.5, 0, TAU, 0, 114), '#fbf8f2', { lw: .5, flat: true });
    if (recipes && recipes[1]) INK.dessert(g, recipes[1], x + 86, top - 2, 18, { plate: false, sparkles: false });
    paint(g, [[x + 74, top - 1], ...ell(x + 86, top - 14, 12, 14, Math.PI, TAU, 0, 115), [x + 98, top - 1]], 'rgba(235,244,246,.35)', { lw: .5, gloss: true, flat: true });
  }

  // ———— 家具 ————
  const DRAW = {
    table(g, x, y, k) {
      for (const s of [-1, 1]) {   // 两把雕花小椅子
        const cx = x + s * 31 * k;
        paint(g, [[cx - 9 * k, y - 62 * k], [cx + 9 * k, y - 62 * k], [cx + 8 * k, y - 34 * k], [cx - 8 * k, y - 34 * k]], '#f3e6d4', { lw: k * .8, seed: 120 + s });
        paint(g, ell(cx, y - 62 * k, 9 * k, 4 * k, Math.PI, TAU, 0, 121), '#f3e6d4', { lw: k * .6, flat: true });
        paint(g, rbox(cx - 10 * k, y - 36 * k, 20 * k, 5 * k, 2 * k), '#e8b4b8', { lw: k * .6, seed: 122 });
        for (const d of [-7, 7]) stroke(g, [[cx + d * k, y - 31 * k], [cx + d * 1.15 * k, y]], '#b48a68', 1.6 * k);
      }
      stroke(g, [[x, y - 40 * k], [x, y - 2 * k]], '#8a7a6a', 2.6 * k);
      paint(g, ell(x, y - 2 * k, 11 * k, 3 * k, 0, TAU, 0, 123), '#8a7a6a', { lw: k * .5, flat: true });
      // 桌布：垂下来的蕾丝边
      const cloth = [...ell(x, y - 42 * k, 26 * k, 7.5 * k, Math.PI, TAU, 0, 124)];
      for (let i = 0; i <= 10; i++) { const t = i / 10, px = x + 26 * k - t * 52 * k; cloth.push([px, y - 30 * k + Math.sin(t * Math.PI) * 4 * k + (i % 2 ? 2.5 * k : 0)]); }
      paint(g, cloth, '#fbf8f2', { lw: k * .8, seed: 125 });
      paint(g, ell(x, y - 42 * k, 26 * k, 7.5 * k, 0, TAU, 0, 126), '#fdfbf7', { lw: k * .6, flat: true });
      // 一套茶杯和一碟小点心
      paint(g, ell(x - 8 * k, y - 43 * k, 7 * k, 2.4 * k, 0, TAU, 0, 127), '#fbf8f2', { lw: k * .5, flat: true });
      paint(g, [[x - 13 * k, y - 50 * k], [x - 3 * k, y - 50 * k], [x - 4.5 * k, y - 44 * k], [x - 11.5 * k, y - 44 * k]], '#f6e6e8', { lw: k * .5, flat: true });
      paint(g, ell(x + 9 * k, y - 43.5 * k, 7 * k, 2.4 * k, 0, TAU, 0, 128), '#fbf8f2', { lw: k * .5, flat: true });
      for (let i = 0; i < 3; i++) paint(g, ell(x + (6 + i * 3) * k, y - 46 * k, 2.4 * k, 1.6 * k, 0, TAU, 6, i), ['#f2c3c8', '#bccb9c', '#f1dd8e'][i], { lw: k * .3, flat: true });
    },
    armchair(g, x, y, k) {
      const c = '#c98b94';
      for (const s of [-1, 1]) stroke(g, [[x + s * 15 * k, y - 8 * k], [x + s * 17 * k, y]], '#8a6a50', 2.4 * k);
      paint(g, [[x - 20 * k, y - 18 * k], ...ell(x, y - 46 * k, 20 * k, 16 * k, Math.PI, TAU, 0, 130), [x + 20 * k, y - 18 * k]], c, { lw: k, seed: 130 });
      for (let i = -1; i <= 1; i++) paint(g, ell(x + i * 9 * k, y - 42 * k, 2 * k, 2 * k, 0, TAU, 5, i + 2), tone(c, -.15), { lw: k * .3, flat: true, line: false });
      paint(g, rbox(x - 19 * k, y - 25 * k, 38 * k, 15 * k, 5 * k), tone(c, .08), { lw: k * .8, seed: 131 });
      for (const s of [-1, 1]) paint(g, rbox(x + s * 19 * k - 6 * k, y - 34 * k, 12 * k, 24 * k, 6 * k), tone(c, .04), { lw: k * .8, seed: 132 + s });
      for (let i = 0; i < 7; i++) paint(g, ell(x - 15 * k + i * 5 * k, y - 10 * k, 2.4 * k, 1.8 * k, 0, Math.PI, 5, i), GOLD, { lw: k * .3, flat: true, line: false });
    },
    plant(g, x, y, k) {
      paint(g, [[x - 13 * k, y - 26 * k], [x + 13 * k, y - 26 * k], [x + 10 * k, y], [x - 10 * k, y]], '#efe4d4', { lw: k, seed: 140 });
      paint(g, box(x - 14 * k, y - 28 * k, 28 * k, 4 * k), GOLD, { lw: k * .5, flat: true, gloss: true });
      const leaves = [[-1, -62, -.5, 1], [1, -70, .4, 1.1], [0, -84, 0, 1], [-1, -46, -1, .9], [1, -50, .9, .9]];
      for (const [s, ly, a, sz] of leaves) {
        stroke(g, [[x, y - 26 * k], [x + s * 5 * k, y + ly * k * .6], [x + s * 14 * k, y + ly * k]], '#6f8f5e', 1.5 * k);
        g.save(); g.translate(x + s * 14 * k, y + ly * k); g.rotate(a);
        const lf = []; for (let i = 0; i <= 16; i++) { const t = i / 16 * TAU, rr = 1 - (Math.abs(Math.sin(t * 3)) > .85 && Math.cos(t) < .6 ? .25 : 0); lf.push([Math.cos(t) * 15 * k * sz * rr, Math.sin(t) * 11 * k * sz * rr]); }
        paint(g, lf, '#86b07c', { lw: k * .7, seed: 141 });
        stroke(g, [[-12 * k * sz, 0], [12 * k * sz, 0]], 'rgba(60,100,60,.6)', .7 * k);
        g.restore();
      }
    },
    flowerpot(g, x, y, k) {
      paint(g, [[x - 10 * k, y - 20 * k], [x + 10 * k, y - 20 * k], [x + 7 * k, y], [x - 7 * k, y]], '#e2b1a3', { lw: k * .8, seed: 150 });
      paint(g, box(x - 11 * k, y - 22 * k, 22 * k, 4 * k), '#ecc4b8', { lw: k * .5, flat: true });
      const R = rng(Math.round(x));
      for (let i = 0; i < 8; i++) { const fx = x + (R() - .5) * 24 * k, fy = y - (28 + R() * 20) * k; stroke(g, [[x, y - 22 * k], [fx, fy]], '#7f9a5c', 1.1 * k); paint(g, ell((x + fx) / 2 + 3 * k, (y - 22 * k + fy) / 2, 4 * k, 2 * k, .6, .6 + TAU, 6, i), '#8fae7c', { lw: k * .3, flat: true }); const c = ['#f3c4cf', '#fff6e0', '#e8b4b8', '#c7bcd8'][i % 4]; for (let p = 0; p < 5; p++) { const a = p / 5 * TAU; paint(g, ell(fx + Math.cos(a) * 2.8 * k, fy + Math.sin(a) * 2.8 * k, 2.5 * k, 2.5 * k, 0, TAU, 5, p), c, { lw: k * .3, flat: true }); } paint(g, ell(fx, fy, 1.4 * k, 1.4 * k, 0, TAU, 5, 1), '#f1dca0', { lw: k * .2, flat: true, line: false }); }
    },
    bookshelf(g, x, y, k) {
      paint(g, [[x - 29 * k, y], [x - 29 * k, y - 80 * k], ...ell(x, y - 80 * k, 29 * k, 10 * k, Math.PI, TAU, 0, 160), [x + 29 * k, y - 80 * k], [x + 29 * k, y]], '#b48a68', { lw: k, seed: 160 });
      paint(g, box(x - 25 * k, y - 82 * k, 50 * k, 78 * k), '#ecdfcc', { lw: k * .6, flat: true });
      const cols = ['#c98b8f', '#a9b89a', '#c7bcd8', '#d9bf9c', '#8fa3b8', '#e8b4b8'];
      for (let r = 0; r < 3; r++) { paint(g, box(x - 26 * k, y - 57 * k + r * 26 * k, 52 * k, 3 * k), '#b48a68', { lw: k * .4, flat: true }); let bx = x - 23 * k, i = r * 3; while (bx < x + 18 * k) { const bw = (4 + (i * 7 % 4)) * k, bh = (15 + (i * 5 % 7)) * k; paint(g, box(bx, y - 57 * k + r * 26 * k - bh, bw, bh), cols[i % cols.length], { lw: k * .4, flat: true }); bx += bw + 1 * k; i++; } }
      paint(g, ell(x + 14 * k, y - 84 * k, 6 * k, 5 * k, 0, TAU, 0, 161), '#8fae7c', { lw: k * .5, flat: true });
    },
    gramophone(g, x, y, k) {
      paint(g, rbox(x - 18 * k, y - 22 * k, 36 * k, 22 * k, 3 * k), '#8a6a50', { lw: k, seed: 170 });
      paint(g, ell(x, y - 23 * k, 15 * k, 4 * k, 0, TAU, 0, 171), '#2d2a2e', { lw: k * .5, flat: true, gloss: true });
      stroke(g, [[x + 10 * k, y - 24 * k], [x + 14 * k, y - 46 * k], [x + 4 * k, y - 52 * k]], GOLD, 2 * k);
      paint(g, [[x + 4 * k, y - 52 * k], [x - 24 * k, y - 78 * k], [x - 30 * k, y - 62 * k], [x - 20 * k, y - 46 * k]], GOLD, { lw: k, gloss: true, seed: 172 });
      paint(g, ell(x - 26 * k, y - 70 * k, 6 * k, 10 * k, .7, .7 + TAU, 0, 173), tone(GOLD, -.2), { lw: k * .5, flat: true });
    },
    cakestand(g, x, y, k) {
      stroke(g, [[x, y - 70 * k], [x, y]], GOLD, 1.8 * k);
      paint(g, ell(x, y - 2 * k, 10 * k, 3 * k, 0, TAU, 0, 180), GOLD, { lw: k * .5, flat: true });
      for (const [ty, r] of [[-20, 20], [-42, 15], [-62, 10]]) { paint(g, ell(x, y + ty * k, r * k, 4 * k, 0, TAU, 0, ty), '#fbf8f2', { lw: k * .6, flat: true }); const cols = ['#f2c3c8', '#bccb9c', '#f1dd8e', '#c7bcd8']; for (let i = 0; i < Math.round(r / 6); i++) { const px = x + (i - (r / 6 - 1) / 2) * 9 * k; paint(g, ell(px, y + ty * k - 4 * k, 3.6 * k, 2.6 * k, 0, TAU, 6, i), cols[(i + r) % 4], { lw: k * .3, flat: true }); paint(g, ell(px, y + ty * k - 1.5 * k, 3.6 * k, 2.6 * k, 0, TAU, 6, i + 1), cols[(i + r) % 4], { lw: k * .3, flat: true }); } }
    },
    teddy(g, x, y, k) {
      const c = '#c99a6a';
      paint(g, ell(x, y - 14 * k, 13 * k, 14 * k, 0, TAU, 0, 190), c, { lw: k, seed: 190 });
      for (const s of [-1, 1]) { paint(g, ell(x + s * 8 * k, y - 3 * k, 6 * k, 4 * k, 0, TAU, 0, 191), c, { lw: k * .7 }); paint(g, ell(x + s * 13 * k, y - 18 * k, 4 * k, 7 * k, 0, TAU, 0, 192), c, { lw: k * .7 }); paint(g, ell(x + s * 9 * k, y - 45 * k, 4.5 * k, 4.5 * k, 0, TAU, 0, 193), c, { lw: k * .7 }); }
      paint(g, ell(x, y - 36 * k, 12 * k, 11 * k, 0, TAU, 0, 194), c, { lw: k, seed: 194 });
      paint(g, ell(x, y - 32 * k, 5 * k, 4 * k, 0, TAU, 0, 195), '#e9cfae', { lw: k * .5, flat: true });
      g.fillStyle = '#3a2a26'; for (const s of [-1, 1]) { g.beginPath(); g.arc(x + s * 4 * k, y - 38 * k, 1.3 * k, 0, TAU); g.fill(); } g.beginPath(); g.arc(x, y - 33 * k, 1.4 * k, 0, TAU); g.fill();
      for (const s of [-1, 1]) paint(g, [[x, y - 25 * k], [x + s * 7 * k, y - 28 * k], [x + s * 7 * k, y - 21 * k]], '#e8b4b8', { lw: k * .5, flat: true });
    },
    frame(g, x, y, k) {
      paint(g, ell(x, y, 23 * k, 29 * k, 0, TAU, 0, 200), GOLD, { lw: k, gloss: true });
      for (let i = 0; i < 12; i++) { const a = i / 12 * TAU; paint(g, ell(x + Math.cos(a) * 23 * k, y + Math.sin(a) * 29 * k, 2.4 * k, 2.4 * k, 0, TAU, 5, i), tone(GOLD, .12), { lw: k * .3, flat: true, line: false }); }
      const pg = g.createLinearGradient(0, y - 24 * k, 0, y + 24 * k); pg.addColorStop(0, '#c7d9e8'); pg.addColorStop(.6, '#ece6cc'); pg.addColorStop(1, '#a9b89a');
      g.save(); trace(g, ell(x, y, 18 * k, 24 * k, 0, TAU, 0, 201)); g.fillStyle = pg; g.fill(); g.clip();
      paint(g, ell(x + 6 * k, y + 2 * k, 7 * k, 9 * k, 0, TAU, 0, 202), '#8fae7c', { lw: k * .5, flat: true });
      for (let i = 0; i < 5; i++) paint(g, ell(x - 10 * k + i * 5 * k, y + 13 * k - (i % 2) * 3 * k, 2.2 * k, 2.2 * k, 0, TAU, 5, i), '#e8b4b8', { lw: k * .3, flat: true });
      g.restore();
    },
    clock(g, x, y, k, t) {
      paint(g, ell(x, y, 19 * k, 19 * k, 0, TAU, 0, 210), GOLD, { lw: k, gloss: true });
      paint(g, ell(x, y, 15 * k, 15 * k, 0, TAU, 0, 211), '#fbf8f2', { lw: k * .6, flat: true });
      g.fillStyle = '#7a5a48'; for (let i = 0; i < 12; i++) { const a = i / 12 * TAU; g.beginPath(); g.arc(x + Math.cos(a) * 12 * k, y + Math.sin(a) * 12 * k, (i % 3 ? .8 : 1.5) * k, 0, TAU); g.fill(); }
      const h = (t / 60) % 12, m = t % 60;
      g.strokeStyle = '#4a3a33'; g.lineCap = 'round';
      g.lineWidth = 1.8 * k; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.sin(h / 12 * TAU) * 7 * k, y - Math.cos(h / 12 * TAU) * 7 * k); g.stroke();
      g.lineWidth = 1.1 * k; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.sin(m / 60 * TAU) * 10.5 * k, y - Math.cos(m / 60 * TAU) * 10.5 * k); g.stroke();
    },
    wreath(g, x, y, k) {
      for (let i = 0; i < 20; i++) { const a = i / 20 * TAU; g.save(); g.translate(x + Math.cos(a) * 16 * k, y + Math.sin(a) * 16 * k); g.rotate(a + 1.2); paint(g, ell(0, 0, 6 * k, 3 * k, 0, TAU, 6, i), i % 2 ? '#8fae7c' : '#6f9a6a', { lw: k * .4, flat: true }); g.restore(); }
      for (let i = 0; i < 7; i++) { const a = i / 7 * TAU + .3; paint(g, ell(x + Math.cos(a) * 16 * k, y + Math.sin(a) * 16 * k, 3.5 * k, 3.5 * k, 0, TAU, 6, i), ['#f3c4cf', '#fff6e0', '#e8b4b8'][i % 3], { lw: k * .4, flat: true }); }
      for (const s of [-1, 1]) paint(g, [[x, y + 16 * k], [x + s * 10 * k, y + 21 * k], [x + s * 7 * k, y + 30 * k]], '#e8b4b8', { lw: k * .5, flat: true });
    },
    mirror(g, x, y, k) {
      paint(g, archPts(x - 18 * k, y - 32 * k, 36 * k, 62 * k), GOLD, { lw: k, gloss: true });
      paint(g, archPts(x - 14 * k, y - 28 * k, 28 * k, 55 * k), '#e2ecef', { lw: k * .6, gloss: true });
      stroke(g, [[x - 8 * k, y + 10 * k], [x + 2 * k, y - 18 * k]], 'rgba(255,255,255,.8)', 2 * k);
      paint(g, ell(x, y - 34 * k, 5 * k, 4 * k, 0, TAU, 0, 220), GOLD, { lw: k * .4, flat: true });
    },
    garland(g, x, y, k, t) {
      const pts = []; for (let i = 0; i <= 10; i++) { const u = i / 10; pts.push([x - 45 * k + u * 90 * k, y - 6 * k + Math.sin(u * Math.PI) * 12 * k]); }
      stroke(g, pts, '#6b5a50', 1);
      pts.forEach(([px, py], i) => { if (i % 1) return; const on = .6 + .4 * Math.sin(t * 3 + i); const gl = g.createRadialGradient(px, py + 4 * k, 0, px, py + 4 * k, 9 * k); gl.addColorStop(0, `rgba(255,220,150,${.5 * on})`); gl.addColorStop(1, 'rgba(255,220,150,0)'); g.fillStyle = gl; g.beginPath(); g.arc(px, py + 4 * k, 9 * k, 0, TAU); g.fill(); paint(g, ell(px, py + 4 * k, 2.4 * k, 3.2 * k, 0, TAU, 5, i), ['#fff3d6', '#f6d3da', '#d9ecf2'][i % 3], { lw: k * .3, flat: true, gloss: true }); });
    },
    drawing(g, x, y, k) {
      g.save(); g.translate(x, y); g.rotate(-.06);
      paint(g, box(-17 * k, -20 * k, 34 * k, 40 * k), '#fffdf8', { lw: k * .6, flat: true });
      PEOPLE.clawd(g, 0, 13 * k, .36 * k, 0, {});
      paint(g, box(-2 * k, -23 * k, 4 * k, 6 * k), '#d9a46c', { lw: k * .3, flat: true });
      g.restore();
    },
    pennant(g, x, y, k) {
      stroke(g, [[x - 25 * k, y - 10 * k], [x + 25 * k, y - 10 * k]], '#8a7a6a', 1);
      paint(g, [[x - 25 * k, y - 10 * k], [x + 25 * k, y - 10 * k], [x, y + 18 * k]], '#a9c9b6', { lw: k * .7 });
      g.fillStyle = '#fbf7f1'; g.font = `600 ${8 * k}px "PingFang SC", sans-serif`; g.textAlign = 'center'; g.fillText('跑团', x, y + 1 * k);
    },
    trophy(g, x, y, k) {
      paint(g, rbox(x - 10 * k, y + 8 * k, 20 * k, 6 * k, 1.5 * k), '#b48a68', { lw: k * .6 });
      paint(g, box(x - 2 * k, y, 4 * k, 9 * k), GOLD, { lw: k * .4, flat: true, gloss: true });
      paint(g, [[x - 12 * k, y - 16 * k], [x + 12 * k, y - 16 * k], [x + 9 * k, y - 2 * k], [x, y + 2 * k], [x - 9 * k, y - 2 * k]], GOLD, { lw: k * .7, gloss: true });
      for (const s of [-1, 1]) stroke(g, ell(x + s * 13 * k, y - 10 * k, 5 * k, 5 * k, s > 0 ? -1.5 : 1.6, s > 0 ? 1.5 : 4.7, 0, 1), GOLD, 2 * k);
    },
  };
  const DECOR_H = { table: 70, armchair: 66, plant: 100, flowerpot: 56, bookshelf: 100, gramophone: 84, cakestand: 76, teddy: 54, frame: 64, clock: 42, wreath: 64, mirror: 70, garland: 30, drawing: 48, pennant: 36, trophy: 40 };
  function decorItem(g, d, t, clock, highlight) {
    const def = DECOR[d.kind]; if (!def || !DRAW[d.kind]) return;
    if (def.place === 'floor') {
      const y = floorY(d.z), k = depthK(d.z);
      g.save(); g.fillStyle = 'rgba(80,55,40,.2)'; g.beginPath(); g.ellipse(d.x, y, def.w * .55 * k, 7 * k, 0, 0, TAU); g.fill(); g.restore();
      DRAW[d.kind](g, d.x, y, k, clock);
      if (highlight) { g.strokeStyle = 'rgba(232,180,184,.95)'; g.lineWidth = 2; g.setLineDash([4, 3]); g.beginPath(); g.ellipse(d.x, y, def.w * .6 * k, 10 * k, 0, 0, TAU); g.stroke(); g.setLineDash([]); }
    } else {
      DRAW[d.kind](g, d.x, d.y, 1, d.kind === 'clock' ? clock : t);
      if (highlight) { g.strokeStyle = 'rgba(232,180,184,.95)'; g.lineWidth = 2; g.setLineDash([4, 3]); g.beginPath(); g.roundRect(d.x - def.w * .6, d.y - 34, def.w * 1.2, 68, 8); g.stroke(); g.setLineDash([]); }
    }
  }
  function clampDecor(d) {
    const def = DECOR[d.kind];
    if (def.place === 'floor') { d.x = Math.max(124, Math.min(440, d.x)); d.z = Math.max(0, Math.min(1, d.z)); }
    else { d.x = Math.max(126 + def.w / 2, Math.min(450 - def.w / 2, d.x)); d.y = Math.max(56, Math.min(232, d.y)); }
    return d;
  }
  function seats(decor) {
    const out = [];
    for (const d of decor) {
      if (d.kind === 'table') for (const s of [-1, 1]) out.push({ x: d.x + s * 31 * depthK(d.z), z: d.z, decor: d, side: s });
      if (d.kind === 'armchair') out.push({ x: d.x, z: d.z, decor: d, side: 1, chair: true });
    }
    return out;
  }

  return { WW, WH, FLOOR, WIN, floorY, depthK, CASE, COUNTER, sky, background, door, lights, chalkboard, displayCase, caseSlots, counterBack, counterFront, decorItem, clampDecor, seats, DRAW, DECOR_H };
})();
