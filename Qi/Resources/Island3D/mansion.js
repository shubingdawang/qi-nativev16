// 第二帝国式宅邸（照她给的参考图）：象牙白护墙板立面、灰蓝粗面石勒脚、深海军蓝鱼鳞瓦复折屋顶、
// 每层一道带托架的檐口、窗套和窗楣、门廊立柱和栏杆、正中门楼和大台阶、右边一座钟形穹顶塔楼、屋顶黑铁花边。
import * as THREE from 'three';
import { bake, box, cyl, cone, ball, torus, lathe, tri3 } from './kit.js';

const C = {
  white: '#f8f5ee', ivory: '#ffffff', cream: '#efe9dd', shade: '#ddd5c6', iron: '#1c2026',
  wood: '#7b3c25', woodD: '#5b2a1a', frame: '#8a5838', glass: '#58708a', curtain: '#f2efe8', gold: '#c9a45c', lamp: '#f6d79a',
};

// 一个局部坐标系里摆东西：origin（宅邸原点）× m（这一组的位置朝向）× 每块自己的 p/r/s
function maker(o) {
  const O = new THREE.Matrix4().makeTranslation(o.cx, o.t, o.cz);
  const put = (geo, color, opt = {}) => bake(geo, color, { ...opt, matrix: opt.m ? O.clone().multiply(opt.m) : O, ao: null });
  return put;
}
const M = (x, y, z, ry = 0) => new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z);
const mul = (a, b) => a.clone().multiply(b);

function extrude(shape, depth) {
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 12 });
  g.translate(0, 0, -depth / 2); return g;
}
const triShape = (w, h) => { const s = new THREE.Shape(); s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(0, h); s.closePath(); return s; };
const segShape = (w, h) => { const s = new THREE.Shape(); s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.quadraticCurveTo(0, h * 2, -w / 2, 0); return s; };

// 一排托架（檐口下面一个个小牛腿）
function brackets(put, m, len, y, z, { step = .14, h = .1, d = .08 } = {}) {
  const n = Math.max(2, Math.round(len / step));
  for (let i = 0; i <= n; i++) {
    const x = -len / 2 + i * len / n;
    put(box(.035, h, d), C.white, { m, p: [x, y - h / 2, z + d / 2] });
    put(box(.035, .03, d * .6), C.white, { m, p: [x, y - h - .01, z + d * .3] });
  }
}
// 檐口：一条腰板、一排托架、上面两层挑出来的线脚
function cornice(put, m, len, y, z, deep = .12) {
  put(box(len, .07, .03), C.white, { m, p: [0, y - .17, z + .015] });
  brackets(put, m, len, y - .03, z, { d: deep * .8 });
  put(box(len + .04, .03, deep), C.white, { m, p: [0, y - .025, z + deep / 2] });
  put(box(len + .1, .03, deep + .05), C.white, { m, p: [0, y + .005, z + (deep + .05) / 2] });
}
// 一扇窗：窗台和小托、两边壁柱、深色玻璃、暖棕窗框和窗棂、白纱帘；head = 'cornice' / 'tri' / 'seg' / 'arch'
function windowSE(put, m, w, h, head = 'cornice') {
  put(box(w + .16, .035, .09), C.white, { m, p: [0, -.02, .045] });
  for (const sx of [-1, 1]) put(box(.03, .05, .05), C.white, { m, p: [sx * w * .35, -.06, .03] });
  for (const sx of [-1, 1]) { put(box(.045, h + .02, .045), C.white, { m, p: [sx * (w / 2 + .03), h / 2, .02] }); put(box(.06, .03, .05), C.white, { m, p: [sx * (w / 2 + .03), h + .02, .025] }); }
  put(box(w, h, .01), C.glass, { m, p: [0, h / 2, -.005], mat: 'glass' });
  for (const sx of [-1, 1]) put(box(w * .3, h * .8, .008), C.curtain, { m, p: [sx * w * .33, h * .55, .001] });
  put(box(w * .9, h * .14, .008), C.curtain, { m, p: [0, h * .9, .002] });
  for (const [x, y, ww, hh] of [[0, .01, w, .02], [0, h - .01, w, .02], [-w / 2 + .01, h / 2, .02, h], [w / 2 - .01, h / 2, .02, h], [0, h / 2, .015, h], [0, h * .62, w, .015]]) put(box(ww, hh, .02), C.frame, { m, p: [x, y, .006] });
  if (head === 'arch') {
    const g = new THREE.CircleGeometry(w / 2, 16, 0, Math.PI); put(g, C.glass, { m, p: [0, h, -.004], mat: 'glass' });
    put(torus(w / 2 + .03, .028, 6, 18, Math.PI), C.white, { m, p: [0, h, .02] });
    put(box(.05, .08, .05), C.white, { m, p: [0, h + w / 2 + .02, .03] });   // 拱心石
  } else if (head === 'tri') {
    put(box(w + .2, .04, .07), C.white, { m, p: [0, h + .06, .035] });
    put(extrude(triShape(w + .24, .16), .06), C.white, { m, p: [0, h + .08, .03] });
  } else if (head === 'seg') {
    put(box(w + .2, .04, .07), C.white, { m, p: [0, h + .06, .035] });
    put(extrude(segShape(w + .24, .09), .06), C.white, { m, p: [0, h + .08, .03] });
  } else {
    put(box(w + .14, .05, .06), C.white, { m, p: [0, h + .05, .03] });
    put(box(w + .2, .03, .08), C.white, { m, p: [0, h + .09, .04] });
    for (const sx of [-1, 0, 1]) put(box(.03, .04, .04), C.white, { m, p: [sx * w * .4, h + .12, .03] });
  }
}
// 栏杆：底座、一排车削小柱、扶手
const BAL = lathe([[.022, 0], [.022, .015], [.014, .03], [.027, .08], [.012, .13], [.018, .15], [.018, .16]], 8);
function balustrade(put, m, len, y = 0, z = 0) {
  put(box(len, .035, .07), C.white, { m, p: [0, y + .017, z] });
  put(box(len + .03, .03, .08), C.white, { m, p: [0, y + .2, z] });
  const n = Math.max(2, Math.round(len / .055));
  for (let i = 0; i < n; i++) put(BAL, C.white, { m, p: [-len / 2 + (i + .5) * len / n, y + .035, z] });
}
const COLUMN = (h) => lathe([[.06, 0], [.06, .04], [.045, .07], [.04, h * .3], [.048, h * .33], [.04, h * .36], [.036, h - .1], [.05, h - .06], [.065, h - .02], [.065, h]], 12);

// 复折屋顶（下沿往外翻一点的钟形曲线），上面一圈黑铁花边
function mansard(put, x0, x1, z0, z1, y, h, { inset = .32, cresting = true, finials = 0 } = {}) {
  const seg = 8, off = (t) => inset * (1 - Math.pow(1 - t, 2.2)) - .06 * (1 - t) * (1 - t);
  const lv = []; for (let i = 0; i <= seg; i++) { const t = i / seg, d = off(t); lv.push([x0 + d, x1 - d, z0 + d, z1 - d, y + h * t]); }
  const pos = [];
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
  const quad = (a, b, c, d) => {   // 正面朝外
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2], vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
    const nx = uy * vz - uz * vy, nz = ux * vy - uy * vx;
    const mx = (a[0] + c[0]) / 2 - cx, mz = (a[2] + c[2]) / 2 - cz;
    if (nx * mx + nz * mz >= 0) pos.push(...a, ...b, ...c, ...a, ...c, ...d); else pos.push(...a, ...c, ...b, ...a, ...d, ...c);
  };
  for (let i = 0; i < seg; i++) {
    const [ax0, ax1, az0, az1, ay] = lv[i], [bx0, bx1, bz0, bz1, by] = lv[i + 1];
    quad([ax0, ay, az1], [ax1, ay, az1], [bx1, by, bz1], [bx0, by, bz1]);
    quad([ax1, ay, az0], [ax0, ay, az0], [bx0, by, bz0], [bx1, by, bz0]);
    quad([ax0, ay, az0], [ax0, ay, az1], [bx0, by, bz1], [bx0, by, bz0]);
    quad([ax1, ay, az1], [ax1, ay, az0], [bx1, by, bz0], [bx1, by, bz1]);
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.computeVertexNormals();
  put(g, '#ffffff', { mat: 'roof' });
  const [tx0, tx1, tz0, tz1, ty] = lv[seg];
  put(box(tx1 - tx0, .03, tz1 - tz0), '#3a4558', { p: [(tx0 + tx1) / 2, ty, (tz0 + tz1) / 2] });
  // 白色的底边、顶边、四条转角线
  put(box(x1 - x0 + .1, .06, .05), C.white, { p: [cx, y + .03, z1 + .02] });
  for (const [xx0, xx1, zz] of [[x0, x1, z0]]) put(box(xx1 - xx0 + .1, .06, .05), C.white, { p: [cx, y + .03, zz - .02] });
  for (const xx of [x0, x1]) put(box(.05, .06, z1 - z0 + .1), C.white, { p: [xx + (xx === x0 ? -.02 : .02), y + .03, cz] });
  put(box(tx1 - tx0 + .08, .05, .04), C.white, { p: [cx, ty + .02, tz1] });
  put(box(tx1 - tx0 + .08, .05, .04), C.white, { p: [cx, ty + .02, tz0] });
  for (const xx of [tx0, tx1]) put(box(.04, .05, tz1 - tz0 + .08), C.white, { p: [xx, ty + .02, cz] });
  for (let i = 0; i < seg; i++) for (const [ia, ib] of [[0, 2], [1, 2], [0, 3], [1, 3]]) {
    const a = lv[i], b = lv[i + 1];
    const ax = a[ia], az = a[ib], bx = b[ia], bz = b[ib];
    const len = Math.hypot(bx - ax, b[4] - a[4], bz - az);
    const mm = new THREE.Matrix4().lookAt(new THREE.Vector3(ax, a[4], az), new THREE.Vector3(bx, b[4], bz), new THREE.Vector3(0, 1, 0));
    mm.setPosition((ax + bx) / 2, (a[4] + b[4]) / 2, (az + bz) / 2);
    put(box(.035, .035, len + .01), C.white, { m: mm });
  }
  if (!cresting) return;
  // 黑铁花边：一圈细柱、两道横杆、隔几根一个百合花尖
  const perim = [[tx0, tz1, tx1, tz1], [tx1, tz1, tx1, tz0], [tx1, tz0, tx0, tz0], [tx0, tz0, tx0, tz1]];
  for (const [ax, az, bx, bz] of perim) {
    const len = Math.hypot(bx - ax, bz - az), n = Math.max(2, Math.round(len / .07));
    for (let i = 0; i < n; i++) {
      const t = i / n, x = ax + (bx - ax) * t, z = az + (bz - az) * t;
      put(box(.008, .14, .008), C.iron, { p: [x, ty + .1, z], mat: 'iron' });
      if (i % 3 === 0) { put(ball(.012, 6, 4), C.iron, { p: [x, ty + .19, z], mat: 'iron' }); put(cone(.008, .05, 4), C.iron, { p: [x, ty + .23, z], mat: 'iron' }); }
      else put(torus(.018, .004, 4, 8), C.iron, { p: [x, ty + .1, z], r: [0, Math.atan2(bx - ax, bz - az) + Math.PI / 2, 0], mat: 'iron' });
    }
    const mm = new THREE.Matrix4().makeRotationY(Math.atan2(bx - ax, bz - az)).setPosition((ax + bx) / 2, ty, (az + bz) / 2);
    for (const yy of [.04, .17]) put(box(.01, .01, len), C.iron, { m: mm, p: [0, yy, 0], mat: 'iron' });
  }
  for (let k = 0; k < finials; k++) {
    const x = finials === 1 ? cx : tx0 + (tx1 - tx0) * k / (finials - 1);
    fleur(put, x, ty + .03, (tz0 + tz1) / 2 + (tz1 - tz0) / 2, 1.2);
  }
}
// 铁花尖饰：一根杆、一个球、三瓣百合花
function fleur(put, x, y, z, s = 1) {
  put(box(.025 * s, .08 * s, .025 * s), C.iron, { p: [x, y + .04 * s, z], mat: 'iron' });
  put(cyl(.007 * s, .007 * s, .32 * s, 5), C.iron, { p: [x, y + .22 * s, z], mat: 'iron' });
  put(ball(.025 * s, 8, 6), C.iron, { p: [x, y + .16 * s, z], mat: 'iron' });
  put(cone(.014 * s, .1 * s, 5), C.iron, { p: [x, y + .43 * s, z], mat: 'iron' });
  for (const sx of [-1, 1]) put(torus(.03 * s, .006 * s, 4, 10, Math.PI * 1.2), C.iron, { p: [x + sx * .03 * s, y + .36 * s, z], r: [0, 0, sx > 0 ? -.3 : Math.PI + .3], mat: 'iron' });
}
// 老虎窗：从复折屋顶上探出来，拱窗，顶上弧形窗楣和一个小瓮
function dormer(put, x, y, z, w = .3, h = .42) {
  const m = M(x, y, z);
  put(box(w + .14, h + .1, .3), C.cream, { m, p: [0, (h + .1) / 2, -.12], mat: 'siding' });
  windowSE(put, mul(m, M(0, .06, .035)), w, h * .6, 'arch');
  for (const sx of [-1, 1]) { put(box(.05, h + .1, .06), C.white, { m, p: [sx * (w / 2 + .06), (h + .1) / 2, .03] }); put(box(.035, .1, .06), C.white, { m, p: [sx * (w / 2 + .1), .12, .03], r: [0, 0, sx * .5] }); }
  put(extrude(segShape(w + .3, .13), .07), C.white, { m, p: [0, h + .12, .03] });
  put(box(w + .34, .04, .1), C.white, { m, p: [0, h + .11, .03] });
  put(lathe([[0, 0], [.02, 0], [.012, .02], [.03, .05], [.03, .07], [0, .08]], 8), C.white, { m, p: [0, h + .22, .03] });
}

export function mansion(o, d) {
  const put = maker(o);
  const fz = .35, Dp = 2.6, bz = fz - Dp, base = .42, f1 = 1.0, f2 = .95, top = base + f1 + f2;
  const XL = -2.0, XC0 = -.7, XC1 = .7, XR = 2.05;
  // 勒脚：灰蓝粗面石，几个半地下室的小窗
  put(box(XR - XL, base, Dp), '#ffffff', { p: [(XL + XR) / 2, base / 2, fz - Dp / 2], mat: 'plinth' });
  put(box(XR - XL + .04, .04, Dp + .04), C.white, { p: [(XL + XR) / 2, base, fz - Dp / 2] });
  for (const x of [-1.6, -1.05, 1.0, 1.6]) { put(box(.24, .14, .02), C.glass, { p: [x, .2, fz + .005], mat: 'glass' }); put(box(.28, .03, .04), C.white, { p: [x, .29, fz + .01] }); }
  // 墙身（护墙板），中间门楼往前凸 .25
  put(box(XC0 - XL, f1 + f2, Dp), '#ffffff', { p: [(XL + XC0) / 2, base + (f1 + f2) / 2, fz - Dp / 2], mat: 'siding' });
  put(box(XC1 - XC0, f1 + f2, Dp + .25), '#ffffff', { p: [0, base + (f1 + f2) / 2, fz - Dp / 2 + .125], mat: 'siding' });
  put(box(XR - XC1, f1 + f2, Dp), '#ffffff', { p: [(XC1 + XR) / 2, base + (f1 + f2) / 2, fz - Dp / 2], mat: 'siding' });
  // 每段墙的转角：白色壁柱，柱头一小块
  for (const [x, z] of [[XL, fz], [XC0, fz + .25], [XC1, fz + .25], [XR, fz], [XC0 - .02, fz], [XC1 + .02, fz]]) {
    put(box(.09, f1 + f2, .06), C.white, { p: [x, base + (f1 + f2) / 2, z + .02] });
    for (const y of [base + f1 - .1, top - .1]) put(box(.13, .06, .09), C.white, { p: [x, y, z + .03] });
  }
  // 两道檐口
  const front = M(0, 0, 0);
  for (const y of [base + f1, top]) {
    cornice(put, mul(front, M((XL + XC0) / 2, 0, fz)), XC0 - XL, y, 0);
    cornice(put, mul(front, M(0, 0, fz + .25)), XC1 - XC0, y, 0);
    for (const sx of [-1, 1]) cornice(put, M(sx > 0 ? XR : XL, 0, fz - Dp / 2, sx * Math.PI / 2), Dp, y, 0);
  }
  // 左翼：一楼门廊（立柱、栏杆、鱼鳞瓦顶棚），两层各两扇窗
  for (const x of [-1.62, -1.05]) {
    windowSE(put, M(x, base + .2, fz + .005), .3, .62, 'seg');
    windowSE(put, M(x, base + f1 + .18, fz + .005), .3, .6, 'tri');
  }
  const pd = .6, ph = .82;
  put(box(XC0 - XL + .1, .06, pd), C.cream, { p: [(XL + XC0) / 2, base + .03, fz + pd / 2] });
  for (const x of [XL + .05, -1.35, XC0 - .05]) { put(box(.13, .06, .13), C.white, { p: [x, base + .09, fz + pd - .06] }); put(COLUMN(ph - .06), C.white, { p: [x, base + .12, fz + pd - .06] }); }
  for (const [x0, x1] of [[XL + .05, -1.35], [-1.35, XC0 - .05]]) balustrade(put, M((x0 + x1) / 2, base + .06, fz + pd - .06), x1 - x0 - .12);
  put(box(XC0 - XL + .14, .06, pd + .06), C.white, { p: [(XL + XC0) / 2, base + ph + .1, fz + pd / 2] });
  brackets(put, M((XL + XC0) / 2, 0, fz + pd - .02), XC0 - XL, base + ph + .07, 0, { step: .17, h: .09, d: .06 });
  put(box(XC0 - XL + .14, .04, pd + .1), '#ffffff', { p: [(XL + XC0) / 2, base + ph + .16, fz + pd / 2 - .02], r: [.18, 0, 0], mat: 'roof' });
  balustrade(put, M((XL + XC0) / 2, base + ph + .18, fz + pd - .05), XC0 - XL - .1);   // 门廊顶上是二楼的阳台
  // 门楼：一楼门廊式入口（两对柱子、山花、拱门、双开木门），二楼一对拱窗配小阳台
  const ez = fz + .25;
  windowSE(put, M(-.24, base + f1 + .18, ez + .005), .26, .6, 'arch');
  windowSE(put, M(.24, base + f1 + .18, ez + .005), .26, .6, 'arch');
  put(box(1.0, .05, .3), C.white, { p: [0, base + f1 + .1, ez + .15] });
  for (let i = 0; i < 4; i++) put(box(.04, .1, .25), C.white, { p: [-.4 + i * .27, base + f1 + .02, ez + .12] });
  balustrade(put, M(0, base + f1 + .12, ez + .28), .96);
  // 入口：往前再伸出来的门廊
  const pz = ez + .7;
  put(box(1.3, .06, .75), C.cream, { p: [0, base + .03, ez + .37] });
  for (const sx of [-1, 1]) for (const k of [0, 1]) { const x = sx * (.42 + k * .17); put(box(.14, .08, .14), C.white, { p: [x, base + .1, pz - .08] }); put(COLUMN(.85), C.white, { p: [x, base + .14, pz - .08] }); }
  put(box(1.3, .12, .74), C.white, { p: [0, base + 1.05, ez + .36] });
  brackets(put, M(0, 0, pz - .02), 1.3, base + 1.0, 0, { step: .1, h: .07, d: .05 });
  put(extrude(triShape(1.42, .42), .14), C.white, { p: [0, base + 1.11, pz - .06] });
  put(extrude(triShape(1.2, .33), .03), C.cream, { p: [0, base + 1.15, pz + .02] });
  put(torus(.09, .025, 6, 18), C.white, { p: [0, base + 1.3, pz + .03] });   // 山花里一个圆形浮雕
  put(cyl(.07, .07, .03, 16), C.shade, { p: [0, base + 1.3, pz + .02], r: [Math.PI / 2, 0, 0] });
  for (const sx of [-1, 1]) put(torus(.05, .012, 4, 10, Math.PI * 1.4), C.white, { p: [sx * .17, base + 1.25, pz + .03], r: [0, 0, sx > 0 ? 0 : Math.PI] });
  put(lathe([[0, 0], [.03, 0], [.02, .03], [.045, .07], [.045, .1], [0, .12]], 10), C.white, { p: [0, base + 1.55, pz - .06] });
  // 门：拱形门套、双开胡桃木门（门板、玻璃）、上面扇形亮窗、吊灯
  const dm = M(0, base + .06, ez + .01);
  put(box(.66, .88, .06), C.white, { m: dm, p: [0, .44, .02] });
  put(torus(.31, .04, 6, 20, Math.PI), C.white, { m: dm, p: [0, .86, .03] });
  put(box(.54, .82, .04), C.wood, { m: dm, p: [0, .41, .03] });
  put(new THREE.CircleGeometry(.27, 16, 0, Math.PI), C.glass, { m: dm, p: [0, .84, .03], mat: 'glass' });
  for (let k = 0; k < 5; k++) put(box(.012, .27, .02), C.wood, { m: dm, p: [0, .84, .035], r: [0, 0, -Math.PI / 2 + k * Math.PI / 4] });
  for (const sx of [-1, 1]) {
    put(box(.006, .82, .02), C.woodD, { m: dm, p: [0, .41, .055] });
    put(box(.16, .3, .015), C.glass, { m: dm, p: [sx * .135, .58, .052], mat: 'glass' });
    put(box(.18, .025, .02), C.woodD, { m: dm, p: [sx * .135, .42, .056] });
    put(box(.16, .3, .015), C.woodD, { m: dm, p: [sx * .135, .2, .05] });
    put(ball(.012, 6, 4), C.gold, { m: dm, p: [sx * .04, .4, .07], mat: 'gold' });
  }
  put(cyl(.004, .004, .2, 4), C.iron, { p: [0, base + .95, ez + .35], mat: 'iron' });
  put(lathe([[.0, 0], [.05, .02], [.07, .1], [.05, .16], [0, .18]], 8), C.lamp, { p: [0, base + .7, ez + .35], mat: 'glow' });
  // 大台阶：五级，两边栏杆，扶手尽头立柱上一个瓮
  for (let i = 0; i < 5; i++) put(box(1.0 + i * .06, .085, .16), C.cream, { p: [0, base - .04 - i * .085, pz + .08 + i * .16], mat: 'ashlar' });
  for (const sx of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(Math.atan2(.42, .8)).setPosition(sx * .56, base * .5 + .02, pz + .42);
    put(box(.08, .06, .92), C.white, { m, p: [0, .23, 0] });
    put(box(.1, .05, .94), C.white, { m, p: [0, -.02, 0] });
    for (let k = 0; k < 9; k++) put(box(.025, .2, .025), C.white, { m, p: [0, .1, -.42 + k * .105] });
    put(box(.16, .45, .16), C.white, { p: [sx * .56, .22, pz + .9] });
    put(lathe([[0, 0], [.05, 0], [.035, .03], [.08, .1], [.09, .15], [0, .17]], 12), C.white, { p: [sx * .56, .45, pz + .9] });
  }
  // 中间门楼的高复折屋顶 + 正中一扇大老虎窗；左翼一段矮的复折屋顶 + 一扇老虎窗
  mansard(put, XC0 - .05, XC1 + .05, bz + .3, ez + .05, top + .03, 1.05, { inset: .34, finials: 3 });
  dormer(put, 0, top + .1, ez - .02, .34, .5);
  mansard(put, XL - .05, XC0, bz, fz + .05, top + .03, .8, { inset: .3 });
  dormer(put, (XL + XC0) / 2, top + .08, fz - .03, .3, .42);
  // 左边高高的白烟囱
  for (const x of [-1.75]) {
    put(box(.3, 1.3, .3), C.white, { p: [x, top + .55, bz + .7], mat: 'siding' });
    put(box(.38, .06, .38), C.white, { p: [x, top + 1.22, bz + .7] });
    put(box(.34, .05, .34), C.white, { p: [x, top + .95, bz + .7] });
    for (const dx of [-.06, .06]) put(cyl(.04, .045, .14, 8), C.cream, { p: [x + dx, top + 1.32, bz + .7] });
  }
  // 右边塔楼：八角，三层，钟形穹顶，顶上小灯笼亭和尖饰
  const tx = 1.42, tz = fz - .4, tr = .66, t3 = .85, tTop = top + t3;
  const rot8 = [0, Math.PI / 8, 0];
  put(cyl(tr + .04, tr + .06, base, 8), '#ffffff', { p: [tx, base / 2, tz], r: rot8, mat: 'plinth' });
  put(cyl(tr, tr, tTop - base, 8), '#ffffff', { p: [tx, base + (tTop - base) / 2, tz], r: rot8, mat: 'siding' });
  for (const y of [base + f1, top, tTop]) {
    put(cyl(tr + .05, tr + .03, .08, 8), C.white, { p: [tx, y - .14, tz], r: rot8 });
    put(cyl(tr + .1, tr + .1, .035, 8), C.white, { p: [tx, y - .02, tz], r: rot8 });
    for (let k = 0; k < 8; k++) {   // 每面三个托架
      const a = k / 8 * Math.PI * 2;
      for (const off of [-.18, 0, .18]) {
        const ax = Math.cos(a) * (tr + .03) - Math.sin(a) * off, az = Math.sin(a) * (tr + .03) + Math.cos(a) * off;
        put(box(.035, .08, .07), C.white, { p: [tx + ax, y - .07, tz + az], r: [0, -a, 0] });
      }
    }
  }
  const faceR = tr * Math.cos(Math.PI / 8);
  for (const fa of [-Math.PI / 4, 0, Math.PI / 4]) {
    const a = Math.PI / 2 - fa;
    const at = (y) => M(tx + Math.cos(a) * (faceR + .005), y, tz + Math.sin(a) * (faceR + .005), fa);
    windowSE(put, at(base + .2), .24, .62, 'seg');
    windowSE(put, at(base + f1 + .18), .24, .58, 'tri');
    windowSE(put, at(top + .14), .22, .44, 'arch');
  }
  // 钟形穹顶（鱼鳞瓦），八条白色棱线，正面一扇小圆窗老虎窗
  const R0 = tr + .1, prof = [[R0, 0], [R0 - .02, .1], [R0 - .1, .3], [R0 - .24, .55], [R0 - .4, .78], [R0 - .52, .92], [R0 - .56, 1.0]];
  const dome = lathe(prof, 8); dome.rotateY(Math.PI / 8);
  put(dome, '#ffffff', { p: [tx, tTop + .02, tz], mat: 'roof' });
  for (let k = 0; k < 8; k++) {
    const a = k / 8 * Math.PI * 2;
    for (let i = 0; i < prof.length - 1; i++) {
      const [r0, y0] = prof[i], [r1, y1] = prof[i + 1];
      const p0 = new THREE.Vector3(tx + Math.cos(a) * r0, tTop + .02 + y0, tz + Math.sin(a) * r0), p1 = new THREE.Vector3(tx + Math.cos(a) * r1, tTop + .02 + y1, tz + Math.sin(a) * r1);
      const mm = new THREE.Matrix4().lookAt(p0, p1, new THREE.Vector3(0, 1, 0)).setPosition(p0.clone().add(p1).multiplyScalar(.5));
      put(box(.04, .04, p0.distanceTo(p1) + .02), C.white, { m: mm });
    }
  }
  {
    const dz = tz + R0 - .2, dy = tTop + .3;
    put(box(.3, .34, .3), C.white, { p: [tx, dy + .1, dz - .06] });
    put(torus(.08, .02, 6, 16), C.white, { p: [tx, dy + .12, dz + .1] });
    put(cyl(.07, .07, .02, 16), C.glass, { p: [tx, dy + .12, dz + .09], r: [Math.PI / 2, 0, 0], mat: 'glass' });
    put(extrude(triShape(.36, .18), .06), C.white, { p: [tx, dy + .28, dz + .08] });
  }
  // 灯笼亭：八角小亭、一圈小栏杆、小穹顶、高高的铁尖
  const ly = tTop + 1.02;
  put(cyl(.3, .3, .05, 8), C.white, { p: [tx, ly, tz], r: rot8 });
  for (let k = 0; k < 16; k++) { const a = k / 16 * Math.PI * 2; put(box(.012, .1, .012), C.white, { p: [tx + Math.cos(a) * .28, ly + .07, tz + Math.sin(a) * .28] }); }
  put(cyl(.29, .29, .015, 8), C.white, { p: [tx, ly + .13, tz], r: rot8 });
  put(cyl(.17, .17, .26, 8), C.white, { p: [tx, ly + .16, tz], r: rot8 });
  for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2 + Math.PI / 8; put(box(.06, .16, .01), C.glass, { p: [tx + Math.cos(a) * .16, ly + .17, tz + Math.sin(a) * .16], r: [0, -a + Math.PI / 2, 0], mat: 'glass' }); }
  put(lathe([[.2, 0], [.19, .04], [.14, .12], [.07, .18], [0, .2]], 8), '#ffffff', { p: [tx, ly + .29, tz], mat: 'roof' });
  fleur(put, tx, ly + .47, tz, 1.5);
}
