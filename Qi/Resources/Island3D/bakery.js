// 甜品屋（厨房那栋，照她给的第三张参考）：奶油色灰泥墙、陶土筒瓦和蓝色筒瓦、荷兰式弧形山墙、
// 屋檐上淌下来的糖霜、条纹雨棚配波浪边、圆窗和拱窗、花箱、墙上一块大饼干、橱窗里摆着蛋糕、
// 门口的小黑板、面包筐、圆牌路灯。
import * as THREE from 'three';
import { bake, R, box, cyl, cone, ball, torus, blob, lathe } from './kit.js';

const C = {
  wall: '#f7eee3', wall2: '#eef3f6', trim: '#fffaf3', terra: '#d88a68', terraD: '#c57656', blue: '#9ec3dd', blueD: '#86aecb',
  wood: '#b98060', woodD: '#9b6648', glass: '#9fbdd0', frost: '#f9fbff', frostB: '#c9e0f0', cookie: '#d9a46c', choco: '#6e4433',
  stripe: '#f4c7a7', stripeB: '#a9cbe3', leaf: '#7fa36b', flower: ['#f3a7b5', '#ffffff', '#f6d27a', '#c9b3e6'], iron: '#5a5f68', pink: '#f3b4c0',
};
function maker(o) {
  const O = new THREE.Matrix4().makeTranslation(o.cx, o.t, o.cz);
  return (geo, color, opt = {}) => bake(geo, color, { ...opt, matrix: opt.m ? O.clone().multiply(opt.m) : O, ao: null });
}
const M = (x, y, z, ry = 0) => new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z);
const rb = (w, h, d, r) => box(w, h, d, r, 3);

// 一面坡的筒瓦：一行行半圆瓦，下一行压着上一行；ang 是坡度，facing +z
function barrelRoof(put, cx, y, z, w, len, ang, col, colD, side = 1) {
  const m = new THREE.Matrix4().makeRotationX(side * ang).setPosition(cx, y, z);
  put(rb(w + .1, .05, len + .06, .02), colD, { m });
  const rows = Math.round(len / .11), n = Math.round(w / .1);
  for (let i = 0; i < rows; i++) for (let k = 0; k < n; k++) {
    const g = new THREE.CylinderGeometry(.05, .055, .13, 8, 1, true, 0, Math.PI); g.rotateZ(Math.PI / 2); g.rotateY(Math.PI / 2);
    put(g, (i + k) % 3 ? col : colD, { m, p: [-w / 2 + (k + .5) * w / n, .03, side * (-len / 2 + (i + .5) * len / rows)], r: [-side * .08, 0, 0] });
  }
  return m;
}
// 窗：圆角木框、浅蓝玻璃、十字窗棂、白窗台、下面一个花箱
function win(put, m, w, h, { arch = false, box: fb = true } = {}) {
  put(rb(w + .08, h + .08, .05, .02), C.wood, { m, p: [0, h / 2, .01] });
  put(box(w, h, .02), C.glass, { m, p: [0, h / 2, .03], mat: 'glass' });
  if (arch) { put(new THREE.CircleGeometry(w / 2 + .04, 18, 0, Math.PI), C.wood, { m, p: [0, h + .0, .01] }); put(new THREE.CircleGeometry(w / 2, 18, 0, Math.PI), C.glass, { m, p: [0, h, .036], mat: 'glass' }); }
  put(box(.02, h, .03), C.woodD, { m, p: [0, h / 2, .04] }); put(box(w, .02, .03), C.woodD, { m, p: [0, h * .55, .04] });
  put(rb(w + .14, .035, .08, .012), C.trim, { m, p: [0, -.02, .05] });
  if (!fb) return;
  put(rb(w + .06, .08, .1, .02), C.woodD, { m, p: [0, -.08, .08] });
  for (let k = 0; k < 6; k++) {
    put(blob(.035, 1, .8), C.leaf, { m, p: [-w / 2 + .03 + k * (w / 5.5), -.03, .1] });
    put(ball(.022, 8, 6), C.flower[k % 4], { m, p: [-w / 2 + .03 + k * (w / 5.5), .0, .12] });
  }
  for (let k = 0; k < 3; k++) put(blob(.025, 1, 1.6), C.leaf, { m, p: [-w / 3 + k * w / 3, -.15, .12] });   // 垂下来的藤
}
// 条纹雨棚：一条条交替的颜色，下边一排半圆的波浪边
function awning(put, x, y, z, w, d, colA, colB) {
  const m = new THREE.Matrix4().makeRotationX(.5).setPosition(x, y, z);
  const n = Math.max(4, Math.round(w / .1));
  for (let i = 0; i < n; i++) {
    put(rb(w / n + .002, .025, d, .008), i % 2 ? colB : colA, { m, p: [-w / 2 + (i + .5) * w / n, 0, 0] });
    put(new THREE.CircleGeometry(w / n / 2, 10, Math.PI, Math.PI), i % 2 ? colB : colA, { m: m.clone().multiply(new THREE.Matrix4().makeRotationX(-.5)), p: [-w / 2 + (i + .5) * w / n, -.01, d / 2 * Math.cos(.5) + .01] });
  }
  put(cyl(.012, .012, w + .04, 8), C.iron, { m, p: [0, .01, -d / 2], r: [0, 0, Math.PI / 2] });
}
// 屋檐上淌下来的糖霜：一条厚边，下面挂着一滴一滴
function frosting(put, x, y, z, w, col) {
  put(rb(w, .07, .1, .03), col, { p: [x, y, z] });
  for (let i = 0; i < Math.round(w / .09); i++) {
    const px = x - w / 2 + .05 + i * .09 + (R() - .5) * .02, l = .05 + R() * .12;
    put(new THREE.CapsuleGeometry(.025, l, 4, 10), col, { p: [px, y - .03 - l / 2, z + .03] });
  }
}
// 一块饼干：圆圆的饼干、边缘一圈烤得深一点、上面几粒巧克力豆
function cookie(put, m, r) {
  put(cyl(r, r, .04, 28), C.cookie, { m, r: [Math.PI / 2, 0, 0] });
  put(torus(r, .012, 6, 28), '#c48a52', { m, p: [0, 0, .0] });
  for (let i = 0; i < 7; i++) { const a = i * 2.4, d = r * (.25 + (i % 3) * .22); put(ball(.025, 8, 6), C.choco, { m, p: [Math.cos(a) * d, Math.sin(a) * d, .02], s: [1, 1, .5] }); }
}
// 一块小蛋糕：两层海绵、奶油边、顶上一颗草莓
function cake(put, x, y, z, s = 1, col = C.pink) {
  put(cyl(.06 * s, .06 * s, .05 * s, 16), '#f2d6a8', { p: [x, y + .025 * s, z] });
  put(cyl(.062 * s, .062 * s, .015 * s, 16), col, { p: [x, y + .057 * s, z] });
  for (let k = 0; k < 8; k++) { const a = k / 8 * 6.28; put(ball(.012 * s, 6, 4), C.frost, { p: [x + Math.cos(a) * .05 * s, y + .068 * s, z + Math.sin(a) * .05 * s] }); }
  put(ball(.016 * s, 8, 6), '#e0565f', { p: [x, y + .08 * s, z] });
}

export function bakery(o, d) {
  const put = maker(o);
  const fz = .35;
  // 地台：一块圆角的石子地，外面一圈深一点的石边
  put(cyl(2.1, 2.15, .06, 40), '#e6dccf', { p: [0, .03, -.6], s: [1, 1, .8] });
  for (let i = 0; i < 70; i++) { const a = R() * 6.28, rr = Math.sqrt(R()) * 1.9; put(cyl(.06 + R() * .04, .07, .015, 7), R() < .5 ? '#d7cbbb' : '#efe6da', { p: [Math.cos(a) * rr, .065, -.6 + Math.sin(a) * rr * .8] }); }
  // 主楼：两层，奶油色墙，转角圆圆的
  const mw = 2.1, md = 1.7, mx = -.35, mz = fz - md / 2, h1 = 1.0, h2 = .9;
  put(rb(mw, h1 + h2, md, .05), C.wall, { p: [mx, (h1 + h2) / 2 + .06, mz] });
  put(rb(mw + .06, .06, md + .06, .02), C.trim, { p: [mx, h1 + .06, mz] });
  // 荷兰式弧形山墙：前面一块弧顶的墙，边上一圈白线脚，顶上一个小圆窗
  const gs = new THREE.Shape(); const gw = mw * .78, gy0 = h1 + h2 + .06;
  gs.moveTo(-gw / 2, 0); gs.lineTo(-gw / 2, .2); gs.quadraticCurveTo(-gw / 2, .5, -gw / 4, .55); gs.quadraticCurveTo(-gw / 6, .9, 0, .92); gs.quadraticCurveTo(gw / 6, .9, gw / 4, .55); gs.quadraticCurveTo(gw / 2, .5, gw / 2, .2); gs.lineTo(gw / 2, 0); gs.closePath();
  const gg = new THREE.ExtrudeGeometry(gs, { depth: .14, bevelEnabled: true, bevelSize: .025, bevelThickness: .02, bevelSegments: 3, curveSegments: 16 });
  put(gg, C.wall, { p: [mx, gy0, fz - .14] });
  put(torus(.13, .03, 8, 20), C.wood, { p: [mx, gy0 + .55, fz + .03] });
  put(new THREE.CircleGeometry(.12, 20), C.glass, { p: [mx, gy0 + .55, fz + .02], mat: 'glass' });
  for (let k = 0; k < 4; k++) put(box(.24, .015, .02), C.woodD, { p: [mx, gy0 + .55, fz + .035], r: [0, 0, k * Math.PI / 4] });
  // 主楼屋顶：陶土筒瓦两坡，屋脊一排脊瓦；檐口淌着白糖霜
  const rh = .55, half = md / 2 + .1, ang = Math.atan2(rh, half), sl = Math.hypot(half, rh);
  for (const s of [-1, 1]) barrelRoof(put, mx, gy0 + rh / 2 - .02, mz + s * half / 2, mw + .14, sl, ang, C.terra, C.terraD, s);
  put(cyl(.06, .06, mw + .2, 10), C.terraD, { p: [mx, gy0 + rh + .01, mz], r: [0, 0, Math.PI / 2] });
  frosting(put, mx - mw * .3, gy0 - .02, fz + .02, mw * .38, C.frost);
  frosting(put, mx + mw * .3, gy0 - .02, fz + .02, mw * .38, C.frost);
  // 一楼：大橱窗（里面三层架子摆蛋糕）、木门（上半截玻璃）、橱窗上条纹雨棚
  const sw = .95, sx0 = mx - .45;
  put(rb(sw + .1, .7, .06, .02), C.wood, { p: [sx0, .45, fz + .01] });
  put(box(sw, .6, .02), C.glass, { p: [sx0, .45, fz + .04], mat: 'glass' });
  for (let k = 1; k < 3; k++) put(box(.02, .6, .03), C.woodD, { p: [sx0 - sw / 2 + k * sw / 3, .45, fz + .05] });
  for (const [y, n] of [[.2, 4], [.42, 3]]) { put(box(sw - .06, .015, .2), C.trim, { p: [sx0, y, fz - .08] }); for (let k = 0; k < n; k++) cake(put, sx0 - (n - 1) * .12 + k * .24, y + .008, fz - .08, 1, [C.pink, '#f6e7c1', '#c9b3e6', '#f3b4c0'][k]); }
  put(rb(sw + .16, .06, .14, .02), C.woodD, { p: [sx0, .1, fz + .06] });
  put(rb(.8, .12, .05, .03), C.trim, { p: [sx0, .88, fz + .04] });   // 招牌底板
  for (let k = 0; k < 5; k++) put(ball(.03, 8, 6), [C.pink, C.stripeB, '#f6d27a', C.pink, C.stripeB][k], { p: [sx0 - .2 + k * .1, .88, fz + .07], s: [1, 1, .4] });
  awning(put, sx0, .98, fz + .2, sw + .2, .42, C.stripe, C.trim);
  const dx = mx + .62;
  put(rb(.44, .8, .06, .03), C.woodD, { p: [dx, .46, fz + .01] });
  put(rb(.38, .74, .05, .02), C.wood, { p: [dx, .44, fz + .03] });
  put(box(.28, .3, .02), C.glass, { p: [dx, .6, fz + .06], mat: 'glass' });
  put(rb(.28, .22, .02, .01), C.woodD, { p: [dx, .25, fz + .06] });
  put(ball(.02, 8, 6), '#e3c06a', { p: [dx + .14, .45, fz + .07], mat: 'gold' });
  put(rb(.56, .05, .3, .02), '#e9e0d3', { p: [dx, .085, fz + .17] });
  // 门上一盏小壁灯、门边一个圆牌
  put(box(.02, .1, .06), C.iron, { p: [dx + .32, .85, fz + .04] });
  put(lathe([[0, 0], [.04, .01], [.05, .08], [.03, .11], [0, .12]], 10), '#f6d79a', { p: [dx + .32, .76, fz + .1], mat: 'glow' });
  // 二楼：一扇拱窗（花箱）、一个小阳台；墙上一块大饼干
  win(put, M(mx - .5, h1 + .2, fz + .01), .32, .42, { arch: true });
  win(put, M(mx + .45, h1 + .2, fz + .01), .28, .38);
  put(rb(.5, .05, .22, .02), C.trim, { p: [mx + .45, h1 + .12, fz + .12] });
  for (let k = 0; k < 7; k++) put(cyl(.01, .01, .16, 6), C.iron, { p: [mx + .23 + k * .073, h1 + .22, fz + .22] });
  put(box(.5, .015, .015), C.iron, { p: [mx + .45, h1 + .3, fz + .22] });
  cookie(put, M(mx + .02, h1 + .55, fz + .04), .17);
  // 侧楼：蓝色筒瓦、浅蓝白的墙，一个小卖窗配蓝白条纹雨棚，台面上摆着面包和果酱
  const ax = 1.1, aw = 1.05, ad = 1.35, ah = 1.0, az = fz - ad / 2 - .05;
  put(rb(aw, ah, ad, .04), C.wall2, { p: [ax, ah / 2 + .06, az] });
  const rh2 = .45, half2 = ad / 2 + .1, ang2 = Math.atan2(rh2, half2), sl2 = Math.hypot(half2, rh2);
  for (const s of [-1, 1]) barrelRoof(put, ax, ah + .06 + rh2 / 2, az + s * half2 / 2, aw + .12, sl2, ang2, C.blue, C.blueD, s);
  frosting(put, ax, ah + .04, fz - .02, aw, C.frostB);
  put(rb(.62, .42, .04, .02), C.wood, { p: [ax, .58, fz - .05] });
  put(box(.54, .34, .02), '#3e3a3a', { p: [ax, .58, fz - .03] });
  put(rb(.72, .05, .26, .02), C.woodD, { p: [ax, .36, fz + .06] });
  for (let k = 0; k < 4; k++) put(new THREE.CapsuleGeometry(.03, .08, 4, 10), '#d9a35c', { p: [ax - .22 + k * .14, .41, fz + .06], r: [0, 0, Math.PI / 2] });
  for (const k of [0, 1]) { put(cyl(.035, .035, .07, 12), ['#d9566a', '#e8a940'][k], { p: [ax + .2 + k * .08, .42, fz + .1] }); put(cyl(.037, .037, .02, 12), '#f3eee5', { p: [ax + .2 + k * .08, .465, fz + .1] }); }
  awning(put, ax, .9, fz + .14, .8, .36, C.stripeB, C.trim);
  win(put, M(ax + aw / 2 + .005, .35, az, Math.PI / 2), .26, .34);
  // 门口：A 字小黑板、两筐面包、一盆小树、圆牌路灯
  const bm = new THREE.Matrix4().makeRotationX(-.18).setPosition(-1.55, 0, fz + .55);
  put(rb(.3, .4, .03, .01), C.wood, { m: bm, p: [0, .26, 0] });
  put(box(.24, .32, .01), '#3a3f3a', { m: bm, p: [0, .27, .02] });
  for (let k = 0; k < 3; k++) put(box(.14 - k * .03, .012, .005), '#f4efe6', { m: bm, p: [0, .36 - k * .07, .027] });
  for (const [x, z] of [[-.05, fz + .55], [.18, fz + .6]]) {
    put(lathe([[.0, 0], [.12, 0], [.15, .1], [.16, .12], [0, .12]], 14), '#c9945f', { p: [x, .06, z] });
    for (let k = 0; k < 4; k++) put(new THREE.CapsuleGeometry(.03, .1, 4, 10), '#dca865', { p: [x - .06 + k * .04, .2, z], r: [0, k, Math.PI / 2 - .3] });
  }
  put(lathe([[0, 0], [.1, 0], [.12, .16], [.13, .18], [0, .18]], 14), C.terra, { p: [1.9, .06, fz + .35] });
  put(cyl(.015, .02, .3, 6), C.woodD, { p: [1.9, .35, fz + .35] });
  put(blob(.16, 2), C.leaf, { p: [1.9, .58, fz + .35] });
  for (const [x, z, col] of [[-1.85, fz + .1, C.pink], [2.05, fz - 1.3, C.stripeB]]) {
    put(cyl(.025, .03, 1.1, 10), C.iron, { p: [x, .61, z] });
    put(cyl(.13, .13, .03, 24), col, { p: [x, 1.22, z], r: [Math.PI / 2, 0, 0] });
    put(torus(.13, .015, 6, 24), C.trim, { p: [x, 1.22, z] });
    put(ball(.03, 8, 6), C.trim, { p: [x, 1.38, z] });
  }
}
