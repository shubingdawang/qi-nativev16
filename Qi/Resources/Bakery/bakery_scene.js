// 店里的场景：一间比手机屏宽的小店（可以左右拖着看）。
// 左边是门和坐着吃东西的地方（家具随便摆），中间拱形窗，右边是展示柜和收银台，她站在柜台后面。
// 场景坐标：宽 760、高 600；墙到 y = 330，往下是地板（z 从 0 靠墙到 1 靠前）。
'use strict';

const SCENE = (() => {
  const { TAU, shade, ellipse, rr, softShadow, rng } = ART;
  const WW = 760, WH = 600, FLOOR = 330;
  const floorY = (z) => FLOOR + 22 + z * 228;
  const depthK = (z) => .82 + .32 * z;
  const CASE = { x: 452, w: 196, top: 300, base: 432 };
  const COUNTER = { x: 656, w: 104, top: 362, base: 440 };

  // ———— 墙纸、地板 ————
  function wallpaper(g, wp, t) {
    g.fillStyle = wp.a; g.fillRect(0, 0, WW, FLOOR);
    g.save(); g.beginPath(); g.rect(0, 0, WW, 252); g.clip();
    if (wp.kind === 'stripe') { g.fillStyle = wp.b; for (let x = 0; x < WW; x += 36) g.fillRect(x, 0, 14, 252); g.fillStyle = 'rgba(255,255,255,.25)'; for (let x = 0; x < WW; x += 36) g.fillRect(x + 14, 0, 2, 252); }
    if (wp.kind === 'check') { g.fillStyle = shade(wp.b, 0, .5); for (let x = 0; x < WW; x += 44) g.fillRect(x, 0, 12, 252); for (let y = 0; y < 252; y += 44) g.fillRect(0, y, WW, 12); }
    if (wp.kind === 'dot') { g.fillStyle = wp.b; for (let y = 14; y < 252; y += 28) for (let x = (y / 28 % 2) * 14 + 10; x < WW; x += 28) { g.beginPath(); g.arc(x, y, 3.2, 0, TAU); g.fill(); } }
    if (wp.kind === 'floral') {
      const R = rng(3);
      for (let y = 18; y < 252; y += 48) for (let x = (y / 48 % 2) * 30 + 16; x < WW; x += 60) {
        g.fillStyle = shade(wp.b, .1); for (let i = 0; i < 5; i++) { const a = i / 5 * TAU; g.beginPath(); g.arc(x + Math.cos(a) * 5, y + Math.sin(a) * 5, 4, 0, TAU); g.fill(); }
        g.fillStyle = '#e9d9a6'; g.beginPath(); g.arc(x, y, 2.5, 0, TAU); g.fill();
        g.strokeStyle = '#b9c7a6'; g.lineWidth = 1.4; g.beginPath(); g.moveTo(x + 6, y + 6); g.quadraticCurveTo(x + 14, y + 12 + R() * 4, x + 20, y + 8); g.stroke();
      }
    }
    if (wp.kind === 'damask') {
      g.fillStyle = shade(wp.b, 0, .55);
      for (let y = 30; y < 252; y += 70) for (let x = (y / 70 % 2) * 40 + 20; x < WW; x += 80) {
        g.beginPath(); g.moveTo(x, y - 24); g.bezierCurveTo(x + 18, y - 12, x + 18, y + 12, x, y + 24); g.bezierCurveTo(x - 18, y + 12, x - 18, y - 12, x, y - 24); g.fill();
        g.beginPath(); g.arc(x, y, 5, 0, TAU); g.fillStyle = shade(wp.a, .3); g.fill(); g.fillStyle = shade(wp.b, 0, .55);
      }
    }
    g.restore();
    // 护墙板 + 踢脚线
    const wg = g.createLinearGradient(0, 252, 0, FLOOR); wg.addColorStop(0, '#f5ecdf'); wg.addColorStop(1, '#e8dbc8');
    g.fillStyle = wg; g.fillRect(0, 252, WW, FLOOR - 252);
    g.fillStyle = '#d9c7ae'; g.fillRect(0, 250, WW, 5);
    g.strokeStyle = 'rgba(170,140,110,.35)'; g.lineWidth = 1.2;
    for (let x = 14; x < WW; x += 64) { rr(g, x, 262, 50, 54, 4); g.stroke(); }
    g.fillStyle = '#c9b292'; g.fillRect(0, FLOOR - 8, WW, 8);
  }
  function floor(g, fl) {
    const top = FLOOR, h = WH - FLOOR;
    g.fillStyle = fl.a; g.fillRect(0, top, WW, h);
    if (fl.kind === 'plank') {
      for (let i = 0; i < 9; i++) { const y0 = top + Math.pow(i / 9, 1.25) * h, y1 = top + Math.pow((i + 1) / 9, 1.25) * h; g.fillStyle = i % 2 ? fl.a : fl.b; g.fillRect(0, y0, WW, y1 - y0); g.fillStyle = 'rgba(120,85,55,.18)'; g.fillRect(0, y1 - 1, WW, 1); const R = rng(i + 5); for (let k = 0; k < 4; k++) g.fillRect(R() * WW, y0, 1, y1 - y0); }
    }
    if (fl.kind === 'checker' || fl.kind === 'herring') {
      const rows = 8;
      for (let i = 0; i < rows; i++) {
        const y0 = top + Math.pow(i / rows, 1.25) * h, y1 = top + Math.pow((i + 1) / rows, 1.25) * h, sz = (y1 - y0) * 1.6;
        for (let x = -sz * 2, j = 0; x < WW + sz; x += sz, j++) {
          if (fl.kind === 'checker') { g.fillStyle = (i + j) % 2 ? shade(fl.b, .55) : fl.a; g.beginPath(); g.moveTo(x + (i - 4) * 4, y0); g.lineTo(x + sz + (i - 4) * 4, y0); g.lineTo(x + sz + (i - 3) * 4, y1); g.lineTo(x + (i - 3) * 4, y1); g.fill(); }
          else { g.fillStyle = (i + j) % 2 ? fl.a : fl.b; g.beginPath(); g.moveTo(x, y0); g.lineTo(x + sz / 2, y0); g.lineTo(x + sz, y1); g.lineTo(x + sz / 2, y1); g.fill(); }
        }
      }
    }
    if (fl.kind === 'terrazzo') { const R = rng(9); for (let i = 0; i < 260; i++) { g.fillStyle = ['#cbbfae', '#e3b9a8', '#b9c4ad', '#d9cfc0'][i % 4]; ellipse(g, R() * WW, top + R() * h, 2 + R() * 4, 1.2 + R() * 2); g.fill(); } }
    // 靠墙那一圈暗一点（墙角的影子）
    const sg = g.createLinearGradient(0, top, 0, top + 60); sg.addColorStop(0, 'rgba(90,60,40,.22)'); sg.addColorStop(1, 'rgba(90,60,40,0)');
    g.fillStyle = sg; g.fillRect(0, top, WW, 60);
  }

  // ———— 窗、门、灯、架子 ————
  function sky(g, x, y, w, h, clock, weather, t) {
    const hour = clock / 60;
    const day = hour < 17 ? 1 : Math.max(0, 1 - (hour - 17) / 2);
    const top = day > .5 ? (weather === 'rain' || weather === 'snow' || weather === 'cloudy' ? '#b9c4cf' : '#a9cbe3') : '#e9b49a';
    const bot = day > .5 ? (weather === 'rain' ? '#d9dee3' : '#e9eff0') : '#f3d6b8';
    const gr = g.createLinearGradient(0, y, 0, y + h); gr.addColorStop(0, top); gr.addColorStop(1, bot);
    g.fillStyle = gr; g.fillRect(x, y, w, h);
    // 街对面的房子和树
    g.fillStyle = 'rgba(160,150,140,.55)'; g.fillRect(x + 10, y + h * .55, 40, h * .45); g.fillRect(x + 70, y + h * .48, 50, h * .52);
    g.fillStyle = 'rgba(130,155,120,.6)'; g.beginPath(); g.arc(x + 58, y + h * .62, 18, 0, TAU); g.fill();
    if (weather === 'sunny' || weather === 'hot') { g.fillStyle = 'rgba(255,240,200,.8)'; g.beginPath(); g.arc(x + w * .75, y + h * .25, 12, 0, TAU); g.fill(); }
    if (weather === 'cloudy' || weather === 'rain') { g.fillStyle = 'rgba(255,255,255,.75)'; for (const [cx, cy] of [[.3, .2], [.7, .32]]) { for (const [dx, r] of [[-12, 9], [0, 13], [12, 9]]) { g.beginPath(); g.arc(x + w * cx + dx + Math.sin(t * .1) * 6, y + h * cy, r, 0, TAU); g.fill(); } } }
    if (weather === 'rain') { g.strokeStyle = 'rgba(120,140,170,.55)'; g.lineWidth = 1; for (let i = 0; i < 26; i++) { const px = x + ((i * 37 + t * 60) % w), py = y + ((i * 53 + t * 220) % h); g.beginPath(); g.moveTo(px, py); g.lineTo(px - 3, py + 9); g.stroke(); } }
    if (weather === 'snow') { g.fillStyle = 'rgba(255,255,255,.9)'; for (let i = 0; i < 30; i++) { const px = x + ((i * 41 + Math.sin(t + i) * 8) % w + w) % w, py = y + ((i * 29 + t * 25) % h); g.beginPath(); g.arc(px, py, 1.6, 0, TAU); g.fill(); } }
  }
  function windowArch(g, clock, weather, t) {
    const x = 168, y = 66, w = 136, h = 168;
    g.save(); g.beginPath(); g.moveTo(x, y + h); g.lineTo(x, y + w / 2); g.arc(x + w / 2, y + w / 2, w / 2, Math.PI, 0); g.lineTo(x + w, y + h); g.closePath(); g.clip();
    sky(g, x, y, w, h, clock, weather, t);
    g.restore();
    g.strokeStyle = '#f7f1e8'; g.lineWidth = 9; g.beginPath(); g.moveTo(x, y + h); g.lineTo(x, y + w / 2); g.arc(x + w / 2, y + w / 2, w / 2, Math.PI, 0); g.lineTo(x + w, y + h); g.closePath(); g.stroke();
    g.lineWidth = 4; g.beginPath(); g.moveTo(x + w / 2, y + 4); g.lineTo(x + w / 2, y + h); g.moveTo(x, y + h * .55); g.lineTo(x + w, y + h * .55); g.stroke();
    // 窗帘：两边挽起来的布
    for (const s of [-1, 1]) {
      const cx = s < 0 ? x - 6 : x + w + 6;
      const gr = g.createLinearGradient(cx - 18, 0, cx + 18, 0); gr.addColorStop(0, '#e9c9c6'); gr.addColorStop(.5, '#f6e2df'); gr.addColorStop(1, '#ddb7b4');
      g.fillStyle = gr; g.beginPath(); g.moveTo(cx - 16 * s, y - 12); g.quadraticCurveTo(cx + 22 * s, y + 70, cx + 4 * s, y + 110); g.quadraticCurveTo(cx - 10 * s, y + 150, cx - 2 * s, y + h + 6); g.lineTo(cx - 20 * s, y + h + 6); g.lineTo(cx - 22 * s, y - 12); g.fill();
      g.fillStyle = '#c8a96c'; ellipse(g, cx + 2 * s, y + 112, 8, 3.5); g.fill();
    }
    g.fillStyle = '#c8a96c'; g.fillRect(x - 34, y - 16, w + 68, 4);
    // 窗台花箱
    g.fillStyle = '#e8dccb'; rr(g, x - 8, y + h, w + 16, 10, 3); g.fill();
    g.fillStyle = '#b48a68'; rr(g, x + 6, y + h - 16, w - 12, 16, 4); g.fill();
    const R = rng(4); for (let i = 0; i < 9; i++) { const fx = x + 14 + i * (w - 28) / 8; g.fillStyle = '#8fae7c'; ellipse(g, fx, y + h - 18, 7, 5); g.fill(); g.fillStyle = ['#f3c4cf', '#fff6e0', '#e8b4b8'][i % 3]; g.beginPath(); g.arc(fx + (R() - .5) * 4, y + h - 24, 3.6, 0, TAU); g.fill(); }
  }
  function door(g, openK, t) {
    const x = 26, y = 116, w = 84, h = FLOOR - 116;
    g.fillStyle = '#e8dccb'; rr(g, x - 8, y - 10, w + 16, h + 10, 6); g.fill();
    g.fillStyle = '#3e3a3a'; g.fillRect(x, y, w, h);   // 门洞里是外面
    g.fillStyle = 'rgba(200,215,225,.9)'; g.fillRect(x, y, w, h * .55);
    // 门板（开门时往里转，看起来变窄）
    const dw = w * (1 - openK * .78);
    const dg = g.createLinearGradient(x, 0, x + dw, 0); dg.addColorStop(0, '#a9b89a'); dg.addColorStop(1, '#93a684');
    g.fillStyle = dg; g.fillRect(x, y, dw, h);
    g.fillStyle = 'rgba(220,235,240,.85)'; rr(g, x + dw * .14, y + 12, dw * .72, h * .45, 6); g.fill();
    g.strokeStyle = '#f7f1e8'; g.lineWidth = 3; g.beginPath(); g.moveTo(x + dw / 2, y + 12); g.lineTo(x + dw / 2, y + 12 + h * .45); g.stroke();
    g.strokeStyle = 'rgba(80,90,70,.35)'; g.lineWidth = 1.2; rr(g, x + dw * .14, y + h * .6, dw * .72, h * .32, 4); g.stroke();
    g.fillStyle = '#c8a96c'; g.beginPath(); g.arc(x + dw - 10, y + h * .58, 3.5, 0, TAU); g.fill();
    // 门铃（有人进来时晃）
    const sw = Math.sin(t * 18) * openK * .5;
    g.save(); g.translate(x + w + 2, y - 4); g.rotate(sw);
    g.strokeStyle = '#8a7a6a'; g.lineWidth = 1; g.beginPath(); g.moveTo(0, -8); g.lineTo(0, 4); g.stroke();
    g.fillStyle = '#d8b45a'; g.beginPath(); g.moveTo(-6, 14); g.quadraticCurveTo(-6, 2, 0, 2); g.quadraticCurveTo(6, 2, 6, 14); g.closePath(); g.fill();
    g.restore();
    // 门口小地垫
    g.fillStyle = '#c9a27c'; ellipse(g, x + w / 2, FLOOR + 26, 50, 9); g.fill();
    g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = 1; ellipse(g, x + w / 2, FLOOR + 26, 42, 6.5); g.stroke();
  }
  function lamps(g, clock) {
    const evening = Math.max(.35, Math.min(1, (clock / 60 - 15) / 3));
    for (const x of [236, 392, 548]) {
      g.strokeStyle = '#6b5a50'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(x, 0); g.lineTo(x, 44); g.stroke();
      const glow = g.createRadialGradient(x, 64, 4, x, 64, 120); glow.addColorStop(0, `rgba(255,214,150,${.32 * evening})`); glow.addColorStop(1, 'rgba(255,214,150,0)');
      g.fillStyle = glow; g.beginPath(); g.arc(x, 64, 120, 0, TAU); g.fill();
      const sg = g.createLinearGradient(x - 20, 0, x + 20, 0); sg.addColorStop(0, '#d9c7a8'); sg.addColorStop(.5, '#f3e7d2'); sg.addColorStop(1, '#c9b392');
      g.fillStyle = sg; g.beginPath(); g.moveTo(x - 6, 44); g.lineTo(x + 6, 44); g.quadraticCurveTo(x + 24, 52, x + 22, 64); g.lineTo(x - 22, 64); g.quadraticCurveTo(x - 24, 52, x - 6, 44); g.fill();
      g.fillStyle = '#fff3d6'; ellipse(g, x, 65, 9, 3); g.fill();
    }
  }
  function shelves(g, recipes) {
    for (const y of [118, 190]) {
      g.fillStyle = '#c9a27c'; rr(g, 466, y, 182, 7, 2); g.fill();
      g.fillStyle = 'rgba(90,60,40,.15)'; g.fillRect(470, y + 7, 174, 5);
      for (const bx of [478, 640]) { g.fillStyle = '#b48a68'; g.beginPath(); g.moveTo(bx, y + 7); g.lineTo(bx + (bx < 500 ? 10 : -10), y + 7); g.lineTo(bx, y + 22); g.fill(); }
    }
    // 罐子
    const jars = [[488, 118, '#f3e6c8', '面粉'], [516, 118, '#faf6ef', '糖'], [544, 118, '#e9c9a0', '杏仁'], [600, 118, '#d9b6c9', '']];
    for (const [x, y, c, label] of jars) {
      g.fillStyle = 'rgba(230,240,240,.75)'; rr(g, x - 11, y - 34, 22, 34, 5); g.fill();
      g.fillStyle = c; rr(g, x - 9, y - 22, 18, 21, 3); g.fill();
      g.fillStyle = '#b48a68'; rr(g, x - 9, y - 38, 18, 6, 2); g.fill();
      if (label) { g.fillStyle = '#fbf7f1'; rr(g, x - 8, y - 18, 16, 8, 1.5); g.fill(); g.fillStyle = '#8a6a50'; g.font = '5px sans-serif'; g.textAlign = 'center'; g.fillText(label, x, y - 12); }
    }
    // 小盆栽、蛋糕架
    g.fillStyle = '#e8dccb'; rr(g, 570, y2(118) - 14, 16, 14, 3); g.fill();
    g.fillStyle = '#8fae7c'; for (const [dx, dy] of [[-4, -20], [4, -22], [0, -27]]) { ellipse(g, 578 + dx, 118 + dy, 6, 4); g.fill(); }
    g.fillStyle = '#f6efe6'; ellipse(g, 520, 186, 22, 4); g.fill(); g.fillStyle = '#c8a96c'; g.fillRect(519, 172, 2, 14);
    g.fillStyle = 'rgba(240,240,245,.6)'; g.beginPath(); g.arc(520, 172, 18, Math.PI, 0); g.fill();
    if (recipes[0]) ART.dessert(g, recipes[0], 520, 184, 26, { plate: false });
    g.fillStyle = '#efe4d4'; for (let i = 0; i < 3; i++) { rr(g, 580 + i * 18, 160 - i * 0, 14, 30, 2); g.fill(); g.fillStyle = ['#c7bcd8', '#a9b89a', '#e8b4b8'][i]; g.fillRect(582 + i * 18, 164, 10, 22); g.fillStyle = '#efe4d4'; }
  }
  function y2(y) { return y; }
  function chalkboard(g, items) {
    const x = 356, y = 98, w = 86, h = 108;
    g.fillStyle = '#b48a68'; rr(g, x - 4, y - 4, w + 8, h + 8, 5); g.fill();
    g.fillStyle = '#3f4a44'; rr(g, x, y, w, h, 3); g.fill();
    g.fillStyle = '#f6efe6'; g.font = '600 10px "PingFang SC", sans-serif'; g.textAlign = 'center'; g.fillText('今日甜点', x + w / 2, y + 18);
    g.strokeStyle = 'rgba(246,239,230,.5)'; g.lineWidth = .8; g.beginPath(); g.moveTo(x + 14, y + 24); g.lineTo(x + w - 14, y + 24); g.stroke();
    g.font = '8px "PingFang SC", sans-serif'; g.textAlign = 'left';
    items.slice(0, 5).forEach((it, i) => { g.fillStyle = 'rgba(246,239,230,.9)'; g.fillText(it.name.slice(0, 6), x + 9, y + 40 + i * 14); g.textAlign = 'right'; g.fillStyle = '#f1dca0'; g.fillText('¥' + it.price, x + w - 8, y + 40 + i * 14); g.textAlign = 'left'; });
    if (!items.length) { g.fillStyle = 'rgba(246,239,230,.6)'; g.textAlign = 'center'; g.fillText('还没有上架', x + w / 2, y + 60); }
    g.fillStyle = '#f2c3c8'; g.beginPath(); g.arc(x + 12, y + h - 12, 3, 0, TAU); g.fill(); g.fillStyle = '#f1dca0'; g.beginPath(); g.arc(x + 20, y + h - 10, 2, 0, TAU); g.fill();
  }

  // ———— 展示柜、收银台 ————
  function caseSlots(n) {
    const cols = n <= 6 ? 3 : (n <= 9 ? 3 : 4), rows = Math.ceil(n / cols), out = [];
    const ih = CASE.base - 40 - CASE.top - 14;
    for (let i = 0; i < n; i++) { const c = i % cols, r = Math.floor(i / cols); out.push({ x: CASE.x + 18 + (c + .5) * (CASE.w - 36) / cols, y: CASE.top + 14 + (r + 1) * ih / rows - 6, w: (CASE.w - 36) / cols }); }
    return out;
  }
  function displayCase(g, slots, recipesById, t) {
    const { x, w, top, base } = CASE;
    softShadow(g, x + w / 2, base + 4, w * .58, 12, .22);
    // 木头底座
    const bg = g.createLinearGradient(0, base - 40, 0, base); bg.addColorStop(0, '#d9bf9c'); bg.addColorStop(1, '#bf9d76');
    g.fillStyle = bg; rr(g, x, base - 40, w, 40, 5); g.fill();
    g.strokeStyle = 'rgba(120,85,55,.3)'; g.lineWidth = 1; for (let i = 0; i < 3; i++) { rr(g, x + 10 + i * (w - 20) / 3, base - 32, (w - 20) / 3 - 8, 24, 3); g.stroke(); }
    g.fillStyle = '#c8a96c'; g.fillRect(x, base - 42, w, 3);
    // 玻璃柜
    g.fillStyle = 'rgba(232,242,244,.35)'; rr(g, x + 4, top, w - 8, base - 42 - top, 6); g.fill();
    const n = slots.length, pos = caseSlots(n), rows = Math.ceil(n / (n <= 9 ? 3 : 4));
    for (let r = 1; r <= rows; r++) { const yy = top + 14 + r * (base - 40 - top - 14) / rows - 4; g.fillStyle = 'rgba(255,255,255,.55)'; g.fillRect(x + 8, yy, w - 16, 3); g.fillStyle = 'rgba(200,169,108,.4)'; g.fillRect(x + 8, yy + 3, w - 16, 1); }
    slots.forEach((s, i) => {
      const p = pos[i];
      if (s && s.n > 0 && recipesById[s.rid]) {
        const r = recipesById[s.rid], W = Math.min(46, p.w * .86);
        if (s.n > 1) ART.dessert(g, r, p.x - W * .22, p.y - 3, W * .78, { plate: false });
        ART.dessert(g, r, p.x + (s.n > 1 ? W * .12 : 0), p.y, W, { plate: false });
        // 价签
        g.fillStyle = '#fbf7f1'; rr(g, p.x - 15, p.y + 1, 30, 11, 3); g.fill();
        g.strokeStyle = 'rgba(200,169,108,.7)'; g.lineWidth = .8; rr(g, p.x - 15, p.y + 1, 30, 11, 3); g.stroke();
        g.fillStyle = '#7a5a48'; g.font = '600 7.5px "PingFang SC", sans-serif'; g.textAlign = 'center'; g.fillText('¥' + s.price + ' ×' + s.n, p.x, p.y + 9.5);
      } else {
        g.strokeStyle = 'rgba(160,140,120,.35)'; g.setLineDash([3, 3]); g.lineWidth = 1; ellipse(g, p.x, p.y - 6, p.w * .3, 6); g.stroke(); g.setLineDash([]);
      }
    });
    // 玻璃反光、金边
    const gl = g.createLinearGradient(x, top, x + w, base); gl.addColorStop(0, 'rgba(255,255,255,.35)'); gl.addColorStop(.35, 'rgba(255,255,255,0)'); gl.addColorStop(.6, 'rgba(255,255,255,.12)'); gl.addColorStop(.7, 'rgba(255,255,255,0)');
    g.fillStyle = gl; rr(g, x + 4, top, w - 8, base - 42 - top, 6); g.fill();
    g.strokeStyle = '#d8c39f'; g.lineWidth = 2; rr(g, x + 4, top, w - 8, base - 42 - top, 6); g.stroke();
  }
  function counter(g, t, bakerBusy) {
    const { x, w, top, base } = COUNTER;
    // 她在柜台后
    ART.baker(g, x + 52, top + 6, 1.05, t, { busy: bakerBusy });
    softShadow(g, x + w / 2, base + 4, w * .6, 10, .2);
    const cg = g.createLinearGradient(0, top, 0, base); cg.addColorStop(0, '#e9dccb'); cg.addColorStop(1, '#d6c3a8');
    g.fillStyle = cg; rr(g, x, top + 8, w, base - top - 8, 4); g.fill();
    g.fillStyle = '#f6efe6'; rr(g, x - 4, top, w + 8, 10, 3); g.fill();
    g.strokeStyle = 'rgba(150,120,90,.3)'; g.lineWidth = 1; for (let i = 0; i < 2; i++) { rr(g, x + 8 + i * (w - 16) / 2, top + 18, (w - 16) / 2 - 6, base - top - 28, 3); g.stroke(); }
    // 收银机
    g.fillStyle = '#c8a96c'; rr(g, x + 10, top - 22, 34, 22, 4); g.fill(); g.fillStyle = '#e8d29a'; rr(g, x + 14, top - 30, 26, 10, 3); g.fill();
    g.fillStyle = '#7a5a48'; for (let i = 0; i < 6; i++) { g.beginPath(); g.arc(x + 17 + (i % 3) * 9, top - 14 + Math.floor(i / 3) * 6, 1.6, 0, TAU); g.fill(); }
    // 小花瓶
    g.fillStyle = 'rgba(220,235,240,.8)'; rr(g, x + 74, top - 18, 12, 18, 4); g.fill();
    g.strokeStyle = '#8fae7c'; g.lineWidth = 1.2; for (const dx of [-3, 0, 3]) { g.beginPath(); g.moveTo(x + 80, top - 14); g.lineTo(x + 80 + dx * 2, top - 30); g.stroke(); }
    g.fillStyle = '#f3c4cf'; for (const dx of [-3, 0, 3]) { g.beginPath(); g.arc(x + 80 + dx * 2, top - 32, 3, 0, TAU); g.fill(); }
  }

  // ———— 家具 ————
  const DRAW = {
    table(g, x, y, k) {
      // 小圆桌 + 两把藤椅
      for (const s of [-1, 1]) { g.fillStyle = '#c9a27c'; rr(g, x + s * 30 * k - 9 * k, y - 34 * k, 18 * k, 4 * k, 2 * k); g.fill(); g.strokeStyle = '#b48a68'; g.lineWidth = 2 * k; g.beginPath(); g.moveTo(x + s * 30 * k - 7 * k, y - 30 * k); g.lineTo(x + s * 30 * k - 8 * k, y); g.moveTo(x + s * 30 * k + 7 * k, y - 30 * k); g.lineTo(x + s * 30 * k + 8 * k, y); g.stroke(); g.fillStyle = '#e9d9bf'; rr(g, x + s * 30 * k - 10 * k, y - 62 * k, 20 * k, 30 * k, 8 * k); g.fill(); g.strokeStyle = 'rgba(170,130,90,.5)'; g.lineWidth = 1; for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(x + s * 30 * k - 8 * k, y - 62 * k + i * 7 * k); g.lineTo(x + s * 30 * k + 8 * k, y - 62 * k + i * 7 * k); g.stroke(); } }
      g.fillStyle = '#8a7a6a'; g.fillRect(x - 1.5 * k, y - 40 * k, 3 * k, 38 * k); ellipse(g, x, y - 2 * k, 12 * k, 3 * k); g.fill();
      const tg = g.createLinearGradient(x - 24 * k, 0, x + 24 * k, 0); tg.addColorStop(0, '#e9e2d8'); tg.addColorStop(.5, '#fbf8f2'); tg.addColorStop(1, '#ddd3c6');
      g.fillStyle = tg; ellipse(g, x, y - 42 * k, 24 * k, 7 * k); g.fill(); g.fillStyle = '#d8cbb8'; g.fillRect(x - 24 * k, y - 42 * k, 48 * k, 2 * k);
      g.fillStyle = '#fff'; ellipse(g, x + 6 * k, y - 44 * k, 5 * k, 2 * k); g.fill(); g.fillStyle = '#c8a96c'; rr(g, x - 9 * k, y - 50 * k, 6 * k, 7 * k, 1.5 * k); g.fill();
    },
    armchair(g, x, y, k) {
      const c = '#c98b8f';
      g.fillStyle = '#8a6a50'; for (const s of [-1, 1]) g.fillRect(x + s * 16 * k - 1.5 * k, y - 8 * k, 3 * k, 8 * k);
      g.fillStyle = shade(c, -.08); rr(g, x - 22 * k, y - 50 * k, 44 * k, 36 * k, 14 * k); g.fill();
      g.fillStyle = c; rr(g, x - 20 * k, y - 26 * k, 40 * k, 18 * k, 6 * k); g.fill();
      for (const s of [-1, 1]) { g.fillStyle = shade(c, .06); rr(g, x + s * 19 * k - 6 * k, y - 34 * k, 12 * k, 26 * k, 6 * k); g.fill(); }
      g.strokeStyle = 'rgba(255,255,255,.25)'; g.lineWidth = 1; for (let i = -1; i <= 1; i++) { g.beginPath(); g.moveTo(x + i * 10 * k, y - 46 * k); g.lineTo(x + i * 10 * k, y - 30 * k); g.stroke(); }
    },
    plant(g, x, y, k) {
      g.fillStyle = '#e8dccb'; g.beginPath(); g.moveTo(x - 13 * k, y - 26 * k); g.lineTo(x + 13 * k, y - 26 * k); g.lineTo(x + 10 * k, y); g.lineTo(x - 10 * k, y); g.fill();
      g.fillStyle = '#d9c7ae'; g.fillRect(x - 13 * k, y - 26 * k, 26 * k, 4 * k);
      const leaves = [[-1, -62, -.5, 1], [1, -70, .4, 1.1], [0, -82, 0, 1], [-1, -46, -1, .9], [1, -50, .9, .9]];
      for (const [s, ly, a, sz] of leaves) {
        g.strokeStyle = '#6f8f5e'; g.lineWidth = 1.5 * k; g.beginPath(); g.moveTo(x, y - 26 * k); g.quadraticCurveTo(x + s * 4 * k, y + ly * k * .6, x + s * 14 * k, y + ly * k); g.stroke();
        g.save(); g.translate(x + s * 14 * k, y + ly * k); g.rotate(a); const lg = g.createLinearGradient(-14 * k, 0, 14 * k, 0); lg.addColorStop(0, '#6f9a6a'); lg.addColorStop(1, '#9cc08f');
        g.fillStyle = lg; g.beginPath(); g.ellipse(0, 0, 15 * k * sz, 11 * k * sz, 0, 0, TAU); g.fill();
        g.fillStyle = 'rgba(250,247,240,.9)'; for (let i = -2; i <= 2; i++) { if (!i) continue; g.beginPath(); g.ellipse(i * 4.5 * k * sz, 5 * k * sz * (i % 2 ? 1 : -1) * .4, 1.4 * k, 4 * k, i * .3, 0, TAU); g.fill(); }
        g.restore();
      }
    },
    flowerpot(g, x, y, k) {
      g.fillStyle = '#d9a99a'; g.beginPath(); g.moveTo(x - 10 * k, y - 20 * k); g.lineTo(x + 10 * k, y - 20 * k); g.lineTo(x + 7 * k, y); g.lineTo(x - 7 * k, y); g.fill();
      g.fillStyle = '#e9bfb3'; g.fillRect(x - 11 * k, y - 22 * k, 22 * k, 4 * k);
      const R = rng(Math.round(x));
      for (let i = 0; i < 7; i++) { const fx = x + (R() - .5) * 22 * k, fy = y - (28 + R() * 18) * k; g.strokeStyle = '#7f9a5c'; g.lineWidth = 1.2 * k; g.beginPath(); g.moveTo(x, y - 22 * k); g.lineTo(fx, fy); g.stroke(); g.fillStyle = ['#f3c4cf', '#fff6e0', '#e8b4b8', '#c7bcd8'][i % 4]; for (let p = 0; p < 5; p++) { const a = p / 5 * TAU; g.beginPath(); g.arc(fx + Math.cos(a) * 2.6 * k, fy + Math.sin(a) * 2.6 * k, 2.2 * k, 0, TAU); g.fill(); } g.fillStyle = '#f1dca0'; g.beginPath(); g.arc(fx, fy, 1.4 * k, 0, TAU); g.fill(); }
    },
    bookshelf(g, x, y, k) {
      g.fillStyle = '#b48a68'; rr(g, x - 28 * k, y - 86 * k, 56 * k, 86 * k, 3 * k); g.fill();
      g.fillStyle = '#e9dccb'; for (let r = 0; r < 3; r++) g.fillRect(x - 24 * k, y - 82 * k + r * 27 * k, 48 * k, 23 * k);
      const cols = ['#c98b8f', '#a9b89a', '#c7bcd8', '#d9bf9c', '#8fa3b8', '#e8b4b8'];
      for (let r = 0; r < 3; r++) { let bx = x - 23 * k; let i = r * 3; while (bx < x + 20 * k) { const bw = (4 + (i * 7 % 4)) * k, bh = (16 + (i * 5 % 6)) * k; g.fillStyle = cols[i % cols.length]; g.fillRect(bx, y - 60 * k + r * 27 * k - bh + 1 * k - 22 * k + 22 * k, bw, bh); bx += bw + 1 * k; i++; } }
    },
    gramophone(g, x, y, k) {
      g.fillStyle = '#8a6a50'; rr(g, x - 18 * k, y - 22 * k, 36 * k, 22 * k, 3 * k); g.fill();
      g.fillStyle = '#2d2a2e'; ellipse(g, x, y - 23 * k, 15 * k, 4 * k); g.fill();
      g.strokeStyle = '#c8a96c'; g.lineWidth = 2 * k; g.beginPath(); g.moveTo(x + 10 * k, y - 24 * k); g.quadraticCurveTo(x + 14 * k, y - 46 * k, x + 4 * k, y - 52 * k); g.stroke();
      const hg = g.createLinearGradient(x - 22 * k, 0, x + 10 * k, 0); hg.addColorStop(0, '#f1dca0'); hg.addColorStop(1, '#c8a96c');
      g.fillStyle = hg; g.beginPath(); g.moveTo(x + 4 * k, y - 52 * k); g.lineTo(x - 22 * k, y - 76 * k); g.quadraticCurveTo(x - 30 * k, y - 60 * k, x - 20 * k, y - 46 * k); g.closePath(); g.fill();
    },
    cakestand(g, x, y, k) {
      g.fillStyle = '#c8a96c'; g.fillRect(x - 1 * k, y - 70 * k, 2 * k, 70 * k); ellipse(g, x, y - 2 * k, 10 * k, 3 * k); g.fill();
      for (const [ty, r] of [[-20, 20], [-42, 15], [-62, 10]]) {
        g.fillStyle = '#fbf8f2'; ellipse(g, x, y + ty * k, r * k, 4 * k); g.fill(); g.strokeStyle = '#d8c39f'; g.lineWidth = .8; ellipse(g, x, y + ty * k, r * k, 4 * k); g.stroke();
        const cols = ['#f2c3c8', '#bccb9c', '#f1dd8e', '#c7bcd8'];
        for (let i = 0; i < Math.round(r / 6); i++) { const px = x + (i - (r / 6 - 1) / 2) * 9 * k; g.fillStyle = cols[(i + r) % 4]; ellipse(g, px, y + ty * k - 4 * k, 3.6 * k, 2.6 * k); g.fill(); ellipse(g, px, y + ty * k - 1.5 * k, 3.6 * k, 2.6 * k); g.fill(); }
      }
    },
    teddy(g, x, y, k) {
      const c = '#c99a6a';
      g.fillStyle = c; ellipse(g, x, y - 14 * k, 13 * k, 14 * k); g.fill();
      for (const s of [-1, 1]) { ellipse(g, x + s * 8 * k, y - 3 * k, 6 * k, 4 * k); g.fill(); ellipse(g, x + s * 13 * k, y - 18 * k, 4 * k, 7 * k); g.fill(); }
      ellipse(g, x, y - 36 * k, 12 * k, 11 * k); g.fill();
      for (const s of [-1, 1]) { ellipse(g, x + s * 9 * k, y - 45 * k, 4.5 * k, 4.5 * k); g.fill(); }
      g.fillStyle = '#e9cfae'; ellipse(g, x, y - 32 * k, 5 * k, 4 * k); g.fill(); ellipse(g, x, y - 13 * k, 7 * k, 8 * k); g.fill();
      g.fillStyle = '#3a2a26'; for (const s of [-1, 1]) { g.beginPath(); g.arc(x + s * 4 * k, y - 38 * k, 1.3 * k, 0, TAU); g.fill(); } g.beginPath(); g.arc(x, y - 33 * k, 1.4 * k, 0, TAU); g.fill();
      g.fillStyle = '#e8b4b8'; g.beginPath(); g.moveTo(x - 6 * k, y - 26 * k); g.lineTo(x, y - 24 * k); g.lineTo(x + 6 * k, y - 26 * k); g.lineTo(x + 6 * k, y - 22 * k); g.lineTo(x, y - 24 * k); g.lineTo(x - 6 * k, y - 22 * k); g.fill();
    },
    // —— 墙上的 ——
    frame(g, x, y, k) {
      g.fillStyle = '#c8a96c'; rr(g, x - 22 * k, y - 28 * k, 44 * k, 56 * k, 3 * k); g.fill();
      const pg = g.createLinearGradient(0, y - 24 * k, 0, y + 24 * k); pg.addColorStop(0, '#c7d9e8'); pg.addColorStop(.6, '#e9e2c8'); pg.addColorStop(1, '#a9b89a');
      g.fillStyle = pg; g.fillRect(x - 17 * k, y - 23 * k, 34 * k, 46 * k);
      g.fillStyle = '#e8b4b8'; for (let i = 0; i < 5; i++) { g.beginPath(); g.arc(x - 10 * k + i * 5 * k, y + 12 * k - (i % 2) * 3 * k, 2.2 * k, 0, TAU); g.fill(); }
      g.fillStyle = '#8fae7c'; g.beginPath(); g.arc(x + 8 * k, y - 4 * k, 6 * k, 0, TAU); g.fill();
    },
    clock(g, x, y, k, t) {
      g.fillStyle = '#b48a68'; g.beginPath(); g.arc(x, y, 18 * k, 0, TAU); g.fill();
      g.fillStyle = '#fbf8f2'; g.beginPath(); g.arc(x, y, 14.5 * k, 0, TAU); g.fill();
      g.fillStyle = '#7a5a48'; for (let i = 0; i < 12; i++) { const a = i / 12 * TAU; g.beginPath(); g.arc(x + Math.cos(a) * 11.5 * k, y + Math.sin(a) * 11.5 * k, (i % 3 ? .8 : 1.4) * k, 0, TAU); g.fill(); }
      const h = (t / 60) % 12, m = t % 60;
      g.strokeStyle = '#4a3a33'; g.lineCap = 'round';
      g.lineWidth = 1.8 * k; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.sin(h / 12 * TAU) * 7 * k, y - Math.cos(h / 12 * TAU) * 7 * k); g.stroke();
      g.lineWidth = 1.1 * k; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.sin(m / 60 * TAU) * 10 * k, y - Math.cos(m / 60 * TAU) * 10 * k); g.stroke();
    },
    wreath(g, x, y, k) {
      for (let i = 0; i < 18; i++) { const a = i / 18 * TAU; g.fillStyle = i % 2 ? '#8fae7c' : '#6f9a6a'; g.save(); g.translate(x + Math.cos(a) * 16 * k, y + Math.sin(a) * 16 * k); g.rotate(a + 1.2); g.beginPath(); g.ellipse(0, 0, 6 * k, 3 * k, 0, 0, TAU); g.fill(); g.restore(); }
      for (let i = 0; i < 6; i++) { const a = i / 6 * TAU + .3; g.fillStyle = ['#f3c4cf', '#fff6e0', '#e8b4b8'][i % 3]; g.beginPath(); g.arc(x + Math.cos(a) * 16 * k, y + Math.sin(a) * 16 * k, 3.4 * k, 0, TAU); g.fill(); }
      g.fillStyle = '#e8b4b8'; for (const s of [-1, 1]) { g.beginPath(); g.ellipse(x + s * 5 * k, y + 18 * k, 5 * k, 3 * k, s * .4, 0, TAU); g.fill(); }
    },
    mirror(g, x, y, k) {
      g.fillStyle = '#c8a96c'; g.beginPath(); g.moveTo(x - 18 * k, y + 30 * k); g.lineTo(x - 18 * k, y - 14 * k); g.arc(x, y - 14 * k, 18 * k, Math.PI, 0); g.lineTo(x + 18 * k, y + 30 * k); g.fill();
      const mg = g.createLinearGradient(x - 14 * k, y - 28 * k, x + 14 * k, y + 26 * k); mg.addColorStop(0, '#eef3f4'); mg.addColorStop(.5, '#d6e2e6'); mg.addColorStop(1, '#eef3f4');
      g.fillStyle = mg; g.beginPath(); g.moveTo(x - 14 * k, y + 26 * k); g.lineTo(x - 14 * k, y - 14 * k); g.arc(x, y - 14 * k, 14 * k, Math.PI, 0); g.lineTo(x + 14 * k, y + 26 * k); g.fill();
      g.strokeStyle = 'rgba(255,255,255,.7)'; g.lineWidth = 2 * k; g.beginPath(); g.moveTo(x - 8 * k, y + 10 * k); g.lineTo(x + 2 * k, y - 18 * k); g.stroke();
    },
    garland(g, x, y, k, t) {
      g.strokeStyle = '#6b5a50'; g.lineWidth = 1; g.beginPath(); g.moveTo(x - 45 * k, y - 6 * k); g.quadraticCurveTo(x, y + 14 * k, x + 45 * k, y - 6 * k); g.stroke();
      for (let i = 0; i <= 8; i++) { const u = i / 8, px = x - 45 * k + u * 90 * k, py = y - 6 * k + 4 * u * (1 - u) * 20 * k * .5 + 2 * k; const on = .6 + .4 * Math.sin(t * 3 + i); const gl = g.createRadialGradient(px, py + 3 * k, 0, px, py + 3 * k, 8 * k); gl.addColorStop(0, `rgba(255,220,150,${.5 * on})`); gl.addColorStop(1, 'rgba(255,220,150,0)'); g.fillStyle = gl; g.beginPath(); g.arc(px, py + 3 * k, 8 * k, 0, TAU); g.fill(); g.fillStyle = ['#fff3d6', '#f6d3da', '#d9ecf2'][i % 3]; ellipse(g, px, py + 3 * k, 2.4 * k, 3.2 * k); g.fill(); }
    },
    drawing(g, x, y, k) {
      g.save(); g.translate(x, y); g.rotate(-.06);
      g.fillStyle = '#fffdf8'; g.fillRect(-17 * k, -20 * k, 34 * k, 40 * k);
      ART.clawd(g, 0, 12 * k, .38 * k, 0, {});
      g.strokeStyle = '#f3c4cf'; g.lineWidth = 1.5; g.beginPath(); g.arc(-10 * k, -12 * k, 3 * k, 0, TAU); g.stroke();
      g.fillStyle = '#d9a46c'; g.fillRect(-2 * k, -22 * k, 4 * k, 5 * k);
      g.restore();
    },
    pennant(g, x, y, k) {
      g.strokeStyle = '#8a7a6a'; g.lineWidth = 1; g.beginPath(); g.moveTo(x - 25 * k, y - 10 * k); g.lineTo(x + 25 * k, y - 10 * k); g.stroke();
      g.fillStyle = '#a9c9b6'; g.beginPath(); g.moveTo(x - 25 * k, y - 10 * k); g.lineTo(x + 25 * k, y - 10 * k); g.lineTo(x, y + 18 * k); g.fill();
      g.fillStyle = '#fbf7f1'; g.font = `600 ${8 * k}px "PingFang SC", sans-serif`; g.textAlign = 'center'; g.fillText('跑团', x, y + 1 * k);
    },
    trophy(g, x, y, k) {
      g.fillStyle = '#b48a68'; rr(g, x - 10 * k, y + 8 * k, 20 * k, 6 * k, 1.5 * k); g.fill();
      const tg = g.createLinearGradient(x - 12 * k, 0, x + 12 * k, 0); tg.addColorStop(0, '#c8a96c'); tg.addColorStop(.5, '#f6e3a4'); tg.addColorStop(1, '#b8944f');
      g.fillStyle = tg; g.fillRect(x - 2 * k, y, 4 * k, 9 * k);
      g.beginPath(); g.moveTo(x - 12 * k, y - 16 * k); g.lineTo(x + 12 * k, y - 16 * k); g.quadraticCurveTo(x + 11 * k, y + 2 * k, x, y + 2 * k); g.quadraticCurveTo(x - 11 * k, y + 2 * k, x - 12 * k, y - 16 * k); g.fill();
      g.strokeStyle = '#c8a96c'; g.lineWidth = 2 * k; for (const s of [-1, 1]) { g.beginPath(); g.arc(x + s * 13 * k, y - 10 * k, 5 * k, s > 0 ? -1.5 : 1.6, s > 0 ? 1.5 : 4.7); g.stroke(); }
    },
  };
  function decorItem(g, d, t, clock, highlight) {
    const def = DECOR[d.kind]; if (!def || !DRAW[d.kind]) return;
    if (def.place === 'floor') {
      const y = floorY(d.z), k = depthK(d.z);
      softShadow(g, d.x, y, (def.w * .55) * k, 7 * k, .2);
      DRAW[d.kind](g, d.x, y, k, clock);
      if (highlight) { g.strokeStyle = 'rgba(232,180,184,.95)'; g.lineWidth = 2; g.setLineDash([4, 3]); ellipse(g, d.x, y, def.w * .6 * k, 10 * k); g.stroke(); g.setLineDash([]); }
    } else {
      DRAW[d.kind](g, d.x, d.y, 1, d.kind === 'clock' ? clock : t);
      if (highlight) { g.strokeStyle = 'rgba(232,180,184,.95)'; g.lineWidth = 2; g.setLineDash([4, 3]); rr(g, d.x - def.w * .6, d.y - 34, def.w * 1.2, 68, 8); g.stroke(); g.setLineDash([]); }
    }
  }
  // 家具能放在哪：地上的在左边那块（门和展示柜之间），墙上的不挡窗、黑板和架子
  function clampDecor(d) {
    const def = DECOR[d.kind];
    if (def.place === 'floor') { d.x = Math.max(124, Math.min(440, d.x)); d.z = Math.max(0, Math.min(1, d.z)); }
    else { d.x = Math.max(126 + def.w / 2, Math.min(450 - def.w / 2, d.x)); d.y = Math.max(40, Math.min(232, d.y)); }
    return d;
  }
  // 椅子：每张桌子两个座位，扶手椅一个
  function seats(decor) {
    const out = [];
    for (const d of decor) {
      if (d.kind === 'table') for (const s of [-1, 1]) out.push({ x: d.x + s * 30 * depthK(d.z), z: d.z, decor: d, side: s });
      if (d.kind === 'armchair') out.push({ x: d.x, z: d.z, decor: d, side: 1, chair: true });
    }
    return out;
  }

  return { WW, WH, FLOOR, floorY, depthK, CASE, COUNTER, wallpaper, floor, windowArch, door, lamps, shelves, chalkboard, displayCase, caseSlots, counter, decorItem, clampDecor, seats, DRAW };
})();
