// 华丽版：哥特维多利亚庄园、大理石喷泉、石座花瓮、深色绿篱和深红玫瑰
import * as THREE from 'three';
import { bake, R, jit, box, cyl, cone, ball, torus, blob, lathe, tri3 } from './kit.js';

export const G = {
  stone: '#e6dccb', stoneD: '#cfc3ae', stoneL: '#f1eadf', marble: '#f3efe8', marbleV: '#e4ddd2',
  slate: '#4d5561', slateD: '#3f4651', slateL: '#5d6672',
  iron: '#2c3330', gold: '#c9a45c', door: '#6a2730', doorD: '#561f27',
  glassDark: '#2b3540', stained: ['#24365a', '#5c1f2c', '#1f3050', '#8a6a34', '#2a3f5c', '#3e2a4c'],
  hedge: '#3f5a3b', hedgeL: '#4d6a47', rose: '#9b2f42', roseL: '#c46172', water: '#6e93a6', lamp: '#f6d79a',
};
const GOLD = { mat: 'gold' };
const at = (o) => (geo, color, opt = {}) => {
  const p = opt.p || [0, 0, 0];
  return bake(geo, color, { ...opt, ao: opt.ao === false ? null : (opt.matrix ? null : o.t), p: opt.matrix ? p : [o.cx + p[0], o.t + p[1], o.cz + p[2]] });
};
const frameM = (o, x, y, z, ry = 0) => new THREE.Matrix4().makeRotationY(ry).setPosition(o.cx + x, o.t + y, o.cz + z);

function archShape(w, h, pointed) {
  const s = new THREE.Shape(), hs = h - (pointed ? w * .85 : w / 2);
  s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, hs);
  if (pointed) { s.quadraticCurveTo(w / 2, hs + w * .55, 0, h); s.quadraticCurveTo(-w / 2, hs + w * .55, -w / 2, hs); }
  else s.absarc(0, hs, w / 2, 0, Math.PI, false);
  s.lineTo(-w / 2, 0); return s;
}
function slab(shape, depth, hole = null) {
  if (hole) shape.holes.push(hole);
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 12 });
  g.translate(0, 0, -depth / 2); return g;
}

// 一扇哥特尖拱窗：深深的石窗套、上面一道滴水线脚、深色玻璃配金色窗棂；stained = 彩绘玻璃
function lancet(m, w, h, { stained = false, sill = true } = {}) {
  const put = (g, c, opt = {}) => bake(g, c, { ...opt, matrix: m });
  put(slab(archShape(w + .12, h + .08, true), .08, archShape(w, h, true)), G.stoneL, { p: [0, -.04, .03] });
  put(slab(archShape(w + .2, h + .14, true), .03, archShape(w + .13, h + .09, true)), G.stoneD, { p: [0, -.07, .07] });   // 滴水线脚
  if (stained) {
    const rows = 5, cols = 2;
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) put(box(w / cols - .006, (h - w * .85) / rows - .006, .015), G.stained[(r * 3 + c * 2) % G.stained.length], { p: [-w / 4 + c * w / 2, (r + .5) * (h - w * .85) / rows, 0], mat: 'glass' });
    put(slab(archShape(w, h, true), .012), G.stained[4], { p: [0, 0, -.004], mat: 'glass' });
  } else put(slab(archShape(w, h, true), .015), G.glassDark, { p: [0, 0, 0], mat: 'glass' });
  put(box(.014, h - .02, .02), G.gold, { p: [0, (h - .02) / 2, .012], ...GOLD });
  for (const y of [.33, .66]) put(box(w, .012, .02), G.gold, { p: [0, (h - w * .85) * y, .012], ...GOLD });
  put(torus(w * .14, .008, 4, 14), G.gold, { p: [0, h - w * .5, .012], ...GOLD });
  for (const sx of [-1, 1]) put(torus(w * .1, .006, 4, 12), G.gold, { p: [sx * w * .2, h - w * .78, .012], ...GOLD });
  if (sill) put(box(w + .2, .04, .1), G.stoneL, { p: [0, -.05, .05] });
}
// 尖顶小塔（尖锥 + 一圈小金球 + 顶上金色尖饰）
function pinnacle(put, x, y, z, s = 1) {
  put(box(.1 * s, .18 * s, .1 * s), G.stoneL, { p: [x, y + .09 * s, z] });
  put(cone(.075 * s, .34 * s, 4), G.stone, { p: [x, y + .35 * s, z], r: [0, Math.PI / 4, 0] });
  for (let k = 0; k < 3; k++) for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) put(ball(.016 * s, 6, 4), G.gold, { p: [x + dx * .05 * s * (1 - k * .28), y + (.23 + k * .09) * s, z + dz * .05 * s * (1 - k * .28)], ...GOLD });
  put(ball(.025 * s, 8, 6), G.gold, { p: [x, y + .53 * s, z], ...GOLD });
  put(cone(.012 * s, .12 * s, 6), G.gold, { p: [x, y + .6 * s, z], ...GOLD });
}
// 尖锥顶：石板瓦一圈圈、金色腰线、尖饰
function spire(put, x, y, z, r, h, seg = 8) {
  put(cone(r, h, seg), G.slate, { p: [x, y + h / 2, z], r: [0, Math.PI / seg, 0] });
  for (let i = 1; i < 7; i++) { const k = i / 7; put(cyl(r * (1 - k) + .012, r * (1 - k) + .012, .018, seg), i % 2 ? G.slateD : G.slateL, { p: [x, y + h * k, z], r: [0, Math.PI / seg, 0] }); }
  put(cyl(r + .03, r + .03, .04, seg), G.gold, { p: [x, y + .02, z], r: [0, Math.PI / seg, 0], ...GOLD });
  put(ball(.05, 10, 8), G.gold, { p: [x, y + h + .04, z], ...GOLD });
  put(cyl(.012, .012, .3, 6), G.gold, { p: [x, y + h + .2, z], ...GOLD });
  put(box(.12, .014, .014), G.gold, { p: [x, y + h + .26, z], ...GOLD });
}
// 石栏杆：底座、一排车削的小柱、扶手
function balustrade(put, x, y, z, len, axis = 'x') {
  const bal = lathe([[.028, 0], [.028, .02], [.02, .04], [.034, .1], [.016, .16], [.024, .18], [.024, .2]], 8);
  const along = (t) => axis === 'x' ? [x + t, z] : [x, z + t];
  put(box(axis === 'x' ? len : .1, .04, axis === 'x' ? .1 : len), G.stoneL, { p: [x, y + .02, z] });
  put(box(axis === 'x' ? len + .04 : .12, .04, axis === 'x' ? .12 : len + .04), G.stoneL, { p: [x, y + .26, z] });
  const n = Math.max(2, Math.round(len / .075));
  for (let i = 0; i < n; i++) { const [px, pz] = along(-len / 2 + (i + .5) * len / n); put(bal, G.marble, { p: [px, y + .04, pz] }); }
}

// ———————— 庄园 ————————
export function grandManor(o, d) {
  const put = at(o);
  const Wd = d.w * .95, Dp = 2.5, y0 = .32, fh = .98, top = y0 + fh * 2, zc = -Dp / 2 + .15, fz = zc + Dp / 2;
  // 勒脚：粗面石，一道道横缝
  put(box(Wd + .16, y0, Dp + .16), G.stoneD, { p: [0, y0 / 2, zc] });
  for (let y = .08; y < y0; y += .08) put(box(Wd + .17, .008, Dp + .17), '#b7aa93', { p: [0, y, zc], ao: false });
  // 墙身 + 楼层之间一道线脚 + 檐口（一排齿饰、一道金线）
  put(box(Wd, fh * 2, Dp), G.stone, { p: [0, y0 + fh, zc] });
  for (const y of [y0 + fh, top]) {
    put(box(Wd + .1, .06, Dp + .1), G.stoneL, { p: [0, y - .03, zc] });
    put(box(Wd + .16, .04, Dp + .16), G.stoneL, { p: [0, y + .02, zc] });
  }
  for (let x = -Wd / 2 + .04; x < Wd / 2; x += .07) put(box(.035, .04, .04), G.stoneL, { p: [x, top - .08, fz + .03], ao: false });
  put(box(Wd + .02, .012, .01), G.gold, { p: [0, top - .13, fz + .006], ...GOLD });
  // 转角隅石（一长一短咬合）
  for (const sx of [-1, 1]) for (let k = 0; k < 12; k++) put(box(k % 2 ? .2 : .12, .15, .03), G.stoneL, { p: [sx * (Wd / 2 - (k % 2 ? .1 : .06)), y0 + .08 + k * .163, fz + .012], ao: false });
  // 两层的尖拱窗：楼下深色玻璃，楼上彩绘
  const cw = 1.3;   // 中间凸出来的门楼宽
  for (const floor of [0, 1]) for (const sx of [-1, 1]) for (const k of [0, 1]) {
    const x = sx * (cw / 2 + .32 + k * .48);
    if (Math.abs(x) > Wd / 2 - .25) continue;
    lancet(frameM(o, x, y0 + .2 + floor * fh, fz + .005), .24, .6, { stained: floor === 1 });
  }
  for (const sx of [-1, 1]) for (const floor of [0, 1]) lancet(frameM(o, sx * (Wd / 2 + .005), y0 + .2 + floor * fh, zc - .25, sx * Math.PI / 2), .24, .6, { stained: floor === 1 });
  // 门楼：往前凸一截，比两边高，顶上一个陡陡的尖山墙
  const pz = fz + .3, ph = top + .25;
  put(box(cw, ph, .62), G.stone, { p: [0, ph / 2, fz - .02] });
  for (const sx of [-1, 1]) {   // 门楼两边的扶壁，一层层往里收，顶上小尖塔
    for (let k = 0; k < 3; k++) put(box(.16 - k * .03, ph * (1 - k * .28), .2 - k * .04), G.stoneL, { p: [sx * (cw / 2 + .05), ph * (1 - k * .28) / 2, pz + .02 - k * .02] });
    pinnacle(put, sx * (cw / 2 + .05), ph, pz + .02, 1.1);
  }
  // 大门：尖拱门洞，两边大理石柱，门是深勃艮第红、金色门钉，门上半圆彩绘玻璃
  const dm = frameM(o, 0, y0, pz + .01);
  const pd = (g, c, opt = {}) => bake(g, c, { ...opt, matrix: dm });
  pd(slab(archShape(.74, 1.12, true), .12, archShape(.52, .94, true)), G.stoneL, { p: [0, 0, .02] });
  for (let i = 0; i < 3; i++) pd(slab(archShape(.64 - i * .04, 1.04 - i * .03, true), .03, archShape(.6 - i * .04, 1.0 - i * .03, true)), i % 2 ? G.stoneD : G.marble, { p: [0, 0, .08 - i * .02] });
  pd(slab(archShape(.52, .94, true), .05), G.door, { p: [0, 0, -.02] });
  pd(box(.008, .62, .06), G.doorD, { p: [0, .31, .005] });
  for (let r = 0; r < 4; r++) for (const sx of [-1, 1]) for (let c = 0; c < 2; c++) pd(ball(.012, 6, 4), G.gold, { p: [sx * (.07 + c * .1), .1 + r * .15, .01], ...GOLD });
  for (const sx of [-1, 1]) pd(torus(.035, .008, 4, 12), G.gold, { p: [sx * .06, .36, .012], ...GOLD });
  const tg = slab(archShape(.5, .3, true), .015); tg.translate(0, .62, 0); pd(tg, G.stained[1], { p: [0, 0, .004], mat: 'glass' });
  for (let k = 0; k < 5; k++) pd(box(.008, .26, .02), G.gold, { p: [-.16 + k * .08, .74, .012], ...GOLD });
  const col = lathe([[.06, 0], [.06, .05], [.045, .08], [.04, .82], [.055, .86], [.07, .92], [.07, .95]], 14);
  for (const sx of [-1, 1]) { pd(box(.15, .1, .15), G.stoneD, { p: [sx * .38, .05, .08] }); pd(col, G.marble, { p: [sx * .38, .1, .08] }); pd(ball(.02, 6, 4), G.gold, { p: [sx * .38, 1.07, .14], ...GOLD }); }
  // 二楼阳台（石栏杆）+ 大玫瑰窗
  balustrade(put, 0, y0 + fh + .02, pz + .2, cw - .1);
  put(box(cw - .06, .06, .32), G.stoneL, { p: [0, y0 + fh + .01, pz + .1] });
  for (const sx of [-1, 0, 1]) put(cone(.07, .18, 4), G.stoneD, { p: [sx * .45, y0 + fh - .1, pz + .2], r: [Math.PI, Math.PI / 4, 0] });   // 托石
  const rose = frameM(o, 0, y0 + fh + .62, pz + .015);
  const pr = (g, c, opt = {}) => bake(g, c, { ...opt, matrix: rose });
  const RR = .38;
  pr(torus(RR + .03, .05, 8, 40), G.stoneL, { p: [0, 0, .02] });
  for (let k = 0; k < 12; k++) {   // 十二瓣彩绘玻璃 + 金色窗棂
    const a0 = k / 12 * Math.PI * 2;
    const g = new THREE.CircleGeometry(RR, 4, a0, Math.PI / 6); pr(g, G.stained[k % G.stained.length], { p: [0, 0, 0], mat: 'glass' });
    pr(box(RR, .014, .02), G.gold, { p: [Math.cos(a0) * RR / 2, Math.sin(a0) * RR / 2, .01], r: [0, 0, a0], ...GOLD });
    pr(torus(.055, .008, 4, 12), G.gold, { p: [Math.cos(a0 + .26) * RR * .7, Math.sin(a0 + .26) * RR * .7, .012], ...GOLD });
  }
  pr(torus(RR * .38, .012, 4, 24), G.gold, { p: [0, 0, .012], ...GOLD });
  pr(new THREE.CircleGeometry(RR * .36, 24), G.stained[2], { p: [0, 0, .002], mat: 'glass' });
  // 门楼的尖山墙：两坡石板瓦、一路金色卷叶小球、顶上大尖饰
  const gh = 1.0, gy = ph;
  put(tri3([-cw / 2, gy, pz - .01], [cw / 2, gy, pz - .01], [0, gy + gh, pz - .01]), G.stone, { ao: false });
  const L = Math.hypot(cw / 2 + .08, gh + .05), ang = Math.atan2(gh, cw / 2);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationZ(-s * ang).setPosition(o.cx + s * cw / 4, o.t + gy + gh / 2 + .02, o.cz + pz - .32);
    bake(box(L, .06, .66), G.slate, { matrix: m });
    bake(box(L + .02, .08, .07), G.stoneL, { matrix: m, p: [0, .02, .32] });
    for (let k = 1; k < 7; k++) bake(ball(.026, 8, 6), G.gold, { matrix: m, p: [-L / 2 + k * L / 7, .085, .32], mat: 'gold' });
  }
  pinnacle(put, 0, gy + gh - .05, pz - .02, 1.8);
  // 主屋顶：很陡的两坡，石板瓦一行行深浅相间；屋脊上一排铁艺花边（金尖）
  const rh = 1.25, half = Dp / 2 + .14, slope = Math.hypot(half, rh), rang = Math.atan2(rh, half);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(s * rang).setPosition(o.cx, o.t + top + rh / 2, o.cz + zc + s * half / 2);
    bake(box(Wd + .26, .05, slope), G.slateD, { matrix: m });
    const rows = 12;
    for (let i = 0; i < rows; i++) bake(box(Wd + .27, .02, slope / rows + .01), i % 3 === 0 ? G.slateL : G.slate, { matrix: m, p: [0, .03 + (rows - i) * .002, s * (-slope / 2 + (i + .5) * slope / rows)] });
  }
  for (const sx of [-1, 1]) put(tri3([sx * Wd / 2, top, zc - Dp / 2], [sx * Wd / 2, top, zc + Dp / 2], [sx * Wd / 2, top + rh, zc]).applyMatrix4(new THREE.Matrix4().makeScale(1, 1, 1)), G.stone, { ao: false });
  put(box(Wd + .3, .05, .06), G.slateD, { p: [0, top + rh + .02, zc] });
  for (let x = -Wd / 2; x <= Wd / 2 + .001; x += .1) {
    put(cyl(.006, .006, .12, 4), G.iron, { p: [x, top + rh + .1, zc] });
    put(cone(.016, .05, 4), x % .3 < .1 ? G.gold : G.iron, { p: [x, top + rh + .18, zc], ...(x % .3 < .1 ? GOLD : {}) });
  }
  put(box(Wd + .3, .012, .012), G.iron, { p: [0, top + rh + .13, zc] });
  // 老虎窗：前坡上两扇，带小尖顶
  for (const sx of [-1, 1]) {
    const x = sx * (cw / 2 + .55), z = fz - .35, y = top + .3;
    put(box(.36, .5, .5), G.stone, { p: [x, y + .1, z - .1] });
    lancet(frameM(o, x, y - .08, z + .155), .16, .36, { stained: true, sill: false });
    put(tri3([x - .2, y + .35, z + .15], [x + .2, y + .35, z + .15], [x, y + .65, z + .15]), G.stone, { ao: false });
    for (const s of [-1, 1]) bake(box(Math.hypot(.22, .3), .04, .56), G.slate, { matrix: new THREE.Matrix4().makeRotationZ(-s * Math.atan2(.3, .2)).setPosition(o.cx + x + s * .1, o.t + y + .5, o.cz + z - .1) });
    pinnacle(put, x, y + .62, z + .14, .8);
  }
  // 两头高高的成组烟囱
  for (const sx of [-1, 1]) {
    const x = sx * (Wd / 2 - .3), z = zc - .2;
    put(box(.36, .9, .22), G.stoneD, { p: [x, top + rh * .6 + .3, z] });
    for (const dx of [-.09, .09]) { put(cyl(.06, .07, .4, 8), G.stoneL, { p: [x + dx, top + rh * .6 + .95, z] }); put(cyl(.08, .07, .05, 8), G.stoneL, { p: [x + dx, top + rh * .6 + 1.17, z] }); }
  }
  // 两座八角塔楼
  for (const sx of [-1, 1]) {
    const tx = sx * (Wd / 2 + .1), tz = fz - .2, tr = .46, th = top + .55;
    put(cyl(tr + .05, tr + .07, y0, 8), G.stoneD, { p: [tx, y0 / 2, tz], r: [0, Math.PI / 8, 0] });
    put(cyl(tr, tr, th - y0, 8), G.stone, { p: [tx, y0 + (th - y0) / 2, tz], r: [0, Math.PI / 8, 0] });
    for (const y of [y0 + fh, top]) put(cyl(tr + .04, tr + .04, .06, 8), G.stoneL, { p: [tx, y, tz], r: [0, Math.PI / 8, 0] });
    put(cyl(tr + .1, tr + .04, .14, 8), G.stoneL, { p: [tx, th - .05, tz], r: [0, Math.PI / 8, 0] });   // 塔顶挑出来的一圈
    for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2; put(box(.06, .1, .06), G.stoneL, { p: [tx + Math.cos(a) * (tr + .08), th + .06, tz + Math.sin(a) * (tr + .08)] }); }
    for (const a of [0, sx * .78]) for (const floor of [0, 1]) {
      const fa = Math.PI / 2 - a;   // 朝前和朝侧前
      lancet(frameM(o, tx + Math.cos(fa) * tr * .93, y0 + .22 + floor * fh, tz + Math.sin(fa) * tr * .93, a), .18, .5, { stained: floor === 1 });
    }
    spire(put, tx, th + .02, tz, tr + .08, 1.8);
  }
  // 门前大台阶，两边矮墙上立着石瓮
  for (let i = 0; i < 3; i++) put(box(1.0 + i * .14, .1, .16), i % 2 ? G.stoneL : G.stone, { p: [0, y0 - .05 - i * .1, pz + .12 + i * .16] });
  for (const sx of [-1, 1]) {
    put(box(.14, .36, .62), G.stoneL, { p: [sx * .62, .18, pz + .3] });
    urn(put, sx * .62, .36, pz + .5, .55);
  }
  // 门边一对铁灯笼
  for (const sx of [-1, 1]) {
    const x = sx * .52, y = y0 + .78, z = pz + .1;
    put(box(.04, .14, .1), G.iron, { p: [x, y - .1, z - .04] });
    put(lathe([[.05, 0], [.07, .1], [.07, .16], [.04, .2], [0, .2]], 8), G.lamp, { p: [x, y - .05, z + .04], mat: 'glass' });
    put(cone(.09, .1, 8), G.iron, { p: [x, y + .2, z + .04] });
    put(ball(.02, 6, 4), G.gold, { p: [x, y + .27, z + .04], ...GOLD });
  }
}

// 石瓮：车削的瓮身、金边，里面一蓬花垂下来
export function urn(put, x, y, z, s = 1, flowers = true) {
  put(lathe([[0, 0], [.1, 0], [.1, .03], [.05, .06], [.04, .12], [.09, .16], [.15, .26], [.15, .3], [.17, .32], [0, .32]].map(([a, b]) => [a * s, b * s]), 16), G.marble, { p: [x, y, z] });
  put(torus(.16 * s, .008, 4, 20), G.gold, { p: [x, y + .31 * s, z], r: [Math.PI / 2, 0, 0], ...GOLD });
  if (!flowers) return;
  put(blob(.15 * s, 1, .6), G.hedgeL, { p: [x, y + .36 * s, z] });
  for (let k = 0; k < 9; k++) { const a = k / 9 * 6.28; put(ball(.035 * s, 8, 6), k % 2 ? G.rose : G.roseL, { p: [x + Math.cos(a) * .12 * s, y + (.36 + (k % 3) * .03) * s, z + Math.sin(a) * .12 * s] }); }
  for (let k = 0; k < 4; k++) { const a = k / 4 * 6.28 + .4; put(blob(.04 * s, 0, 1.6), G.hedgeL, { p: [x + Math.cos(a) * .17 * s, y + .22 * s, z + Math.sin(a) * .17 * s] }); }   // 垂下来的叶
}

// 大理石喷泉：八角大水池、中间柱子托着两层盘、顶上小尖
export function fountain(o, d) {
  const put = at(o);
  const r = Math.min(.95, d.w * .46), cz = -(d.h - 1) * .5 + .0;
  put(cyl(r, r + .04, .08, 8), G.stoneD, { p: [0, .04, cz], r: [0, Math.PI / 8, 0] });
  put(cyl(r, r, .26, 8, true), G.marble, { p: [0, .17, cz], r: [0, Math.PI / 8, 0] });
  put(cyl(r - .07, r - .07, .26, 8, true), G.marbleV, { p: [0, .17, cz], r: [0, Math.PI / 8, 0] });
  for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2 + Math.PI / 8 + Math.PI / 8; put(box(2 * r * Math.sin(Math.PI / 8) + .02, .05, .1), G.marble, { p: [Math.cos(a) * (r - .035), .32, cz + Math.sin(a) * (r - .035)], r: [0, -a + Math.PI / 2, 0] }); }
  put(cyl(r - .07, r - .07, .02, 24), G.water, { p: [0, .26, cz], mat: 'water' });
  put(lathe([[.16, 0], [.16, .05], [.1, .1], [.07, .5], [.1, .55], [.12, .6]], 16), G.marble, { p: [0, .2, cz] });
  put(lathe([[0, 0], [.08, 0], [.38, .08], [.42, .12], [.42, .14], [0, .14]], 24), G.marble, { p: [0, .78, cz] });
  put(cyl(.37, .37, .015, 24), G.water, { p: [0, .91, cz], mat: 'water' });
  put(torus(.42, .012, 4, 32), G.gold, { p: [0, .92, cz], r: [Math.PI / 2, 0, 0], ...GOLD });
  put(lathe([[.06, 0], [.04, .25], [.07, .3]], 12), G.marble, { p: [0, .92, cz] });
  put(lathe([[0, 0], [.05, 0], [.2, .05], [.22, .08], [0, .08]], 20), G.marble, { p: [0, 1.2, cz] });
  put(cyl(.19, .19, .012, 20), G.water, { p: [0, 1.28, cz], mat: 'water' });
  put(lathe([[.03, 0], [.02, .12], [.04, .16], [0, .3]], 10), G.gold, { p: [0, 1.28, cz], ...GOLD });
  for (let k = 0; k < 10; k++) { const a = k / 10 * 6.28; put(cyl(.006, .002, .2, 4), '#dcebf2', { p: [Math.cos(a) * .41, .82, cz + Math.sin(a) * .41], mat: 'water' }); }   // 一圈细细的水帘
  for (let k = 0; k < 4; k++) { const a = k / 4 * 6.28 + .4; urn(put, Math.cos(a) * (r + .25), 0, cz + Math.sin(a) * (r + .25), .7); }
}

// 花坛：矮矮的深色黄杨围成方框，里面种满深红玫瑰
export function parterre(o, d) {
  const put = at(o);
  const w = Math.max(.9, d.w * .9), dd = .8;
  for (const [x, z, lw, ld] of [[0, -dd / 2, w, .12], [0, dd / 2, w, .12], [-w / 2, 0, .12, dd], [w / 2, 0, .12, dd]]) put(box(lw, .2, ld, .04), G.hedge, { p: [x, .1, z] });
  for (let i = 0; i < Math.round(w * 9); i++) {
    const x = (R() - .5) * (w - .25), z = (R() - .5) * (dd - .25);
    put(blob(.06, 1), G.hedgeL, { p: [x, .1, z], ao: false });
    put(ball(.035, 8, 6), R() < .6 ? G.rose : G.roseL, { p: [x, .17, z] });
  }
  put(cone(.12, .55, 12), G.hedge, { p: [0, .3, 0] });
}
