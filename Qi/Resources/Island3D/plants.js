// 田里的庄稼：用 sculpt.js 捏出来（叶子按轮廓长、茎沿曲线长、果子有凹有棱），不拿球和胶囊拼。
// 每一样都分四步：0 刚种下（一小撮翻过的土）· 1 发芽（两片子叶）· 2 长叶（没结果，有的开花或打苞）· 3 成熟
// 所有零件带顶点色合成一个网格（一次绘制），颜色每片叶子都差一点点。
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { leaf as leafShape, stem, fruit, rock, noise, LEAF, PETAL, BLADE } from './sculpt.js';

// 叶子只铺一层：田里的材质两面都画
const leaf = (o) => leafShape({ both: false, ...o });

const ROUND = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .8)), .75);
const HEART = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .6)), .8) * (1 + .3 * Math.sin(Math.PI * u * .9));
const LOBED = (u) => ROUND(u) * (1 + .16 * Math.sin(u * Math.PI * 6));
const C = { leaf: '#7b9758', leafD: '#5f7d47', leafL: '#97ad6c', stem: '#7a9152', wood: '#8a6a48', soil: '#7d5f45' };

// 收零件：每块摆好、上色，最后合成一个网格
export function collector(rnd) {
  const list = [], m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), sv = new THREE.Vector3(), pv = new THREE.Vector3(), tc = new THREE.Color(), v = new THREE.Vector3();
  function add(geo, color, { p = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1], vcol = null, parent = null, jit = .06 } = {}) {
    let g = geo.index ? geo.toNonIndexed() : geo.clone();
    for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal') g.deleteAttribute(k);
    if (!g.attributes.normal) g.computeVertexNormals();
    const base = new THREE.Color(color).multiplyScalar(1 + (rnd() - .5) * 2 * jit);
    const pa = g.attributes.position, n = pa.count, ca = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      tc.copy(base); if (vcol) { v.fromBufferAttribute(pa, i); vcol(v, tc); }
      ca[i * 3] = tc.r; ca[i * 3 + 1] = tc.g; ca[i * 3 + 2] = tc.b;
    }
    e.set(r[0], r[1], r[2]); q.setFromEuler(e); m4.compose(pv.set(p[0], p[1], p[2]), q, sv.set(s[0], s[1], s[2]));
    if (parent) m4.premultiply(parent);
    if (add.pre) m4.premultiply(add.pre);
    g.applyMatrix4(m4); g.setAttribute('color', new THREE.BufferAttribute(ca, 3));
    list.push(g);
  }
  add.mat = (p, r = [0, 0, 0], s = 1) => new THREE.Matrix4().compose(new THREE.Vector3(...p), new THREE.Quaternion().setFromEuler(new THREE.Euler(...r)), new THREE.Vector3(s, s, s));
  add.mesh = (mat) => (list.length ? new THREE.Mesh(mergeGeometries(list), mat) : null);
  return add;
}

const V = (x, y, z) => new THREE.Vector3(x, y, z);
// 从 (x, y, z) 朝 a 方向（绕 y 轴）走 d、升 h
const out = (x, y, z, a, d, h) => V(x + Math.cos(a) * d, y + h, z - Math.sin(a) * d);

// ———— 共用的几步 ————
function mound(add, x, y, z, rnd) {   // 刚种下：一小撮翻过的土，上面露一两粒种子
  add(rock(.045, { flat: .45, seed: rnd() * 99 | 0, rough: .3, detail: 2 }), C.soil, { p: [x, y + .005, z], r: [0, rnd() * 6, 0], s: [1.2, 1, 1] });
  add(fruit(.006, { sy: .7, lump: .1 }), '#d8c49a', { p: [x + .01, y + .025, z - .006] });
}
function sprout(add, x, y, z, rnd) {   // 发芽：一根弯弯的小茎，顶上两片圆圆的子叶
  const a = rnd() * 6.28, h = .05 + rnd() * .015;
  add(stem([[x, y, z], [x + .006, y + h * .55, z], [x, y + h, z]], .004, .003, { seg: 6, rad: 5 }), C.stem);
  for (const k of [0, Math.PI]) add(leaf({ len: .04, wid: .028, shape: ROUND, droop: .12, fold: .25, segL: 6, segW: 2, seed: rnd() * 9 }), C.leafL, { p: [x, y + h, z], r: [0, a + k, .35] });
}
// 一片复叶：一根叶柄上对生几对小叶，顶上一片（番茄、玫瑰、胡萝卜都这样）
function compound(add, base, a, len, lift, { pairs = 2, lw = .045, ww = .028, col = C.leaf, rnd, wave = .25, shape = LEAF } = {}) {
  const [x, y, z] = base, end = out(x, y, z, a, len, lift), mid = out(x, y, z, a, len * .55, lift * 1.05);
  const pet = [V(x, y, z), mid, end];
  add(stem(pet, .0035, .002, { seg: 6, rad: 4 }), C.stem);
  const curve = new THREE.CatmullRomCurve3(pet);
  for (let i = 1; i <= pairs; i++) {
    const t = .3 + .55 * i / (pairs + .5), p = curve.getPointAt(t);
    for (const sd of [-1, 1]) add(leaf({ len: lw * (1 - t * .3), wid: ww, shape, droop: .2, fold: .35, wave, waves: 7, segL: 5, segW: 2, seed: rnd() * 9 }), col, { p: [p.x, p.y, p.z], r: [0, a + sd * 1.1, -.15] });
  }
  add(leaf({ len: lw, wid: ww * 1.05, shape, droop: .25, fold: .35, wave, waves: 7, segL: 5, segW: 2, seed: rnd() * 9 }), col, { p: [end.x, end.y, end.z], r: [0, a, -.2] });
}

// ———— 各样庄稼 ————
function strawberry(add, x, y, z, rnd, st) {
  const sc = st === 3 ? 1 : .8;
  for (let i = 0; i < 5; i++) {   // 一丛三出复叶：叶柄拱出去，顶上三片带锯齿的圆叶
    const a = i / 5 * 6.28 + rnd() * .6, d = .055 * sc * (.8 + rnd() * .4), h = .085 * sc * (.8 + rnd() * .4);
    const tip = out(x, y, z, a, d, h);
    add(stem([V(x, y, z), out(x, y, z, a, d * .3, h * .8), tip], .0035, .0025, { seg: 6, rad: 4 }), C.stem);
    for (const k of [-.75, 0, .75]) add(leaf({ len: .052 * sc, wid: .042 * sc, shape: ROUND, droop: .12, fold: .4, wave: .4, waves: 9, segL: 5, segW: 2, seed: rnd() * 9 }), k ? C.leaf : C.leafD, { p: [tip.x, tip.y, tip.z], r: [0, a + k, .2] });
  }
  if (st === 2) for (let i = 0; i < 2; i++) {   // 开小白花
    const a = rnd() * 6.28, p = out(x, y, z, a, .03, .075);
    add(stem([V(x, y, z), out(x, y, z, a, .02, .06), p], .002, .0015, { seg: 6, rad: 4 }), C.stem);
    for (let k = 0; k < 5; k++) add(leaf({ len: .014, wid: .013, shape: ROUND, droop: -.05, fold: .1, segL: 4, segW: 2 }), '#f6f1e6', { p: [p.x, p.y, p.z], r: [0, k / 5 * 6.28, .25] });
    add(fruit(.004, { lump: .2 }), '#e6c34a', { p: [p.x, p.y + .003, p.z] });
  }
  if (st === 3) for (let i = 0; i < 3; i++) {   // 果子垂下来：一头尖、表面一粒粒浅色的籽、顶上一圈萼片
    const a = rnd() * 6.28, top = out(x, y, z, a, .05, .06), p = out(x, y, z, a, .085, .03);
    add(stem([V(x, y, z), top, p], .0022, .0018, { seg: 7, rad: 4 }), C.stem);
    const seed = rnd() * 50 | 0;
    add(fruit(.019, { sy: 1.3, point: .5, dent: .05, lump: .03, seed }), '#cf3b4a', { p: [p.x, p.y - .018, p.z], r: [rnd() * .4, 0, .25], vcol: (v, c) => { const t = Math.max(0, v.y / .025); c.lerp(new THREE.Color('#e9a0a0'), Math.min(1, t * t) * .45); } });   // 果肩靠萼片那圈颜色浅一点
    for (let k = 0; k < 5; k++) add(leaf({ len: .012, wid: .006, droop: -.1, fold: .2, segL: 4, segW: 1 }), C.leaf, { p: [p.x, p.y + .004, p.z], r: [0, k / 5 * 6.28, -.25] });
  }
}

function tomato(add, x, y, z, rnd, st, cherry) {
  const h = (st === 3 ? .34 : .24) * (cherry ? .9 : 1), lean = (rnd() - .5) * .04;
  // 一根竹竿撑着，主茎绕着竿往上，中间扎一道绳
  add(stem([[x + .025, y - .02, z], [x + .025, y + h + .06, z]], .005, .004, { seg: 2, rad: 6, cap: false }), '#b59a6a');
  add(stem([[x, y, z], [x + lean + .008, y + h * .35, z + .006], [x + .012, y + h * .7, z - .004], [x + lean, y + h, z]], .007, .003, { seg: 9, rad: 5 }), C.stem);
  add(new THREE.TorusGeometry(.016, .0025, 4, 10), '#d8cba8', { p: [x + .016, y + h * .55, z], r: [Math.PI / 2, 0, 0], s: [1, .8, 1] });
  for (let i = 0; i < 6; i++) {   // 复叶一层层错开长
    const t = .2 + i * .14, a = i * 2.4 + rnd() * .5;
    compound(add, [x + lean * t, y + h * t, z], a, .08 * (1.1 - t * .4), .025, { pairs: 2, lw: .04, ww: .026, rnd, col: i % 2 ? C.leaf : C.leafD });
  }
  if (st === 2) for (let i = 0; i < 3; i++) { const a = rnd() * 6.28, p = out(x, y + h * (.4 + rnd() * .4), z, a, .035, 0); for (let k = 0; k < 5; k++) add(leaf({ len: .012, wid: .006, shape: PETAL, droop: .3, segL: 4, segW: 1 }), '#ecc94a', { p: [p.x, p.y, p.z], r: [0, k / 5 * 6.28, -.5] }); }
  if (st === 3) for (let cl = 0; cl < 2; cl++) {   // 两串果子挂在叶子下面：一串里有红的也有还在转色的
    const a = cl * 3.1 + rnd(), p = out(x, y + h * (.35 + cl * .25), z, a, .045, 0);
    for (let k = 0; k < (cherry ? 5 : 3); k++) {
      const r = cherry ? .016 : .028, b = a + (k - 1) * .9, q = out(p.x, p.y - .01 - k * .012, p.z, b, r * 1.1, 0);
      const col = k === (cherry ? 4 : 2) ? '#e08a3c' : (cherry ? '#e04a42' : '#cf4337');
      add(fruit(r, { sy: .86, dent: .22, lobes: cherry ? 0 : 5, lobeAmp: .04, lump: .02, seed: rnd() * 50 | 0 }), col, { p: [q.x, q.y - r * .8, q.z] });
      for (let m = 0; m < 5; m++) add(leaf({ len: r * .6, wid: r * .25, droop: .4, fold: .2, segL: 4, segW: 1 }), C.leafD, { p: [q.x, q.y - r * .05, q.z], r: [0, m / 5 * 6.28, .1] });
    }
  }
}

function sunflower(add, x, y, z, rnd, st) {
  const h = st === 3 ? .66 : .42, a = rnd() * 6.28, sway = (rnd() - .5) * .05;
  const top = V(x + sway, y + h, z + .02);
  add(stem([V(x, y, z), V(x - sway * .3, y + h * .4, z), V(x + sway * .6, y + h * .8, z + .01), top], .012, .008, { seg: 14, rad: 7, knots: 4 }), '#7f9650');
  for (let i = 0; i < 6; i++) {   // 心形大叶：互生，叶柄斜出去，叶片往下垂
    const t = .15 + i * .13, b = a + i * 2.4, p = V(x + sway * t, y + h * t, z);
    const q = out(p.x, p.y, p.z, b, .04, .02);
    add(stem([p, q], .0035, .003, { seg: 3, rad: 5 }), C.stem);
    add(leaf({ len: .14 * (1.15 - t * .5), wid: .12 * (1.15 - t * .5), shape: HEART, droop: .45, fold: .25, wave: .25, waves: 6, segL: 8, segW: 3, seed: rnd() * 9 }), i % 2 ? C.leaf : C.leafD, { p: [q.x, q.y, q.z], r: [0, b, .15] });
  }
  // 花盘朝前（+z）、稍微低头：花盘中间一圈圈籽，外面两圈花瓣，背面绿色的萼
  const head = add.mat([top.x, top.y, top.z], [1.25 + rnd() * .2, a * .15, 0]);
  if (st === 2) { add(fruit(.04, { sy: .8, lump: .08 }), '#7d9a52', { parent: head }); for (let k = 0; k < 10; k++) add(leaf({ len: .04, wid: .02, shape: PETAL, droop: -.4, fold: .3, segL: 5, segW: 2 }), C.leaf, { p: [0, .005, 0], r: [0, k / 10 * 6.28, 1.1], parent: head }); return; }
  add(fruit(.062, { sy: .28, dent: -.15, lump: .05, seg: 36 }), '#5a3a22', { p: [0, .012, 0], parent: head, vcol: (v, c) => { const r = Math.hypot(v.x, v.z), th = Math.atan2(v.z, v.x); if (Math.sin(r * 420 + th * 8) > .2) c.multiplyScalar(.72); if (r > .045) c.lerp(new THREE.Color('#8a5a2a'), .5); } });
  for (const [n, rr, col, tilt, len] of [[18, .055, '#e9b52f', .1, .065], [16, .05, '#f2c63e', .25, .058]]) for (let k = 0; k < n; k++) {
    const ang = k / n * 6.28 + (rr < .055 ? .17 : 0);   // 花瓣从花盘边上长出去
    add(leaf({ len, wid: .022, shape: PETAL, droop: .12, fold: .3, curl: .4, segL: 5, segW: 2, seed: k }), col, { p: [Math.cos(ang) * rr * .85, 0, -Math.sin(ang) * rr * .85], r: [0, ang, tilt + (rnd() - .5) * .2], parent: head, jit: .04 });
  }
  add(fruit(.06, { sy: .32, lump: .06 }), '#6f8a46', { p: [0, -.012, 0], parent: head });
}

function lavender(add, x, y, z, rnd, st) {
  for (let i = 0; i < 12; i++) add(leaf({ len: .07, wid: .011, shape: BLADE, droop: .35, fold: .2, segL: 6, segW: 1, seed: i }), '#8fa184', { p: [x, y + .01, z], r: [0, i / 12 * 6.28 + rnd() * .3, .8] });
  const n = st === 3 ? 11 : 8;
  for (let i = 0; i < n; i++) {   // 一束细茎往外散开，顶上一穗紫色的小花苞
    const a = i / n * 6.28 + rnd() * .4, sp = .02 + rnd() * .03, h = .17 + rnd() * .07, tip = out(x, y, z, a, sp * 1.6, h);
    add(stem([V(x, y, z), out(x, y, z, a, sp * .6, h * .5), tip], .0022, .0015, { seg: 7, rad: 4, cap: false }), '#8a9a72');
    const dir = tip.clone().sub(out(x, y, z, a, sp * 1.3, h * .85)).normalize();
    for (let k = 0; k < 9; k++) {
      const t = k / 9, p = tip.clone().addScaledVector(dir, t * .05), b = k * 2.2;
      add(fruit(.0065 * (1 - t * .35), { sy: 1.3, lump: .15, seg: 8 }), st === 3 ? (k % 3 ? '#8b72c2' : '#a08ad3') : '#93a57f', { p: [p.x + Math.cos(b) * .004, p.y, p.z + Math.sin(b) * .004] });
    }
  }
}

function rose(add, x, y, z, rnd, st) {
  for (let i = 0; i < 4; i++) {   // 几根木质的枝，长着复叶
    const a = i * 1.6 + rnd(), h = .2 + rnd() * .08, tip = out(x, y, z, a, .04, h);
    add(stem([V(x, y, z), out(x, y, z, a, .015, h * .5), tip], .005, .0028, { seg: 6, rad: 4 }), '#5f6e3e');
    for (let k = 0; k < 2; k++) compound(add, [tip.x - Math.cos(a) * .02 * k, tip.y - .06 - k * .05, tip.z + Math.sin(a) * .02 * k], a + k * 2 + 1, .05, .015, { pairs: 1, lw: .032, ww: .024, shape: ROUND, rnd, col: C.leafD, wave: .3 });
    const bloom = add.mat([tip.x, tip.y + .006, tip.z], [(rnd() - .5) * .4, rnd() * 6, (rnd() - .5) * .4]);
    if (st === 3 && i < 3) {   // 玫瑰：一层层往里卷的花瓣，越里越紧、越深
      for (let ring = 0; ring < 4; ring++) {
        const n = 5 + ring, col = new THREE.Color('#c63a52').multiplyScalar(1 - ring * .08);
        for (let k = 0; k < n; k++) add(leaf({ len: .032 - ring * .005, wid: .036 - ring * .005, shape: PETAL, droop: -.25 + ring * .05, fold: .9, curl: 1.2 - ring * .2, segL: 5, segW: 2, seed: k }), col, { p: [0, ring * .002, 0], r: [0, k / n * 6.28 + ring * .6, 1.25 - ring * .3 + (3 - ring) * .05], parent: bloom, jit: .03 });
      }
    } else {   // 花苞：尖尖的，外面几片萼片
      add(fruit(.011, { sy: 1.6, point: -.3, lump: .05 }), st === 3 ? '#c63a52' : '#7e9a56', { p: [0, .01, 0], parent: bloom });
      for (let k = 0; k < 5; k++) add(leaf({ len: .016, wid: .006, droop: -.3, segL: 4, segW: 1 }), C.leafD, { r: [0, k / 5 * 6.28, 1.1], parent: bloom });
    }
  }
}

function carrot(add, x, y, z, rnd, st) {
  for (let i = 0; i < 6; i++) {   // 羽毛一样的细叶：叶柄弯出去，沿着长一对对很细的小叶
    const a = i / 6 * 6.28 + rnd() * .5, h = (st === 3 ? .14 : .1) * (.85 + rnd() * .3), tip = out(x, y, z, a, .05, h);
    const pts = [V(x, y, z), out(x, y, z, a, .012, h * .6), tip];
    add(stem(pts, .0025, .0012, { seg: 8, rad: 4 }), C.stem);
    const cv = new THREE.CatmullRomCurve3(pts);
    for (let k = 3; k <= 9; k++) { const p = cv.getPointAt(k / 10); for (const sd of [-1, 1]) add(leaf({ len: .022 * (1.2 - k / 12), wid: .01, wave: .7, waves: 4, droop: .2, fold: .3, segL: 5, segW: 1, seed: k }), k % 2 ? C.leaf : C.leafL, { p: [p.x, p.y, p.z], r: [0, a + sd * 1.0, .3] }); }
  }
  if (st === 3) add(fruit(.02, { sy: 1.5, lump: .06, dent: .1 }), '#e48a3e', { p: [x, y - .024, z], vcol: (v, c) => { if (Math.sin(v.y * 900) > .7) c.multiplyScalar(.88); } });   // 橙色的肩膀露出土
}

// 南瓜、西瓜：藤贴着地爬，长着带缺刻的大圆叶和卷须；熟了中间一个大果子
function vine(add, x, y, z, rnd, st, melon) {
  for (let i = 0; i < 3; i++) {
    const a = i / 3 * 6.28 + rnd() * .8, L = st === 3 ? .42 : .3, pts = [];
    for (let k = 0; k <= 5; k++) { const t = k / 5; pts.push(out(x, y + .012, z, a + Math.sin(t * 4 + i) * .35, L * t, Math.sin(t * Math.PI) * .01)); }
    add(stem(pts, .007, .004, { seg: 12, rad: 5 }), '#78904d');
    const cv = new THREE.CatmullRomCurve3(pts);
    for (let k = 1; k <= 3; k++) {
      const p = cv.getPointAt(k / 3.6), b = a + (k % 2 ? 1.3 : -1.3);
      const q = out(p.x, p.y, p.z, b, .025, .05);
      add(stem([p, out(p.x, p.y, p.z, b, .01, .04), q], .003, .0025, { seg: 5, rad: 4 }), C.stem);
      add(leaf({ len: melon ? .1 : .13, wid: melon ? .09 : .14, shape: melon ? LEAF : LOBED, droop: .15, fold: .2, wave: .5, waves: melon ? 9 : 5, segL: 7, segW: 3, seed: rnd() * 9 }), k % 2 ? C.leaf : C.leafD, { p: [q.x, q.y, q.z], r: [0, b, .35] });
      // 卷须：一圈圈的弹簧
      const tp = []; for (let m = 0; m <= 14; m++) { const t = m / 14; tp.push(V(p.x + Math.cos(t * 14) * .008 + t * .03 * Math.cos(b + 2), p.y + .005 + t * .03, p.z + Math.sin(t * 14) * .008 - t * .03 * Math.sin(b + 2))); }
      add(stem(tp, .0012, .0008, { seg: 20, rad: 3 }), '#93a868');
    }
  }
  if (st === 2) add(fruit(.03, { sy: .8, lump: .05 }), '#86a35a', { p: [x + .05, y + .02, z] });
  if (st === 2 && !melon) for (let k = 0; k < 5; k++) add(leaf({ len: .03, wid: .022, shape: PETAL, droop: -.4, fold: .5, segL: 5, segW: 2 }), '#f0b93a', { p: [x - .06, y + .03, z + .04], r: [0, k / 5 * 6.28, .9] });
  if (st !== 3) return;
  if (melon) {
    const seed = rnd() * 50 | 0;
    add(fruit(.15, { sx: 1.3, sy: .78, dent: .04, lump: .015, seed }), '#7fae6a', { p: [x, y + .11, z], r: [0, rnd() * 3, 0], vcol: (v, c) => { const th = Math.atan2(v.z, v.y); if (Math.sin(th * 9 + noise(v.x * 40, v.y * 40, v.z * 40, seed) * 2.2) > -.1) c.set('#2f5f36'); } });
  } else {
    add(fruit(.165, { sy: .66, lobes: 10, lobeAmp: .17, dent: .45, lump: .02, seed: rnd() * 50 | 0, seg: 40 }), '#d9773a', { p: [x, y + .105, z], vcol: (v, c) => { const th = Math.atan2(v.z, v.x); c.multiplyScalar(.74 + .26 * Math.pow(Math.abs(Math.cos(th * 5)), .35)); } });   // 一道道棱，棱沟里深一点
    add(stem([[x, y + .16, z], [x + .006, y + .2, z], [x + .025, y + .22, z + .005]], .014, .009, { seg: 6, rad: 6, knots: 1 }), '#6f5c3c');
  }
}

// 一格里种几棵、种在哪（三道垄在 .2 / .5 / .8）
const SPOTS = {
  six: [[.28, .2], [.72, .2], [.28, .5], [.72, .5], [.28, .8], [.72, .8]],
  three: [[.33, .2], [.67, .5], [.33, .8]],
  one: [[.5, .5]],
};
const SCALE = { strawberry: 1.2, carrot: 1.35, tomato: 1.35, cherrytomato: 1.35, sunflower: 1.15, lavender: 1.45, rose: 1.4, pumpkin: 1.2, watermelon: 1.2 };
export function cropCell(add, c, y, rnd) {
  const st = c.stage, k = c.kind;
  const spots = st < 2 ? SPOTS.six : (k === 'pumpkin' || k === 'watermelon') ? SPOTS.one : (k === 'strawberry' || k === 'carrot') ? SPOTS.six : SPOTS.three;
  for (const [dx, dz] of spots) {
    const x = c.x + dx + (rnd() - .5) * .06, z = c.y + dz + (rnd() - .5) * .04, yy = y + .06;
    // 长大了的整棵放大一点（绕着根）：一格田里要看着满
    const k2 = st < 2 ? 1.2 : (SCALE[k] || 1.3);
    add.pre = new THREE.Matrix4().makeTranslation(x, yy, z).multiply(new THREE.Matrix4().makeScale(k2, k2, k2)).multiply(new THREE.Matrix4().makeTranslation(-x, -yy, -z));
    if (st === 0) { mound(add, x, yy - .03, z, rnd); continue; }
    if (st === 1) { sprout(add, x, yy, z, rnd); continue; }
    switch (k) {
      case 'strawberry': strawberry(add, x, yy, z, rnd, st); break;
      case 'tomato': tomato(add, x, yy, z, rnd, st, false); break;
      case 'cherrytomato': tomato(add, x, yy, z, rnd, st, true); break;
      case 'sunflower': sunflower(add, x, yy, z, rnd, st); break;
      case 'lavender': lavender(add, x, yy, z, rnd, st); break;
      case 'rose': rose(add, x, yy, z, rnd, st); break;
      case 'carrot': carrot(add, x, yy, z, rnd, st); break;
      case 'pumpkin': vine(add, x, yy - .03, z, rnd, st, false); break;
      case 'watermelon': vine(add, x, yy - .03, z, rnd, st, true); break;
      default: strawberry(add, x, yy, z, rnd, st);
    }
  }
  add.pre = null;
}
