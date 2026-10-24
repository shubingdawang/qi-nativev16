// 白蔷薇石塔庄园（照参考图）：深灰石块墙、米色方石窗套和隅石、很陡的尖山墙配黑色封檐板、
// 琥珀色亮着的尖拱窗、右边圆塔和锥形石板瓦顶、高高的成组烟囱、屋脊黑铁尖饰，墙上爬满白蔷薇和紫藤。
import * as THREE from 'three';
import { bake, R, box, cyl, cone, ball, torus, blob, lathe, tri3 } from './kit.js';

const C = { cream: '#f4ecdb', black: '#3a3f4a', iron: '#1a1d22', wood: '#8a5232', woodD: '#6a3c22', glow: '#c98a3a', rose: '#f6f3ee', roseS: '#e6e0d6', leaf: '#3f5a3a', wis: '#b7a6d6', wisD: '#9a88c2', pot: '#b9714f' };
function maker(o) {
  const O = new THREE.Matrix4().makeTranslation(o.cx, o.t, o.cz);
  return (geo, color, opt = {}) => bake(geo, color, { ...opt, matrix: opt.m ? O.clone().multiply(opt.m) : O, ao: null });
}
const M = (x, y, z, ry = 0) => new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z);
const archShape = (w, h) => { const s = new THREE.Shape(), hs = h - w * .85; s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, hs); s.quadraticCurveTo(w / 2, hs + w * .55, 0, h); s.quadraticCurveTo(-w / 2, hs + w * .55, -w / 2, hs); s.closePath(); return s; };
// 尖拱在横坐标 x 处有多高（跟 archShape 那两段二次曲线一样算）
function archTop(w, h, x) {
  const hs = h - w * .85, t = Math.sqrt(Math.max(0, 1 - Math.abs(x) / (w / 2)));
  return (1 - t) * (1 - t) * hs + 2 * (1 - t) * t * (hs + w * .55) + t * t * h;
}
function slab(shape, depth, hole) { if (hole) shape.holes.push(hole); const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 10 }); g.translate(0, 0, -depth / 2); return g; }

// 一扇尖拱窗：米色石窗套（外面一圈一块块的拱石）、琥珀色亮着的玻璃、黑色铅条窗棂、石窗台
function lancet(put, m, w, h, { twin = false } = {}) {
  put(slab(archShape(w + .12, h + .08), .07, archShape(w, h)), C.cream, { m, p: [0, -.04, .03], mat: 'ashlar' });
  const n = 9;
  for (let i = 0; i < n; i++) {   // 拱石
    const t = i / (n - 1), a = Math.PI * (1 - t);
    const x = Math.cos(a) * (w / 2 + .08), y = (h - w * .85) + Math.sin(a) * (w * .85 + .05) * (1 - Math.abs(Math.cos(a)) * .15);
    put(box(.06, .07, .08), C.cream, { m, p: [x, y, .035], r: [0, 0, a - Math.PI / 2], mat: 'ashlar' });
  }
  put(slab(archShape(w, h), .015), C.glow, { m, p: [0, 0, -.01], mat: 'glow' });
  // 铅条：竖条顶到拱边，横条只在直的那一段，拱里一个小圆
  const cols = twin ? 3 : 2;
  for (let c = 1; c < cols; c++) { const x = -w / 2 + c * w / cols, top = archTop(w, h, x) - .004; put(box(.012, top, .016), C.black, { m, p: [x, top / 2, .002] }); }
  const hs = h - w * .85;
  for (let r2 = 1; r2 < 4; r2++) put(box(w - .004, .01, .016), C.black, { m, p: [0, r2 * hs / 4, .002] });
  put(box(w - .004, .012, .016), C.black, { m, p: [0, hs, .002] });
  const rr = Math.min(w * .17, (h - hs) * .28);
  if (!twin) put(torus(rr, .007, 4, 16), C.black, { m, p: [0, hs + (h - hs) * .42, .002] });
  put(box(w + .18, .05, .1), C.cream, { m, p: [0, -.05, .05], mat: 'ashlar' });
  for (const sx of [-1, 1]) put(box(.05, .05, .07), C.cream, { m, p: [sx * (w / 2 + .05), -.1, .04], mat: 'ashlar' });
}
// 一簇白蔷薇：深绿的叶团打底，上面一朵朵玫瑰（中间一个卷心、外面五片杯状的花瓣），叶子是尖尖的小片
function rose(put, x, y, z, s) {
  const c = R() < .7 ? C.rose : C.roseS;
  put(ball(.016 * s, 8, 6), '#efe6d6', { p: [x, y + .006 * s, z + .01 * s] });
  for (let k = 0; k < 5; k++) {
    const a = k / 5 * Math.PI * 2 + R();
    put(ball(.02 * s, 8, 6), c, { p: [x + Math.cos(a) * .017 * s, y + Math.sin(a) * .017 * s, z], r: [Math.sin(a) * .6, -Math.cos(a) * .6, 0], s: [1, 1, .45] });
  }
  for (let k = 0; k < 3; k++) {
    const a = k / 3 * Math.PI * 2 + .5;
    put(ball(.026 * s, 8, 6), c, { p: [x + Math.cos(a) * .028 * s, y + Math.sin(a) * .028 * s, z - .008 * s], r: [Math.sin(a) * .9, -Math.cos(a) * .9, 0], s: [1, 1, .35] });
  }
}
function leaf(put, x, y, z, s, a) {
  put(cone(.018 * s, .06 * s, 4), C.leaf, { p: [x, y, z], r: [0, 0, a], s: [1.4, 1, .25] });
}
function roses(put, x, y, z, s = 1, n = 18) {
  for (let i = 0; i < Math.round(n * .3); i++) put(blob(.05 * s, 1, .7), '#344c31', { p: [x + (R() - .5) * .28 * s, y + (R() - .5) * .28 * s, z - .02] });
  for (let i = 0; i < n * 1.4; i++) leaf(put, x + (R() - .5) * .36 * s, y + (R() - .5) * .36 * s, z + .02 + R() * .03 * s, s, R() * 6.28);
  for (let i = 0; i < Math.round(n * .55); i++) rose(put, x + (R() - .5) * .32 * s, y + (R() - .5) * .32 * s, z + .05 + R() * .03 * s, s * (.85 + R() * .4));
}
// 一串紫藤：从上往下越来越细的一串
function wisteria(put, x, y, z, len = .4) {
  for (let k = 0; k < 7; k++) { const t = k / 6; put(ball(.035 * (1 - t * .7), 8, 6), k % 2 ? C.wis : C.wisD, { p: [x + (R() - .5) * .02, y - t * len, z], s: [1, 1.3, 1] }); }
}

export function roseManor(o, d) {
  const put = maker(o);
  const fz = .3, Dp = 2.4, base = .22, H1 = 1.0, H2 = .95, top = base + H1 + H2, W = 3.6, x0 = -W / 2, x1 = W / 2;
  // 墙身：深灰石块
  put(box(W + .1, base, Dp + .1), C.cream, { p: [0, base / 2, fz - Dp / 2], mat: 'ashlar' });
  put(box(W, H1 + H2, Dp), '#ffffff', { p: [0, base + (H1 + H2) / 2, fz - Dp / 2], mat: 'darkstone' });
  for (const sx of [-1, 1]) for (let k = 0; k < 12; k++) put(box(k % 2 ? .22 : .14, .15, .04), C.cream, { p: [sx * (W / 2 - (k % 2 ? .11 : .07)), base + .08 + k * .162, fz + .01], mat: 'ashlar' });
  put(box(W + .06, .06, Dp + .06), C.cream, { p: [0, base + H1, fz - Dp / 2], mat: 'ashlar' });
  // 中间往前凸的门楼：尖山墙，尖拱大门（几圈石拱）、双开木门、上面的尖拱窗配小石阳台
  const gx = -.25, gw = 1.25, gz = fz + .35;
  put(box(gw, top, .4), '#ffffff', { p: [gx, top / 2, fz + .15], mat: 'darkstone' });
  for (let i = 0; i < 3; i++) put(slab(archShape(.72 - i * .08, 1.0 - i * .06), .06, archShape(.66 - i * .08, .95 - i * .06)), C.cream, { p: [gx, base, gz + .1 - i * .03], mat: 'ashlar' });
  put(slab(archShape(.5, .84), .04), C.wood, { p: [gx, base, gz + .01] });
  // 门：中缝从门底通到拱顶，每扇门三道黑铁合页（一头尖的长条，上面三颗钉）
  put(box(.008, .84, .012), C.woodD, { p: [gx, base + .42, gz + .032] });
  for (const sx of [-1, 1]) for (const y of [.12, .38, .6]) {
    const len = Math.min(.2, Math.abs(archTop(.5, .84, sx * .2) - y) > 0 ? .2 : .2);
    put(box(len, .028, .008), C.black, { p: [gx + sx * (.25 - len / 2 - .01), base + y, gz + .035] });
    put(cone(.02, .04, 4), C.black, { p: [gx + sx * (.25 - len - .02), base + y, gz + .035], r: [0, 0, sx * Math.PI / 2], s: [1, 1, .3] });
    for (let k = 0; k < 3; k++) put(ball(.007, 6, 4), '#5a5a60', { p: [gx + sx * (.22 - k * .06), base + y, gz + .04] });
  }
  for (const sx of [-1, 1]) put(torus(.025, .006, 4, 12), C.black, { p: [gx + sx * .05, base + .4, gz + .038] });
  put(slab(archShape(.4, .3), .012), C.glow, { p: [gx, base + .55, gz + .032], mat: 'glow' });
  for (const sx of [-1, 1]) {   // 门边一对铁灯笼、一对石盆
    put(box(.07, .12, .07), C.glow, { p: [gx + sx * .52, base + .7, gz + .02], mat: 'glow' });
    put(cone(.07, .08, 4), C.iron, { p: [gx + sx * .52, base + .8, gz + .02], r: [0, Math.PI / 4, 0], mat: 'iron' });
    put(box(.02, .1, .05), C.iron, { p: [gx + sx * .52, base + .6, gz - .01], mat: 'iron' });
    put(lathe([[0, 0], [.08, 0], [.06, .04], [.11, .16], [.12, .18], [0, .18]], 12), C.cream, { p: [gx + sx * .62, 0, gz + .45] });
    roses(put, gx + sx * .62, .28, gz + .45, .8, 10);
  }
  for (let i = 0; i < 4; i++) put(box(.9 + i * .1, .055, .14), C.cream, { p: [gx, base - .03 - i * .055, gz + .1 + i * .13], mat: 'ashlar' });
  lancet(put, M(gx, base + H1 + .12, gz + .01), .34, .62, { twin: true });
  put(box(.6, .05, .2), C.cream, { p: [gx, base + H1 + .05, gz + .1], mat: 'ashlar' });
  for (let k = 0; k < 7; k++) put(box(.025, .14, .025), C.cream, { p: [gx - .25 + k * .083, base + H1 + .14, gz + .17] });
  put(box(.62, .03, .05), C.cream, { p: [gx, base + H1 + .22, gz + .17] });
  // 门楼的尖山墙：石头三角，黑色封檐板（两道），尖上一根铁尖饰
  const gh = 1.25;
  put(tri3([gx - gw / 2, top, gz - .05], [gx + gw / 2, top, gz - .05], [gx, top + gh, gz - .05]), '#ffffff', { mat: 'darkstone' });
  const L = Math.hypot(gw / 2 + .1, gh + .08), ang = Math.atan2(gh, gw / 2);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationZ(-s * ang).setPosition(gx + s * gw / 4, top + gh / 2 + .02, gz - .5);
    put(box(L, .06, 1.0), '#ffffff', { m, mat: 'slate' });
    put(box(L + .02, .1, .04), C.black, { m, p: [0, -.02, .5] });
    put(box(L - .3, .04, .03), C.black, { m, p: [0, -.12, .48] });
    for (let k = 1; k < 6; k++) put(torus(.05, .01, 4, 12, Math.PI), C.black, { m, p: [-L / 2 + k * L / 6, -.1, .49], r: [0, 0, Math.PI] });
  }
  lancet(put, M(gx, top + .25, gz - .04), .22, .48);
  ironFinial(put, gx, top + gh + .02, gz - .05, 1.6);
  // 左边：一座更高的尖山墙 + 黑色木框的凸窗（两层）
  const lx = -1.25;
  put(tri3([lx - .5, top, fz + .01], [lx + .5, top, fz + .01], [lx, top + 1.1, fz + .01]), '#ffffff', { mat: 'darkstone' });
  for (const s of [-1, 1]) {
    const L2 = Math.hypot(.6, 1.15), a2 = Math.atan2(1.1, .5);
    const m = new THREE.Matrix4().makeRotationZ(-s * a2).setPosition(lx + s * .25, top + .55, fz - .4);
    put(box(L2, .06, .9), '#ffffff', { m, mat: 'slate' });
    put(box(L2 + .02, .1, .04), C.black, { m, p: [0, -.02, .45] });
  }
  ironFinial(put, lx, top + 1.12, fz, 1.3);
  lancet(put, M(lx, top + .2, fz + .02), .2, .45);
  for (const fl of [0, 1]) {   // 黑框凸窗：三面玻璃
    const y = base + .15 + fl * H1, bw = .62, bd = .22;
    put(box(bw + .1, .06, bd + .05), C.black, { p: [lx, y - .04, fz + bd / 2] });
    put(box(bw + .12, .08, bd + .07), C.black, { p: [lx, y + .72, fz + bd / 2] });
    for (const [x, z, ry, w] of [[lx, fz + bd, 0, bw], [lx - bw / 2, fz + bd / 2, Math.PI / 2, bd], [lx + bw / 2, fz + bd / 2, Math.PI / 2, bd]]) {
      put(box(w, .7, .01), C.glow, { p: [x, y + .34, z], r: [0, ry, 0], mat: 'glow' });
      for (let k = 0; k <= 3; k++) put(box(.02, .7, .02), C.black, { p: [x + (ry ? 0 : -w / 2 + k * w / 3), y + .34, z + (ry ? -w / 2 + k * w / 3 : .005)], r: [0, ry, 0] });
      put(box(w, .02, .02), C.black, { p: [x, y + .5, z + (ry ? 0 : .006)], r: [0, ry, 0] });
    }
    if (fl === 1) put(cone(.42, .25, 4), '#ffffff', { p: [lx, y + .9, fz + bd / 2], r: [0, Math.PI / 4, 0], s: [1, 1, .5], mat: 'slate' });
  }
  // 右半边一楼、二楼的尖拱窗
  for (const x of [.75]) for (const fl of [0, 1]) lancet(put, M(x, base + .2 + fl * H1, fz + .005), .24, .6);
  // 主屋顶：很陡，石板瓦，屋脊黑铁尖饰一排
  const rh = 1.35, half = Dp / 2 + .12, slope = Math.hypot(half, rh), rang = Math.atan2(rh, half), zc = fz - Dp / 2;
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(s * rang).setPosition(0, top + rh / 2, zc + s * half / 2);
    put(box(W + .2, .06, slope), '#ffffff', { m, mat: 'slate' });
  }
  for (const sx of [-1, 1]) put(tri3([sx * W / 2, top, zc - Dp / 2], [sx * W / 2, top, zc + Dp / 2], [sx * W / 2, top + rh, zc]), '#ffffff', { mat: 'darkstone' });
  put(box(W + .25, .05, .06), C.black, { p: [0, top + rh + .02, zc] });
  for (let x = x0; x <= x1 + .01; x += .12) { put(box(.01, .12, .01), C.iron, { p: [x, top + rh + .08, zc], mat: 'iron' }); put(cone(.012, .05, 4), C.iron, { p: [x, top + rh + .16, zc], mat: 'iron' }); }
  for (const x of [x0 + .1, x1 - .1]) ironFinial(put, x, top + rh, zc, 1.4);
  // 成组的高烟囱：深灰石身、米色石线、陶土烟囱帽
  for (const [x, z] of [[-.65, zc - .2], [.55, zc + .1]]) {
    put(box(.42, 1.6, .3), '#ffffff', { p: [x, top + .8, z], mat: 'darkstone' });
    for (const y of [top + 1.1, top + 1.58]) put(box(.48, .07, .36), C.cream, { p: [x, y, z], mat: 'ashlar' });
    for (const dx of [-.1, .1]) { put(cyl(.05, .055, .2, 10), C.pot, { p: [x + dx, top + 1.72, z] }); put(cyl(.06, .06, .03, 10), C.pot, { p: [x + dx, top + 1.83, z] }); }
  }
  // 右边圆塔：深灰石，米色石带，顶上一圈托石挑出、一圈尖拱小窗，锥形石板瓦顶上两扇小老虎窗
  const tx = 1.55, tz = fz - .35, tr = .62, tH = top + .6;
  put(cyl(tr, tr + .03, tH, 20), '#ffffff', { p: [tx, tH / 2, tz], mat: 'darkstone' });
  for (const y of [base + H1, top - .05]) put(cyl(tr + .03, tr + .03, .06, 20), C.cream, { p: [tx, y, tz], mat: 'ashlar' });
  for (let k = 0; k < 20; k++) { const a = k / 20 * Math.PI * 2; put(box(.07, .1, .08), C.cream, { p: [tx + Math.cos(a) * (tr + .04), tH - .05, tz + Math.sin(a) * (tr + .04)], r: [0, -a, 0], mat: 'ashlar' }); }
  put(cyl(tr + .1, tr + .08, .1, 20), C.cream, { p: [tx, tH + .04, tz], mat: 'ashlar' });
  for (const a of [Math.PI / 2 - .5, Math.PI / 2, Math.PI / 2 + .5]) {
    lancet(put, M(tx + Math.cos(a) * (tr + .03), base + .25, tz + Math.sin(a) * (tr + .03), Math.PI / 2 - a), .18, .48);
    lancet(put, M(tx + Math.cos(a) * (tr + .03), top + .05, tz + Math.sin(a) * (tr + .03), Math.PI / 2 - a), .14, .34);
  }
  put(cone(tr + .2, 2.0, 24), '#ffffff', { p: [tx, tH + 1.09, tz], mat: 'slate' });
  for (const a of [Math.PI / 2 - .6, Math.PI / 2 + .6]) {
    const dx = tx + Math.cos(a) * .45, dz = tz + Math.sin(a) * .45, y = tH + .55;
    put(box(.16, .26, .2), '#ffffff', { p: [dx, y, dz], r: [0, Math.PI / 2 - a, 0], mat: 'darkstone' });
    put(cone(.14, .2, 4), '#ffffff', { p: [dx, y + .22, dz], r: [0, Math.PI / 2 - a + Math.PI / 4, 0], mat: 'slate' });
    put(box(.08, .14, .01), C.glow, { p: [dx + Math.cos(a) * .1, y, dz + Math.sin(a) * .1], r: [0, Math.PI / 2 - a, 0], mat: 'glow' });
  }
  ironFinial(put, tx, tH + 2.08, tz, 1.8);
  // 白蔷薇沿着立面爬，紫藤从塔边、门楼边垂下来
  for (const [x, y, s] of [[-.95, .35, 1.4], [-1.7, .3, 1.2], [.35, .35, 1.3], [.95, .9, 1.1], [-.9, 1.4, 1], [gx + .62, 1.6, .9], [1.1, .3, 1.4], [-1.55, 1.6, .9]]) roses(put, x, y, fz + .02 + (x > 1 ? .2 : 0), s, 14);
  for (const [x, y, z] of [[1.0, 1.9, fz + .1], [1.12, 1.7, fz + .15], [.92, 1.6, fz + .12], [gx - .66, 2.2, gz], [gx - .6, 2.0, gz + .02], [-1.9, 1.8, fz + .02]]) for (let k = 0; k < 3; k++) wisteria(put, x + k * .05, y + (R() - .5) * .1, z, .3 + R() * .2);
  for (const x of [-1.75, -1.2, -.7, .3, .8, 1.3, 2.0]) roses(put, x, .18, fz + .25 + (x > 1 ? .3 : 0), 1.3, 16);   // 墙脚一溜白蔷薇丛
}

function ironFinial(put, x, y, z, s = 1) {
  put(cyl(.008 * s, .008 * s, .36 * s, 5), C.iron, { p: [x, y + .18 * s, z], mat: 'iron' });
  put(ball(.022 * s, 8, 6), C.iron, { p: [x, y + .14 * s, z], mat: 'iron' });
  for (const sx of [-1, 1]) put(torus(.035 * s, .006 * s, 4, 10, Math.PI * 1.3), C.iron, { p: [x + sx * .035 * s, y + .3 * s, z], r: [0, 0, sx > 0 ? -.4 : Math.PI + .4], mat: 'iron' });
  put(cone(.015 * s, .12 * s, 5), C.iron, { p: [x, y + .42 * s, z], mat: 'iron' });
}
