// 店里的人：她（甜点师）、clawd、客人。跟甜点一样走 INK，三种画风都能画。
// 客人按类型穿不一样的衣服：学生水手领、上班族衬衫领带、奶奶开衫和珍珠项链、情侣荷叶边裙子、小朋友背带裤、
// 健身的姐姐运动外套和帽子、评论家大衣和贝雷帽。头发一缕缕、有一道亮光，眼睛大、带两点高光。
'use strict';

const PEOPLE = (() => {
  const { TAU, ell, paint, stroke, tone, trace } = INK;
  const P = (pts, dx = 0, dy = 0, k = 1) => pts.map(([x, y]) => [dx + x * k, dy + y * k]);
  const S = () => INK.style();

  // 眼睛：眼白不画（Q 版），一颗大大的深色眼珠、下半截浅一点、两点高光；开心就是两道弯弯
  function eyes(g, hx, hy, r, mood, col = '#3a2a26', lash = false) {
    for (const s of [-1, 1]) {
      const ex = hx + s * r * .36, ey = hy + r * .12;
      if (mood === 'happy' || mood === 'blink') { g.strokeStyle = S() === 'paper' ? col : '#3a2a26'; g.lineWidth = r * .09; g.lineCap = 'round'; g.beginPath(); g.arc(ex, ey + r * .03, r * .13, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); continue; }
      paint(g, ell(ex, ey, r * .13, r * .17, 0, TAU, S() === 'paper' ? 7 : 0, 3), col, { lw: r / 26, flat: true, line: S() === 'candy' });
      if (S() !== 'paper') { const gr = g.createLinearGradient(0, ey - r * .1, 0, ey + r * .17); gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(1, 'rgba(255,220,200,.45)'); g.fillStyle = gr; g.beginPath(); g.ellipse(ex, ey, r * .13, r * .17, 0, 0, TAU); g.fill(); }
      g.fillStyle = '#ffffff'; g.beginPath(); g.ellipse(ex + r * .04, ey - r * .06, r * .05, r * .06, 0, 0, TAU); g.fill(); g.beginPath(); g.arc(ex - r * .05, ey + r * .08, r * .025, 0, TAU); g.fill();
      if (lash && S() !== 'paper') { g.strokeStyle = '#2b1d18'; g.lineWidth = r * .045; g.beginPath(); g.arc(ex, ey + r * .02, r * .19, Math.PI * 1.15, Math.PI * 1.85); g.stroke(); g.beginPath(); g.moveTo(ex + s * r * .16, ey - r * .1); g.lineTo(ex + s * r * .24, ey - r * .17); g.stroke(); }
    }
    g.fillStyle = 'rgba(240,140,140,.42)';
    for (const s of [-1, 1]) { g.beginPath(); g.ellipse(hx + s * r * .58, hy + r * .38, r * .15, r * .085, 0, 0, TAU); g.fill(); }
    if (S() === 'story') { g.strokeStyle = 'rgba(220,110,110,.5)'; g.lineWidth = r * .02; for (const s of [-1, 1]) for (let i = 0; i < 3; i++) { g.beginPath(); g.moveTo(hx + s * r * (.5 + i * .06), hy + r * .42); g.lineTo(hx + s * r * (.53 + i * .06), hy + r * .34); g.stroke(); } }
  }
  function mouth(g, hx, hy, r, mood) {
    g.strokeStyle = '#a5524e'; g.lineWidth = r * .07; g.lineCap = 'round'; g.beginPath();
    if (mood === 'sad') g.arc(hx, hy + r * .58, r * .13, Math.PI * 1.15, Math.PI * 1.85);
    else if (mood === 'think') { g.moveTo(hx - r * .08, hy + r * .46); g.lineTo(hx + r * .08, hy + r * .46); }
    else if (mood === 'eat') { g.fillStyle = '#c96a6a'; g.ellipse(hx, hy + r * .45, r * .07, r * .06, 0, 0, TAU); g.fill(); return; }
    else g.arc(hx, hy + r * .33, r * .13, Math.PI * .15, Math.PI * .85);
    g.stroke();
  }
  // 头发：后面一片 + 刘海（几簇尖尖的）+ 一道亮光
  function hairBack(g, hx, hy, r, col, style) {
    if (style === 'long') paint(g, [[hx - r * 1.05, hy - r * .1], [hx - r * 1.1, hy + r * 1.5], [hx - r * .6, hy + r * 1.75], [hx + r * .6, hy + r * 1.75], [hx + r * 1.1, hy + r * 1.5], [hx + r * 1.05, hy - r * .1]], tone(col, -.08), { lw: r / 18, seed: 31 });
    if (style === 'bob') paint(g, [[hx - r * 1.08, hy - r * .1], [hx - r * 1.1, hy + r * .75], [hx - r * .7, hy + r * .82], [hx + r * .7, hy + r * .82], [hx + r * 1.1, hy + r * .75], [hx + r * 1.08, hy - r * .1]], tone(col, -.08), { lw: r / 18, seed: 32 });
  }
  function hairFront(g, hx, hy, r, col, style) {
    const cap = ell(hx, hy - r * .02, r * 1.07, r * 1.05, Math.PI * 1.02, Math.PI * 1.98, 0, 7);
    // 刘海：五簇，每簇一个尖
    const fringe = []; const n = 5;
    for (let i = n; i >= 0; i--) { const t = i / n, x = hx - r * 1.04 + t * r * 2.08; fringe.push([x, hy - r * (.22 + (i % 2 ? 0 : .1))]); if (i > 0) fringe.push([x - r * .21, hy - r * (i % 2 ? .02 : .1) + r * .04]); }
    paint(g, [...cap, ...fringe], col, { lw: r / 18, seed: 9 });
    if (S() !== 'paper') { g.save(); g.strokeStyle = 'rgba(255,255,255,.35)'; g.lineWidth = r * .1; g.lineCap = 'round'; g.beginPath(); g.arc(hx, hy - r * .1, r * .78, Math.PI * 1.25, Math.PI * 1.6); g.stroke(); g.restore(); }   // 头发的亮光
    if (style === 'bun') { paint(g, ell(hx, hy - r * 1.12, r * .38, r * .34, 0, TAU, 0, 11), col, { lw: r / 18, seed: 11 }); }
    if (style === 'pony') { paint(g, [[hx + r * .8, hy - r * .55], [hx + r * 1.35, hy - r * .2], [hx + r * 1.25, hy + r * .55], [hx + r * 1.05, hy + r * .2]], col, { lw: r / 18, seed: 12 }); }
    if (style === 'short') { for (const s of [-1, 1]) paint(g, [[hx + s * r * .98, hy - r * .2], [hx + s * r * 1.05, hy + r * .25], [hx + s * r * .86, hy + r * .1]], col, { lw: r / 22, seed: 13 }); }
  }
  // 衣服上的小细节（按客人类型）
  function outfit(g, type, x, top, k, look) {
    const lw = k;
    switch (type) {
      case 'student': paint(g, [[x - 12 * k, top + 1 * k], [x, top + 12 * k], [x + 12 * k, top + 1 * k], [x + 9 * k, top + 6 * k], [x, top + 15 * k], [x - 9 * k, top + 6 * k]], '#f6f2ea', { lw: lw * .7, flat: true }); paint(g, [[x - 4 * k, top + 12 * k], [x + 4 * k, top + 12 * k], [x + 6 * k, top + 19 * k], [x, top + 16 * k], [x - 6 * k, top + 19 * k]], '#d9566b', { lw: lw * .7, flat: true }); break;
      case 'office': paint(g, [[x - 5 * k, top], [x, top + 6 * k], [x + 5 * k, top]], '#ffffff', { lw: lw * .6, flat: true }); paint(g, [[x - 1.6 * k, top + 4 * k], [x + 1.6 * k, top + 4 * k], [x + 2.2 * k, top + 17 * k], [x, top + 19 * k], [x - 2.2 * k, top + 17 * k]], '#8a5a6a', { lw: lw * .6, flat: true }); break;
      case 'granny': for (let i = 0; i < 9; i++) { const a = Math.PI * (.15 + i / 8 * .7); paint(g, ell(x + Math.cos(a) * 9 * k, top + Math.sin(a) * 6 * k, 1.4 * k, 1.4 * k, 0, TAU, 6, i), '#fbf8f2', { lw: lw * .4, flat: true, gloss: true, line: S() === 'candy' }); } break;
      case 'couple': for (let i = 0; i < 6; i++) paint(g, ell(x - 10 * k + i * 4 * k, top + 21 * k, 2.6 * k, 1.8 * k, 0, Math.PI, 0, i), '#fbf3f0', { lw: lw * .5, flat: true }); break;
      case 'kid': for (const s of [-1, 1]) paint(g, [[x + s * 6 * k, top], [x + s * 8 * k, top], [x + s * 6 * k, top + 12 * k], [x + s * 4 * k, top + 12 * k]], tone(look.bottom, -.05), { lw: lw * .5, flat: true }); break;
      case 'athlete': stroke(g, [[x, top + 1 * k], [x, top + 22 * k]], '#fbf8f2', 1.4 * k); for (const s of [-1, 1]) stroke(g, [[x + s * 12 * k, top + 4 * k], [x + s * 13 * k, top + 20 * k]], '#fbf8f2', 1.2 * k); break;
      case 'critic': paint(g, [[x - 13 * k, top], [x - 3 * k, top + 14 * k], [x - 7 * k, top + 2 * k]], tone(look.top, .15), { lw: lw * .6, flat: true }); paint(g, [[x + 13 * k, top], [x + 3 * k, top + 14 * k], [x + 7 * k, top + 2 * k]], tone(look.top, .15), { lw: lw * .6, flat: true }); break;
    }
  }

  // 客人
  function person(g, look, x, y, k, { t = 0, walk = false, mood = 'idle', facing = 1, eating = false, type = 'student' } = {}) {
    const bob = walk ? Math.abs(Math.sin(t * 9)) * 2.2 * k : Math.sin(t * 2) * .6 * k;
    const sw = walk ? Math.sin(t * 9) * 5 * k : 0;
    g.save(); g.fillStyle = 'rgba(80,55,40,.18)'; g.beginPath(); g.ellipse(x, y, 17 * k, 4.5 * k, 0, 0, TAU); g.fill(); g.restore();
    g.save(); g.translate(x, y - bob); g.scale(facing, 1);
    const lw = k;
    // 腿和鞋
    for (const s of [-1, 1]) {
      const lx = s * 5.5 * k + (s < 0 ? sw * .3 : -sw * .3);
      paint(g, [[lx - 3.4 * k, -24 * k], [lx + 3.4 * k, -24 * k], [lx + 3 * k, -3 * k], [lx - 3 * k, -3 * k]], look.legs || '#efd9c8', { lw: lw * .7, flat: true });
      paint(g, ell(lx + s * .5 * k, -1.6 * k, 5 * k, 2.8 * k, 0, TAU, 0, 21), look.shoe || '#6b4a3a', { lw: lw * .7, flat: true, gloss: true });
    }
    // 下装
    const skirt = look.style === 'short' || look.pants;
    if (skirt) for (const s of [-1, 1]) paint(g, [[s * 1 * k, -38 * k], [s * 12 * k, -38 * k], [s * 10 * k, -20 * k], [s * 1.5 * k, -20 * k]], look.bottom, { lw, seed: 40 + s });
    else paint(g, [[-11 * k, -38 * k], [11 * k, -38 * k], [16 * k, -19 * k], [8 * k, -17.5 * k], [0, -19 * k], [-8 * k, -17.5 * k], [-16 * k, -19 * k]], look.bottom, { lw, seed: 42 });
    // 上衣
    paint(g, [[-12 * k, -58 * k], [12 * k, -58 * k], [14 * k, -37 * k], [-14 * k, -37 * k]].map(([a, b], i) => [a, b + (i < 2 ? 0 : 0)]), look.top, { lw, seed: 44 });
    outfit(g, look.type || 'student', 0, -58 * k, k, look);
    // 手臂
    for (const s of [-1, 1]) {
      g.save(); g.translate(s * 12 * k, -55 * k); g.rotate(s * .22 + (walk ? -s * sw * .03 : 0) + (eating && s > 0 ? -1.7 : 0));
      paint(g, [[-3.5 * k, 0], [3.5 * k, 0], [3 * k, 15 * k], [-3 * k, 15 * k]], tone(look.top, -.05), { lw: lw * .8, seed: 46 + s });
      paint(g, ell(0, 17 * k, 3.6 * k, 3.6 * k, 0, TAU, 0, 47), look.skin, { lw: lw * .7, flat: true });
      g.restore();
    }
    // 头
    const hy = -78 * k, hr = 21 * k;
    hairBack(g, 0, hy, hr, look.hair, look.style === 'long' ? 'long' : look.style === 'bob' ? 'bob' : null);
    paint(g, ell(0, hy, hr, hr * .96, 0, TAU, 0, 50), look.skin, { lw, seed: 50 });
    eyes(g, 0, hy, hr, mood);
    mouth(g, 0, hy, hr, eating ? 'eat' : mood);
    hairFront(g, 0, hy, hr, look.hair, look.style);
    if (look.glasses) { g.strokeStyle = '#4a3a33'; g.lineWidth = 1.3 * k; for (const s of [-1, 1]) { g.beginPath(); g.arc(s * hr * .36, hy + hr * .12, hr * .21, 0, TAU); g.stroke(); } g.beginPath(); g.moveTo(-hr * .15, hy + hr * .1); g.lineTo(hr * .15, hy + hr * .1); g.stroke(); }
    if (look.bow) for (const s of [-1, 1]) paint(g, [[hr * .55, hy - hr * .82], [hr * .55 + s * hr * .42, hy - hr * 1.02], [hr * .55 + s * hr * .4, hy - hr * .6]], look.bow, { lw: lw * .7, seed: 60 + s });
    if (look.cap) { paint(g, ell(0, hy - hr * .3, hr * 1.06, hr * .8, Math.PI, TAU, 0, 61), look.cap, { lw, seed: 61 }); paint(g, ell(hr * .7, hy - hr * .3, hr * .55, hr * .14, 0, TAU, 0, 62), tone(look.cap, -.1), { lw, seed: 62 }); }
    if (look.beret) paint(g, [...ell(-hr * .1, hy - hr * .78, hr * .95, hr * .38, 0, TAU, 0, 63)], look.beret, { lw, seed: 63 });
    g.restore();
  }

  // 她：棕色辫子、粉色蝴蝶结、粉色针织毛衣、米白荷叶边围裙
  function baker(g, x, y, k, t = 0, { mood = 'idle', busy = false } = {}) {
    const bob = Math.sin(t * 2.2) * .8 * k;
    g.save(); g.translate(x, y - bob);
    const lw = k, HAIR = '#5b3a2e', PINK = '#efb3be';
    for (const s of [-1, 1]) paint(g, [[s * 9 * k - 3.4 * k, -20 * k], [s * 9 * k + 3.4 * k, -20 * k], [s * 9 * k + 3 * k, 0], [s * 9 * k - 3 * k, 0]], '#6f4337', { lw: lw * .7, flat: true });
    paint(g, [[-13 * k, -40 * k], [13 * k, -40 * k], [17 * k, -16 * k], [-17 * k, -16 * k]], '#f7efe6', { lw, seed: 70 });
    // 毛衣：一道道竖纹
    paint(g, [[-14 * k, -63 * k], [14 * k, -63 * k], [15.5 * k, -37 * k], [-15.5 * k, -37 * k]], PINK, { lw, seed: 71 });
    if (INK.style() !== 'paper') for (let i = -3; i <= 3; i++) stroke(g, [[i * 4 * k, -61 * k], [i * 4.3 * k, -39 * k]], tone(PINK, -.12, .7), .7 * k);
    paint(g, [[-6 * k, -66 * k], [6 * k, -66 * k], [6.5 * k, -61 * k], [-6.5 * k, -61 * k]], tone(PINK, -.06), { lw: lw * .7, seed: 72 });   // 高领
    // 围裙：上面一片、荷叶边下摆
    const apron = [[-9 * k, -57 * k], [9 * k, -57 * k], [11 * k, -22 * k]];
    for (let i = 0; i <= 6; i++) apron.push([11 * k - i * 22 * k / 6, -22 * k + (i % 2 ? 3 * k : 0)]);
    paint(g, apron, '#fbf6ee', { lw, seed: 73 });
    stroke(g, [[-8 * k, -48 * k], [8 * k, -48 * k]], '#e8c4c8', 1 * k);
    paint(g, ell(0, -40 * k, 3.6 * k, 2.6 * k, 0, TAU, 0, 74), '#f2b8c2', { lw: lw * .6, flat: true });
    for (const s of [-1, 1]) {
      g.save(); g.translate(s * 13 * k, -58 * k); g.rotate(s * -.3 + (busy ? Math.sin(t * 10 + s) * .4 : 0));
      paint(g, [[-4 * k, 0], [4 * k, 0], [3.4 * k, 15 * k], [-3.4 * k, 15 * k]], PINK, { lw: lw * .8, seed: 75 + s });
      paint(g, ell(0, 17 * k, 3.6 * k, 3.6 * k, 0, TAU, 0, 77), '#f8dfd2', { lw: lw * .7, flat: true });
      g.restore();
    }
    const hy = -85 * k, hr = 22 * k;
    // 两条辫子：一节一节
    for (const s of [-1, 1]) {
      for (let i = 0; i < 4; i++) paint(g, ell(s * hr * .95, hy + hr * (.35 + i * .3), hr * (.22 - i * .02), hr * .19, 0, TAU, 0, 80 + i), i % 2 ? HAIR : tone(HAIR, .08), { lw: lw * .8, seed: 80 + i });
      paint(g, ell(s * hr * .95, hy + hr * 1.55, hr * .14, hr * .07, 0, TAU, 0, 85), '#f08ea0', { lw: lw * .6, flat: true });
      paint(g, [[s * hr * .88, hy + hr * 1.6], [s * hr * 1.02, hy + hr * 1.6], [s * hr * .95, hy + hr * 1.85]], HAIR, { lw: lw * .6, flat: true });
    }
    paint(g, ell(0, hy, hr, hr * .96, 0, TAU, 0, 86), '#f8e1d4', { lw, seed: 86 });
    eyes(g, 0, hy, hr, mood, '#5a3426', true);
    mouth(g, 0, hy, hr, mood);
    hairFront(g, 0, hy, hr, HAIR, 'girl');
    // 蝴蝶结
    for (const s of [-1, 1]) paint(g, [[hr * .55, hy - hr * .82], [hr * .55 + s * hr * .5, hy - hr * 1.08], [hr * .55 + s * hr * .46, hy - hr * .58]], '#f08ea0', { lw: lw * .8, seed: 88 + s });
    paint(g, ell(hr * .55, hy - hr * .82, hr * .09, hr * .09, 0, TAU, 0, 90), '#e57d91', { lw: lw * .6, flat: true });
    g.restore();
  }

  // clawd：橙色的小方块，眼睛那么高两侧各一块扁扁的手，底下四根小腿，头上一顶有褶子的厨师帽
  function clawd(g, x, y, k, t = 0, { job = null, walk = false, mood = 'idle', facing = 1 } = {}) {
    const C = '#dd7a5c', CD = '#c86a4e';
    const bob = walk ? Math.abs(Math.sin(t * 10)) * 2.5 * k : Math.sin(t * 2.6) * .7 * k;
    g.save(); g.fillStyle = 'rgba(80,55,40,.18)'; g.beginPath(); g.ellipse(x, y, 22 * k, 5 * k, 0, 0, TAU); g.fill(); g.restore();
    g.save(); g.translate(x, y); g.scale(facing, 1);
    const lw = k;
    [-15, -6, 6, 15].forEach((lx, i) => { const up = walk ? Math.max(0, Math.sin(t * 10 + i * Math.PI / 2)) * 2.5 * k : 0; paint(g, [[lx * k - 2.6 * k, -12 * k - up], [lx * k + 2.6 * k, -12 * k - up], [lx * k + 2.6 * k, -up], [lx * k - 2.6 * k, -up]], i % 2 ? CD : C, { lw: lw * .7, flat: true }); });
    g.translate(0, -bob);
    const body = []; const rx = 22 * k, top = -41 * k, bot = -10 * k, rr = 8 * k;
    for (const [cx, cy, a0] of [[rx - rr, top + rr, -Math.PI / 2], [rx - rr, bot - rr, 0], [-rx + rr, bot - rr, Math.PI / 2], [-rx + rr, top + rr, Math.PI]]) body.push(...ell(cx, cy, rr, rr, a0, a0 + Math.PI / 2, 4, 1));
    paint(g, body, C, { lw, seed: 95 });
    const wave = job === 'greet' ? Math.sin(t * 8) * .5 : 0;
    paint(g, [[-29 * k, -34 * k], [-22 * k, -34 * k], [-22 * k, -24 * k], [-29 * k, -24 * k]], C, { lw: lw * .8, seed: 96 });
    g.save(); g.translate(22 * k, -29 * k); g.rotate(-wave); paint(g, [[0, -5 * k], [7 * k, -5 * k], [7 * k, 5 * k], [0, 5 * k]], C, { lw: lw * .8, seed: 97 }); g.restore();
    if (mood === 'happy') { g.strokeStyle = '#1d1614'; g.lineWidth = 2 * k; for (const s of [-1, 1]) { g.beginPath(); g.arc(s * 8 * k, -26 * k, 3 * k, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); } }
    else for (const s of [-1, 1]) { paint(g, [[s * 8 * k - 2.2 * k, -31 * k], [s * 8 * k + 2.2 * k, -31 * k], [s * 8 * k + 2.2 * k, -22 * k], [s * 8 * k - 2.2 * k, -22 * k]], '#1d1614', { lw: lw * .5, flat: true, line: false }); g.fillStyle = '#fff'; g.beginPath(); g.ellipse(s * 8 * k + .8 * k, -29 * k, 1 * k, 1.3 * k, 0, 0, TAU); g.fill(); }
    g.fillStyle = 'rgba(255,170,150,.6)'; for (const s of [-1, 1]) { g.beginPath(); g.ellipse(s * 14 * k, -20 * k, 3 * k, 1.8 * k, 0, 0, TAU); g.fill(); }
    // 厨师帽：帽圈 + 三团鼓起来的布，布上几道褶
    paint(g, [[-10 * k, -47 * k], [10 * k, -47 * k], [10 * k, -40 * k], [-10 * k, -40 * k]], '#fbf8f2', { lw: lw * .8, seed: 98 });
    paint(g, [...ell(-6 * k, -51 * k, 6.5 * k, 6 * k, Math.PI * .5, Math.PI * 1.6, 0, 99), ...ell(0, -55 * k, 7.5 * k, 7 * k, Math.PI * 1.1, Math.PI * 1.9, 0, 100), ...ell(6 * k, -51 * k, 6.5 * k, 6 * k, Math.PI * 1.4, Math.PI * 2.5, 0, 101)], '#fbf8f2', { lw: lw * .8, seed: 102 });
    for (const dx of [-3, 3]) stroke(g, [[dx * k, -47 * k], [dx * 1.3 * k, -56 * k]], 'rgba(190,175,160,.8)', .8 * k);
    if (job === 'clean') { g.save(); g.translate(26 * k, -20 * k); g.rotate(.4 + Math.sin(t * 6) * .25); paint(g, [[-1.2 * k, -20 * k], [1.2 * k, -20 * k], [1.2 * k, 10 * k], [-1.2 * k, 10 * k]], '#a77f5c', { lw: lw * .5, flat: true }); paint(g, [[-6 * k, 10 * k], [6 * k, 10 * k], [4 * k, 18 * k], [-4 * k, 18 * k]], '#e8d29a', { lw: lw * .6, flat: true }); g.restore(); }
    g.restore();
  }

  return { person, baker, clawd };
})();
