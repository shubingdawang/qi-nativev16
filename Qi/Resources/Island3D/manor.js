// 房子和铁艺小物：维多利亚、哥特、洛可可、巴洛克几种。脸朝 +z，原点是占地底边中点
import * as THREE from 'three';
import { bake, R, jit, box, cyl, cone, ball, torus, blob, lathe, tri3 } from './kit.js';
import { P } from './models.js';

const GOLD = '#c8a96c', IRON = '#3f3a3c', SLATE = '#7f8794', SLATED = '#6c7480';

// 一个局部坐标系：先绕 y 转 ry，再挪到 (x, y, z)（相对景的原点）
const frame = (o, x, y, z, ry = 0, rx = 0) => {
  const m = new THREE.Matrix4().makeRotationY(ry);
  if (rx) m.multiply(new THREE.Matrix4().makeRotationX(rx));
  return m.setPosition(o.cx + x, o.t + y, o.cz + z);
};
const at = (m) => (geo, color, opt = {}) => bake(geo, color, { ...opt, matrix: m, ao: null });

// 拱形：pointed = 哥特尖拱，否则半圆拱。spring = 起拱的高度
function archShape(w, h, pointed) {
  const s = new THREE.Shape(), hs = h - (pointed ? w * .85 : w / 2);
  s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, hs);
  if (pointed) { s.quadraticCurveTo(w / 2, hs + w * .55, 0, h); s.quadraticCurveTo(-w / 2, hs + w * .55, -w / 2, hs); }
  else s.absarc(0, hs, w / 2, 0, Math.PI, false);
  s.lineTo(-w / 2, 0);
  return s;
}
function slab(shape, depth, hole = null) {
  if (hole) shape.holes.push(hole);
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 10 });
  g.translate(0, 0, -depth / 2); return g;
}
// 一扇拱窗：窗套、玻璃、窗棂、窗台；gothic 时顶上一个小圆花窗
function archWindow(put, w, h, { pointed = false, trim = P.trim, glass = P.glass, sill = true, curtain = P.curtain } = {}) {
  put(slab(archShape(w + .07, h + .05, pointed), .04, archShape(w, h, pointed)), trim, { p: [0, -.025, .01], line: .006 });
  put(slab(archShape(w, h, pointed), .02), glass, { p: [0, 0, 0], line: 0 });
  for (const sx of [-1, 1]) put(box(w * .3, h * .62, .01), curtain, { p: [sx * w * .32, h * .36, -.012], line: 0 });
  put(box(.016, h * .95, .025), trim, { p: [0, h * .48, .015], line: 0 });
  put(box(w, .016, .025), trim, { p: [0, h * .55, .015], line: 0 });
  if (pointed) { put(torus(w * .16, .01, 4, 14), trim, { p: [0, h - w * .42, .016], line: 0 }); }
  if (sill) put(box(w + .14, .035, .08), trim, { p: [0, -.04, .03], line: .005 });
}
// 尖顶上的小尖塔（铁 / 金）
function finial(put, x, y, z, s = 1, c = GOLD) {
  put(cyl(.012 * s, .02 * s, .12 * s, 6), c, { p: [x, y + .06 * s, z], line: .004 });
  put(ball(.03 * s, 8, 6), c, { p: [x, y + .14 * s, z], line: .005 });
  put(cone(.014 * s, .12 * s, 6), c, { p: [x, y + .22 * s, z], line: .004 });
}
// 一面两坡顶：瓦一排排，scales = 鱼鳞瓦（一排排小半圆）
function gableRoof(o, { w, dep, zc, top, rh, over = .2, roof, roofD, scales = false, trim = P.trim }) {
  const half = dep / 2 + over, slope = Math.hypot(half, rh), ang = Math.atan2(rh, half);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(s * ang).setPosition(o.cx, o.t + top + rh / 2 - .02, o.cz + zc + s * half / 2);
    const put = at(m);
    put(box(w + .44, .05, slope + .02), roofD, { p: [0, -.02, 0], line: .012 });
    const rows = scales ? 9 : 7;
    for (let i = 0; i < rows; i++) {
      const v = -slope / 2 + (i + .5) * slope / rows, c = jit(i % 2 ? roof : roofD, .025);
      if (scales) {
        const n = Math.round((w + .4) / .13);
        for (let k = 0; k < n; k++) put(cyl(.07, .07, .025, 10, false), c, { p: [-(w + .4) / 2 + (k + (i % 2) * .5) * .13 + .03, .02 + (rows - i) * .003, s * (v + slope / rows * .3)], s: [1, 1, 1.3], line: 0 });
        put(box(w + .44, .035, slope / rows * .6), c, { p: [0, .012 + (rows - i) * .003, s * (v - slope / rows * .15)], line: 0 });
      } else {
        put(box(w + .46, .04, slope / rows + .03, .012), c, { p: [0, .025 + (rows - i) * .004, s * v], r: [s * .06, 0, 0], line: .006 });
      }
    }
    put(box(w + .5, .05, .04), trim, { p: [0, -.01, s * (slope / 2 + .01)], line: .006 });
  }
  bake(cyl(.045, .045, w + .5, 10), roofD, { p: [o.cx, o.t + top + rh + .015, o.cz + zc], r: [0, 0, Math.PI / 2], line: .008 });
  // 屋脊上一排小铁花
  for (let x = -w / 2; x <= w / 2 + .01; x += .3) bake(cone(.02, .09, 4), IRON, { p: [o.cx + x, o.t + top + rh + .09, o.cz + zc], line: .004 });
}
// 朝前的一个尖山墙（屋顶上凸出来的那一块），带镂空花边的封檐板、尖顶、山墙里一扇窗
function frontGable(o, { x, w, fz, top, rh, depth = .9, wall, roof, roofD, trim = P.trim, win = 'rose', pointed = true }) {
  const zb = fz - depth;
  // 山墙三角 + 下面一截墙
  const put = (geo, c, opt = {}) => bake(geo, c, { ...opt, ao: null, p: [o.cx + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + (opt.p?.[2] ?? 0)] });
  put(tri3([x - w / 2, top, fz], [x + w / 2, top, fz], [x, top + rh, fz]), wall, { line: 0 });
  // 两坡
  const L = Math.hypot(w / 2 + .1, rh + .06), ang = Math.atan2(rh, w / 2);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationZ(-s * ang).setPosition(o.cx + x + s * (w / 4), o.t + top + rh / 2 + .03, o.cz + (fz + zb) / 2 + .06);
    const pr = at(m);
    pr(box(L, .05, depth + .14), roofD, { line: .01 });
    for (let i = 0; i < 6; i++) pr(box(L / 6 + .02, .035, depth + .16, .01), jit(i % 2 ? roof : roofD, .03), { p: [-L / 2 + (i + .5) * L / 6, .035, 0], line: .005 });
    // 封檐板 + 一排垂下来的小尖（姜饼花边）
    pr(box(L + .02, .07, .03), trim, { p: [0, -.04, depth / 2 + .08], line: .006 });
    const n = Math.round(L / .09);
    for (let k = 0; k < n; k++) pr(cone(.022, .07, 5), trim, { p: [-L / 2 + (k + .5) * L / n, -.1, depth / 2 + .08], r: [Math.PI, 0, 0], line: .004 });
  }
  finial(put, x, top + rh + .04, fz + .05, 1.1);
  // 山墙上的窗
  const m = frame(o, x, top + rh * .22, fz + .015);
  const pw = at(m);
  if (win === 'rose') {   // 圆形玫瑰窗：外圈、玻璃、八根辐条、中间一个小圆
    const r = Math.min(.2, rh * .26);
    pw(torus(r, .03, 6, 22), trim, { p: [0, r + .03, 0], line: .006 });
    pw(cyl(r, r, .02, 22), P.glass, { p: [0, r + .03, -.01], r: [Math.PI / 2, 0, 0], line: 0 });
    for (let k = 0; k < 4; k++) pw(box(r * 2, .014, .02), trim, { p: [0, r + .03, .01], r: [0, 0, k * Math.PI / 4], line: 0 });
    pw(cyl(.04, .04, .03, 12), trim, { p: [0, r + .03, .012], r: [Math.PI / 2, 0, 0], line: 0 });
  } else {
    archWindow(pw, .2, .36, { pointed });
  }
}
// 门：拱门套、门板（凸起的门板 / 铁合页）、门环、门上的扇形亮窗
function door(put, { w = .36, h = .7, pointed = false, color = P.door, trim = P.trim, iron = false }) {
  put(slab(archShape(w + .12, h + .07, pointed), .05, archShape(w, h, pointed)), trim, { p: [0, 0, .02], line: .006 });
  put(slab(archShape(w, h, pointed), .04), color, { p: [0, 0, .01], line: .006 });
  if (iron) for (const y of [.15, .5]) put(box(w * .7, .025, .01), IRON, { p: [-w * .1, y, .035], line: 0 });
  else for (const [x, y, hh] of [[-.075, .14, .2], [.075, .14, .2], [-.075, .42, .24], [.075, .42, .24]]) put(box(.11, hh, .012), new THREE.Color(color).multiplyScalar(1.1), { p: [x, y, .034], line: 0 });
  put(torus(.025, .006, 4, 10), GOLD, { p: [w * .3, h * .45, .04], line: 0 });
}
// 门廊：木平台、车削立柱、栏杆、顶棚和檐下一排小柱子
function porch(o, { x = 0, w, fz, y0, h = .82, roof, trim = P.trim }) {
  const d = .5, put = (geo, c, opt = {}) => bake(geo, c, { ...opt, ao: o.t, p: [o.cx + x + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + fz + (opt.p?.[2] ?? 0)] });
  put(box(w, .08, d), P.woodL, { p: [0, y0 - .04, d / 2] });
  for (let i = 0; i < Math.round(w / .1); i++) put(box(.008, .082, d), P.woodD, { p: [-w / 2 + i * .1, y0 - .04, d / 2], line: 0 });
  const col = lathe([[.04, 0], [.04, .05], [.028, .08], [.03, h * .4], [.04, h * .45], [.028, h * .5], [.028, h - .08], [.04, h - .05], [.045, h]], 10);
  for (const cx of [-w / 2 + .05, -w / 6, w / 6, w / 2 - .05]) put(col, trim, { p: [cx, y0, d - .05], line: .006 });
  // 栏杆（中间留门口）
  for (const side of [-1, 1]) {
    const x0 = side * (w / 2 - .05), x1 = side * .26;
    put(box(Math.abs(x1 - x0), .03, .04), trim, { p: [(x0 + x1) / 2, y0 + .32, d - .05], line: .005 });
    for (let xx = Math.min(x0, x1) + .04; xx < Math.max(x0, x1) - .02; xx += .07) put(cyl(.01, .01, .28, 5), trim, { p: [xx, y0 + .17, d - .05], line: 0 });
  }
  // 顶棚 + 檐下一排小柱子 + 两头的托架
  put(box(w + .16, .05, d + .16), roof, { p: [0, y0 + h + .03, d / 2], r: [.12, 0, 0], line: .01 });
  put(box(w + .1, .05, .04), trim, { p: [0, y0 + h - .02, d - .03], line: .005 });
  for (let xx = -w / 2 + .06; xx < w / 2 - .04; xx += .06) put(cyl(.007, .007, .07, 4), trim, { p: [xx, y0 + h - .08, d - .03], line: 0 });
  // 台阶
  put(box(.5, .06, .16), P.stone, { p: [0, .03 + Math.max(0, y0 - .12), d + .08], line: .006 });
  put(box(.56, .06, .16), P.stone, { p: [0, .03, d + .22], line: .006 });
}
// 地基：石头勒脚，上沿一道线脚
function plinth(o, w, dep, zc, h, c = P.stone) {
  bake(box(w + .12, h, dep + .12), c, { p: [o.cx, o.t + h / 2, o.cz + zc], ao: o.t, line: .01 });
  bake(box(w + .16, .03, dep + .16), P.trim, { p: [o.cx, o.t + h, o.cz + zc], line: .005 });
}
// 墙上一道道护墙板（横线）+ 四角的角板
function siding(o, w, dep, zc, y0, wallH, c) {
  const fz = zc + dep / 2;
  for (let y = y0 + .1; y < y0 + wallH - .04; y += .1) {
    bake(box(w + .005, .008, .006), new THREE.Color(c).multiplyScalar(.9), { p: [o.cx, o.t + y, o.cz + fz + .003], line: 0 });
    for (const sx of [-1, 1]) bake(box(.006, .008, dep), new THREE.Color(c).multiplyScalar(.9), { p: [o.cx + sx * (w / 2 + .003), o.t + y, o.cz + zc], line: 0 });
  }
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) bake(box(.07, wallH, .07), P.trim, { p: [o.cx + sx * w / 2, o.t + y0 + wallH / 2, o.cz + zc + sz * dep / 2], line: .006 });
}

// ———————— 维多利亚：一座角楼、一个尖山墙带玫瑰窗、门廊、鱼鳞瓦 ————————
export function victorian(o, d, { wall = '#e8cfc8', roof = SLATE, roofD = SLATED, accent = '#9aae8a' } = {}) {
  const w = d.w * .8, dep = 2.1, wallH = 1.15, y0 = .22, zc = -dep / 2 + .1, fz = zc + dep / 2, top = y0 + wallH, rh = .8;
  plinth(o, w, dep, zc, y0);
  bake(box(w, wallH, dep), wall, { p: [o.cx, o.t + y0 + wallH / 2, o.cz + zc], ao: o.t });
  siding(o, w, dep, zc, y0, wallH, wall);
  bake(box(w + .06, .06, dep + .06), P.trim, { p: [o.cx, o.t + top - .03, o.cz + zc], line: .006 });   // 檐下一道线脚
  for (let x = -w / 2 + .1; x < w / 2; x += .14) bake(box(.04, .06, .05), P.trim, { p: [o.cx + x, o.t + top - .09, o.cz + fz + .03], line: 0 });   // 檐下小托
  gableRoof(o, { w, dep, zc, top, rh, roof, roofD, scales: true });
  frontGable(o, { x: -w * .18, w: 1.1, fz: fz + .02, top, rh, depth: dep / 2 + .02, wall, roof, roofD, win: 'rose' });
  // 角楼：右前角一座圆塔，比房子高，尖尖的圆锥顶
  const tx = w / 2 - .12, tz = fz - .1, tr = .42, tH = wallH + .55;
  bake(cyl(tr + .04, tr + .06, y0, 16), P.stone, { p: [o.cx + tx, o.t + y0 / 2, o.cz + tz], ao: o.t, line: .008 });
  bake(cyl(tr, tr, tH, 16), wall, { p: [o.cx + tx, o.t + y0 + tH / 2, o.cz + tz], ao: o.t });
  for (const y of [y0 + .02, y0 + wallH, y0 + tH - .02]) bake(torus(tr + .01, .022, 5, 24), P.trim, { p: [o.cx + tx, o.t + y, o.cz + tz], r: [Math.PI / 2, 0, 0], line: .005 });
  bake(cone(tr + .12, 1.15, 16), roofD, { p: [o.cx + tx, o.t + y0 + tH + .57, o.cz + tz], line: .012 });
  for (let i = 0; i < 6; i++) bake(torus(tr + .1 - i * .085, .018, 4, 20), jit(i % 2 ? roof : roofD, .03), { p: [o.cx + tx, o.t + y0 + tH + .08 + i * .17, o.cz + tz], r: [Math.PI / 2, 0, 0], line: 0 });
  finial((g, c, opt) => bake(g, c, { ...opt, p: [o.cx + opt.p[0], o.t + opt.p[1], o.cz + opt.p[2]] }), tx, y0 + tH + 1.12, tz, 1.4);
  for (const a of [-.5, .35]) {   // 角楼上两扇拱窗（一高一低）
    for (const y of [y0 + .3, y0 + wallH + .02]) {
      const m = frame(o, tx + Math.sin(a) * (tr + .005), y, tz + Math.cos(a) * (tr + .005), a);
      archWindow(at(m), .18, .34, { sill: y < 1 });
    }
  }
  // 门廊 + 门
  porch(o, { x: -w * .18, w: 1.3, fz, y0, roof: roofD });
  door(at(frame(o, -w * .18, y0, fz)), { color: '#7e5a4a' });
  bake(slab(archShape(.42, .14, false), .03), P.glass, { p: [o.cx - w * .18, o.t + y0 + .72, o.cz + fz + .02], line: 0 });
  // 门左边一扇高拱窗、侧面两扇
  archWindow(at(frame(o, -w * .42, y0 + .3, fz + .005)), .22, .5, { pointed: false });
  for (const sx of [-1, 1]) archWindow(at(frame(o, sx * (w / 2 + .005), y0 + .3, zc - .2, sx * Math.PI / 2)), .22, .5);
  // 烟囱
  bake(box(.22, .7, .22), P.brick, { p: [o.cx - w * .38, o.t + top + rh * .6, o.cz + zc - .3], line: .01 });
  bake(box(.28, .05, .28), P.ink, { p: [o.cx - w * .38, o.t + top + rh * .6 + .36, o.cz + zc - .3], line: .006 });
  for (const sx of [-1, 1]) bake(cyl(.03, .03, .08, 8), '#b0705c', { p: [o.cx - w * .38 + sx * .05, o.t + top + rh * .6 + .42, o.cz + zc - .3], line: .004 });
  // 门口一对花盆（瓮形）
  for (const sx of [-1, 1]) {
    const px = o.cx - w * .18 + sx * .45, pz = o.cz + fz + .85;
    bake(lathe([[0, 0], [.06, 0], [.04, .04], [.05, .08], [.1, .18], [.11, .2], [0, .2]], 12), P.stone, { p: [px, o.t, pz], line: .006 });
    bake(blob(.1, 1), P.leaf, { p: [px, o.t + .27, pz] });
    for (let k = 0; k < 4; k++) bake(ball(.025, 6, 4), accent === '#9aae8a' ? P.pink : accent, { p: [px + Math.cos(k * 1.6) * .07, o.t + .32, pz + Math.sin(k * 1.6) * .07], line: 0 });
  }
}

// ———————— 哥特小屋：灰石墙、很陡的尖顶、尖拱窗、黑铁合页的尖拱门 ————————
export function gothic(o, d, { wall = '#cfc8be', roof = '#6f6a78', roofD = '#5f5a68' } = {}) {
  const w = d.w * .8, dep = 2.0, wallH = 1.05, y0 = .14, zc = -dep / 2 + .1, fz = zc + dep / 2, top = y0 + wallH, rh = 1.05;
  plinth(o, w, dep, zc, y0, '#b7ada0');
  bake(box(w, wallH, dep), wall, { p: [o.cx, o.t + y0 + wallH / 2, o.cz + zc], ao: o.t });
  // 石墙：零零星星几块凸出来的方石，转角是一上一下咬合的隅石
  for (let i = 0; i < 26; i++) bake(box(.14 + R() * .1, .07, .02), jit(wall, .06).multiplyScalar(.95), { p: [o.cx + (R() - .5) * (w - .3), o.t + y0 + .1 + R() * (wallH - .2), o.cz + fz + .01], line: 0 });
  for (const sx of [-1, 1]) for (let k = 0; k < 7; k++) bake(box(k % 2 ? .16 : .1, .13, .08), '#bdb3a6', { p: [o.cx + sx * (w / 2 - (k % 2 ? .06 : .03)), o.t + y0 + .08 + k * .145, o.cz + fz], line: .004 });
  gableRoof(o, { w, dep, zc, top, rh, over: .16, roof, roofD, scales: true });
  frontGable(o, { x: 0, w: 1.0, fz: fz + .02, top, rh, depth: dep / 2 + .02, wall, roof, roofD, win: 'lancet', pointed: true, trim: '#efe8dc' });
  door(at(frame(o, 0, y0, fz)), { w: .38, h: .78, pointed: true, color: '#5e4a40', iron: true, trim: '#bdb3a6' });
  for (const sx of [-1, 1]) {
    archWindow(at(frame(o, sx * w * .3, y0 + .28, fz + .005)), .2, .55, { pointed: true, trim: '#efe8dc' });
    archWindow(at(frame(o, sx * (w / 2 + .005), y0 + .28, zc - .2, sx * Math.PI / 2)), .2, .55, { pointed: true, trim: '#efe8dc' });
  }
  // 门两边铁灯笼
  for (const sx of [-1, 1]) {
    const px = o.cx + sx * .34, py = o.t + y0 + .62, pz = o.cz + fz + .07;
    bake(box(.08, .12, .08), P.lamp, { p: [px, py, pz], line: .005 });
    bake(cone(.07, .07, 4), IRON, { p: [px, py + .095, pz], r: [0, .78, 0], line: .004 });
    bake(box(.02, .1, .06), IRON, { p: [px, py - .02, pz - .04], line: 0 });
  }
  // 屋侧一堆柴
  for (let r = 0; r < 3; r++) for (let i = 0; i < 4 - r; i++) bake(cyl(.06, .06, .5, 8), jit(P.trunk, .06), { p: [o.cx + w / 2 + .22, o.t + .07 + r * .11, o.cz + zc - .3 + i * .13 + r * .065], r: [Math.PI / 2, 0, 0], line: .006 });
  // 烟囱（石）
  bake(box(.24, .8, .24), '#b7ada0', { p: [o.cx + w * .3, o.t + top + rh * .55, o.cz + zc - .25], line: .01 });
  bake(box(.3, .05, .3), IRON, { p: [o.cx + w * .3, o.t + top + rh * .55 + .41, o.cz + zc - .25], line: .006 });
}

// ———————— 洛可可：浅薄荷绿墙、复折式屋顶（下陡上缓）、圆顶老虎窗、金色小卷花、条纹雨棚 ————————
export function rococo(o, d, { wall = '#d9e3d6', roof = '#a7b3c2', roofD = '#95a1b1', pinkC = '#e9c4c4' } = {}) {
  const w = d.w * .82, dep = 2.0, wallH = 1.1, y0 = .18, zc = -dep / 2 + .1, fz = zc + dep / 2, top = y0 + wallH;
  plinth(o, w, dep, zc, y0, '#e6ddd0');
  bake(box(w, wallH, dep), wall, { p: [o.cx, o.t + y0 + wallH / 2, o.cz + zc], ao: o.t });
  // 壁柱：一根根浅色的扁柱子，柱头上一点金
  for (const x of [-w / 2 + .04, -w / 6, w / 6, w / 2 - .04]) {
    bake(box(.1, wallH, .04), P.trim, { p: [o.cx + x, o.t + y0 + wallH / 2, o.cz + fz + .02], line: .005 });
    bake(box(.14, .05, .06), P.trim, { p: [o.cx + x, o.t + top - .03, o.cz + fz + .03], line: .005 });
    bake(torus(.025, .007, 4, 10), GOLD, { p: [o.cx + x, o.t + top - .1, o.cz + fz + .045], line: 0 });
  }
  bake(box(w + .12, .08, dep + .12), P.trim, { p: [o.cx, o.t + top, o.cz + zc], line: .006 });
  // 复折式屋顶：下面一圈陡的，上面一块缓的
  const h1 = .55, inset = .28, h2 = .2;
  const low = new THREE.CylinderGeometry(Math.SQRT1_2 * 1, Math.SQRT1_2 * 1, 1, 4, 1);
  low.rotateY(Math.PI / 4);
  const mansard = (y, hh, w0, d0, w1, d1, c) => {   // 一个四面梯台
    const g = new THREE.BufferGeometry(), p = [];
    const A = [[-w0 / 2, -d0 / 2], [w0 / 2, -d0 / 2], [w0 / 2, d0 / 2], [-w0 / 2, d0 / 2]], B = [[-w1 / 2, -d1 / 2], [w1 / 2, -d1 / 2], [w1 / 2, d1 / 2], [-w1 / 2, d1 / 2]];
    for (let i = 0; i < 4; i++) { const j = (i + 1) % 4; p.push(A[i][0], 0, A[i][1], B[j][0], hh, B[j][1], A[j][0], 0, A[j][1], A[i][0], 0, A[i][1], B[i][0], hh, B[i][1], B[j][0], hh, B[j][1]); }
    p.push(B[0][0], hh, B[0][1], B[2][0], hh, B[2][1], B[1][0], hh, B[1][1], B[0][0], hh, B[0][1], B[3][0], hh, B[3][1], B[2][0], hh, B[2][1]);
    g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3)); g.computeVertexNormals();
    bake(g, c, { p: [o.cx, o.t + y, o.cz + zc], line: .012 });
  };
  mansard(top + .04, h1, w + .2, dep + .2, w - inset * 2, dep - inset * 2, roofD);
  mansard(top + .04 + h1, h2, w - inset * 2, dep - inset * 2, w - inset * 2 - .5, dep - inset * 2 - .3, roof);
  // 屋顶边上一圈小铁栏，顶上两个金尖
  const ry = o.t + top + .04 + h1;
  for (let x = -w / 2 + inset; x <= w / 2 - inset + .01; x += .1) bake(cyl(.006, .006, .1, 4), IRON, { p: [o.cx + x, ry + .05, o.cz + zc + dep / 2 - inset], line: 0 });
  bake(box(w - inset * 2, .012, .012), IRON, { p: [o.cx, ry + .1, o.cz + zc + dep / 2 - inset], line: 0 });
  for (const sx of [-1, 1]) finial((g, c, opt) => bake(g, c, { ...opt, p: [o.cx + opt.p[0], o.t + opt.p[1], o.cz + opt.p[2]] }), sx * (w / 2 - inset - .25), top + .04 + h1 + h2, zc, 1.2);
  // 老虎窗：从陡坡上探出来，圆拱窗，顶上一道弯弯的小檐
  for (const sx of [-1, 0, 1]) {
    const x = sx * w * .3, zz = fz - .02;
    bake(box(.32, .4, .3), wall, { p: [o.cx + x, o.t + top + .3, o.cz + zz - .12], line: .008 });
    bake(torus(.18, .035, 5, 16, Math.PI), roofD, { p: [o.cx + x, o.t + top + .48, o.cz + zz - .1], s: [1, 1, 3], line: .008 });
    archWindow(at(frame(o, x, top + .12, zz + .035)), .16, .3, { sill: false });
  }
  // 一楼：三扇高拱窗 + 中间一扇双开门，门窗上面金色卷花
  door(at(frame(o, 0, y0, fz)), { w: .42, h: .75, color: '#b9c9b8' });
  for (const sx of [-1, 1]) archWindow(at(frame(o, sx * w * .33, y0 + .25, fz + .005)), .26, .55, { trim: '#fbf7ee' });
  for (const x of [-w * .33, 0, w * .33]) {
    const yy = x === 0 ? y0 + .86 : y0 + .88;
    for (const sx of [-1, 1]) bake(torus(.05, .009, 4, 12, Math.PI * 1.3), GOLD, { p: [o.cx + x + sx * .06, o.t + yy, o.cz + fz + .03], r: [0, 0, sx > 0 ? -.4 : Math.PI + .4], line: 0 });
    bake(ball(.022, 8, 6), GOLD, { p: [o.cx + x, o.t + yy + .03, o.cz + fz + .035], line: 0 });
  }
  // 粉白条纹雨棚（橱窗上）
  for (const sx of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(.55).setPosition(o.cx + sx * w * .33, o.t + y0 + .98, o.cz + fz + .14);
    for (let i = 0; i < 5; i++) bake(box(.08, .022, .3), i % 2 ? P.white : pinkC, { matrix: m, p: [-.16 + i * .08, 0, 0], line: .005 });
    for (let i = 0; i < 5; i++) bake(cyl(.04, .04, .02, 10, false), i % 2 ? P.white : pinkC, { matrix: m, p: [-.16 + i * .08, 0, .15], r: [Math.PI / 2, 0, 0], s: [1, 1, 1], line: 0 });
  }
  // 门口两箱蔬果、一个小黑板
  for (const x of [w * .33 - .15, w * .33 + .17]) {
    bake(box(.28, .16, .2), P.woodL, { p: [o.cx + x, o.t + .08, o.cz + fz + .32], ao: o.t, line: .006 });
    for (let k = 0; k < 4; k++) bake(ball(.045, 7, 5), [P.apple, '#e8c06a', '#9cbf72', P.peach][k], { p: [o.cx + x - .09 + k * .06, o.t + .19, o.cz + fz + .32], line: .004 });
  }
  const bm = frame(o, -w * .33, 0, fz + .4, 0, -.15);
  bake(box(.26, .34, .02), '#4b5148', { matrix: bm, p: [0, .26, 0], line: .006 });
  bake(box(.3, .38, .015), P.woodL, { matrix: bm, p: [0, .26, -.01], line: 0 });
  for (const sx of [-1, 1]) bake(box(.02, .45, .02), P.woodD, { matrix: bm, p: [sx * .13, .22, -.02], line: .004 });
}

// ———————— 巴洛克小亭：圆顶、一圈柱子、台阶 ————————
export function baroque(o, d, { wall = '#efe6da', dome = '#b9c2b4', domeD = '#a5ae9f' } = {}) {
  const r = Math.min(1.2, d.w * .32), zc = -.7, y0 = .3, colH = 1.05;
  for (let i = 0; i < 3; i++) bake(cyl(r + .32 - i * .1, r + .34 - i * .1, .1, 24), jit(P.stone, .03), { p: [o.cx, o.t + .05 + i * .1, o.cz + zc], ao: o.t, line: .008 });
  const n = 8;
  const col = lathe([[.06, 0], [.06, .05], [.045, .08], [.04, colH * .9], [.05, colH * .93], [.065, colH]], 12);
  for (let i = 0; i < n; i++) {
    const a = i / n * 6.28 + .2, x = Math.cos(a) * r, z = Math.sin(a) * r;
    bake(col, P.trim, { p: [o.cx + x, o.t + y0, o.cz + zc + z], line: .006 });
    bake(box(.15, .05, .15), P.trim, { p: [o.cx + x, o.t + y0 + colH + .02, o.cz + zc + z], line: .005 });
  }
  bake(cyl(r + .12, r + .12, .16, 24), wall, { p: [o.cx, o.t + y0 + colH + .12, o.cz + zc], line: .01 });
  bake(torus(r + .13, .03, 5, 32), P.trim, { p: [o.cx, o.t + y0 + colH + .2, o.cz + zc], r: [Math.PI / 2, 0, 0], line: .005 });
  bake(ball(r + .05, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), dome, { p: [o.cx, o.t + y0 + colH + .2, o.cz + zc], s: [1, 1.15, 1], line: .012 });
  for (let i = 0; i < 8; i++) bake(torus(r + .055, .012, 4, 24, Math.PI / 2), domeD, { p: [o.cx, o.t + y0 + colH + .2, o.cz + zc], r: [0, i / 8 * 6.28, Math.PI / 2], s: [1, 1.15, 1], line: 0 });
  bake(cyl(.12, .16, .2, 12), P.trim, { p: [o.cx, o.t + y0 + colH + .2 + (r + .05) * 1.15 + .05, o.cz + zc], line: .006 });
  finial((g, c, opt) => bake(g, c, { ...opt, p: [o.cx + opt.p[0], o.t + opt.p[1], o.cz + opt.p[2]] }), 0, y0 + colH + .35 + (r + .05) * 1.15, zc, 1.6);
  // 中间一个小水盆
  bake(lathe([[0, 0], [.08, 0], [.05, .2], [.08, .3], [.3, .38], [.32, .42], [0, .42]], 16), P.stone, { p: [o.cx, o.t + y0, o.cz + zc], line: .008 });
  bake(cyl(.28, .28, .02, 16), '#a9cbd8', { p: [o.cx, o.t + y0 + .41, o.cz + zc], line: 0 });
}

// ———————— 铁艺小物 ————————
export function gasLamp(o) {
  const put = (geo, c, opt = {}) => bake(geo, c, { ...opt, ao: o.t, p: [o.cx + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + (opt.p?.[2] ?? 0)] });
  put(lathe([[.13, 0], [.13, .05], [.09, .08], [.09, .14], [.06, .2], [.045, .26], [0, .26]], 12), IRON, { line: .006 });
  put(cyl(.032, .04, 1.05, 10), IRON, { p: [0, .78, 0] });
  for (let k = 0; k < 6; k++) { const a = k / 6 * 6.28; put(box(.008, .9, .008), '#4c4649', { p: [Math.cos(a) * .036, .72, Math.sin(a) * .036], line: 0 }); }
  for (const y of [.35, 1.18]) put(torus(.05, .012, 4, 12), GOLD, { p: [0, y, 0], r: [Math.PI / 2, 0, 0], line: 0 });
  for (const sx of [-1, 1]) put(torus(.07, .01, 4, 12, Math.PI * 1.2), IRON, { p: [sx * .07, 1.22, 0], r: [0, 0, sx > 0 ? -.2 : Math.PI + .2], line: .004 });   // 两边小卷花
  put(box(.22, .03, .22), IRON, { p: [0, 1.32, 0], line: .005 });
  for (const [x, z] of [[-.09, -.09], [.09, -.09], [-.09, .09], [.09, .09]]) put(box(.018, .26, .018), IRON, { p: [x, 1.46, z], line: .004 });
  put(lathe([[.07, 0], [.095, .12], [.095, .2], [.06, .26], [0, .26]], 8), P.lamp, { p: [0, 1.33, 0], line: 0 });
  put(cone(.17, .14, 8), IRON, { p: [0, 1.66, 0], line: .006 });
  put(lathe([[.03, 0], [.03, .03], [.015, .05], [.025, .08], [0, .14]], 8), GOLD, { p: [0, 1.73, 0], line: .004 });
}
export function ironFence(o, w) {
  const put = (geo, c, opt = {}) => bake(geo, c, { ...opt, ao: o.t, p: [o.cx + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + .3 + (opt.p?.[2] ?? 0)] });
  for (const sx of [-1, 1]) {   // 两头石柱，柱顶一个圆球
    put(box(.16, .5, .16), P.stone, { p: [sx * (w / 2 - .08), .25, 0], line: .008 });
    put(box(.2, .04, .2), P.trim, { p: [sx * (w / 2 - .08), .52, 0], line: .005 });
    put(ball(.06, 10, 8), P.stone, { p: [sx * (w / 2 - .08), .6, 0], line: .005 });
  }
  put(box(w - .3, .06, .1), P.stone, { p: [0, .03, 0], line: .006 });
  for (const y of [.12, .38]) put(box(w - .3, .02, .02), IRON, { p: [0, y, 0], line: .004 });
  const n = Math.round((w - .3) / .08);
  for (let i = 0; i <= n; i++) {
    const x = -(w - .3) / 2 + i * (w - .3) / n;
    put(cyl(.008, .008, .42, 5), IRON, { p: [x, .27, 0], line: 0 });
    put(cone(.018, .05, 4), i % 3 === 0 ? GOLD : IRON, { p: [x, .5, 0], line: 0 });
    if (i < n && i % 2 === 0) put(torus(.025, .006, 4, 10), IRON, { p: [x + (w - .3) / n / 2, .25, 0], line: 0 });
  }
}
export function ironBench(o, w) {
  const put = (geo, c, opt = {}) => bake(geo, c, { ...opt, ao: o.t, p: [o.cx + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + (opt.p?.[2] ?? 0)] });
  const L = w * .82;
  for (let i = 0; i < 5; i++) put(box(L, .025, .06, .008), jit(P.woodL, .03), { p: [0, .27, -.14 + i * .07] });
  for (let i = 0; i < 4; i++) put(box(L, .05, .02, .008), jit(P.woodL, .03), { p: [0, .37 + i * .07, -.2 - i * .015], r: [-.2, 0, 0] });
  for (const sx of [-1, 1]) {   // 铁艺扶手：一个大卷、一个小卷
    const x = sx * L * .45;
    put(torus(.12, .014, 4, 16, Math.PI * 1.5), IRON, { p: [x, .3, .02], r: [0, Math.PI / 2, 0], line: .004 });
    put(torus(.06, .012, 4, 12, Math.PI * 1.6), IRON, { p: [x, .13, .1], r: [0, Math.PI / 2, 0], line: .004 });
    put(box(.025, .27, .025), IRON, { p: [x, .13, -.15], line: .004 });
    put(box(.025, .6, .025), IRON, { p: [x, .3, -.2], r: [-.2, 0, 0], line: .004 });
  }
}
