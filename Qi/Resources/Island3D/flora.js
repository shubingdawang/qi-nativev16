// 岛上的草木和石头：照真东西的样子捏（sculpt.js），不拿球、圆柱、方块直接拼。
// - 树：树干沿一条歪歪的曲线长、根部往外撑出几条根、几根枝伸进树冠；树冠是几团挤在一起的不规则叶团，底下暗、顶上亮，
//   果子带凹蒂，开花的树冠上点着五瓣小花、地上落着花瓣
// - 松树：一层层往下垂的裙边，边缘参差；柏树：细高的火苗形，表面一道道拧着的叶簇
// - 修剪过的绿篱、球形黄杨、棒棒糖树、圆锥树：形状规整，但表面是一簇簇叶子的起伏
// - 花：雏菊、毛茛、郁金香、三叶草、睡莲……花瓣、叶子都按轮廓长
// - 石头：劈开磨圆的样子，顶上长青苔；树桩带根、截面有年轮；蘑菇伞盖不正、带白点
import * as THREE from 'three';
import { bake, R, jit } from './kit.js';
import { P } from './models.js';
import { leaf as leafShape, stem, fruit, rock as rockGeo, canopy, leafy, pushN, deform, fbm, noise, LEAF, PETAL, BLADE } from './sculpt.js';
import { roseBloom, lavender as lavenderPlant, sunflower as sunflowerPlant } from './plants.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
// 叶子、花瓣只铺一层（那组材质两面都画）
const leaf = (o) => leafShape({ both: false, ...o });
const ROUND = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .8)), .75);
const HEART = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .6)), .8) * (1 + .3 * Math.sin(Math.PI * u * .9));
const HEDGE = '#4a6643', HEDGED = '#3f5a3b', HEDGEL = '#587650';

// 摆一块：相对这个景的中心（o.cx, o.t, o.cz）；叶子、花瓣进两面都画的那组
function putter(o, mat = 'foliage') {
  const put = (geo, color, opt = {}) => {
    const p = opt.p || [0, 0, 0];
    let matrix = opt.parent || null;
    if (put.pre) matrix = matrix ? put.pre.clone().multiply(matrix) : put.pre;
    return bake(geo, color, { line: 0, ...opt, mat: opt.mat || mat, matrix, ao: opt.ao === false ? null : o.t, p: [p[0], p[1], p[2]] });
  };
  put.pre = new THREE.Matrix4().makeTranslation(o.cx, o.t, o.cz);
  put.mat = (p, r = [0, 0, 0], s = 1) => new THREE.Matrix4().compose(V(...p), new THREE.Quaternion().setFromEuler(new THREE.Euler(...r)), V(s, s, s));
  return put;
}
// plants.js 那套（add(geo, color, {p, r, s, vcol, parent, jit})）接到这边：整棵挪到 (x, z)、放大 k 倍
function plantAdd(o, x, z, k = 1) {
  const put = putter(o);
  const add = (geo, color, opt = {}) => put(geo, opt.jit === 0 ? color : jit(color, opt.jit ?? .05), { p: opt.p, r: opt.r, s: opt.s, vcol: opt.vcol, parent: opt.parent && add.pre ? add.pre.clone().multiply(opt.parent) : (opt.parent || add.pre) });
  add.pre = new THREE.Matrix4().makeTranslation(x, 0, z).multiply(new THREE.Matrix4().makeScale(k, k, k));
  add.mat = put.mat;
  return add;
}
const rnd = () => R();
// 叶团的颜色：底下暗、顶上亮，再一块块深浅不一
const shade = (r, light, seed = 0) => (v, c) => {
  const t = Math.max(0, Math.min(1, (v.y / r + 1) / 2));
  c.multiplyScalar(.72 + .38 * t);
  const n = fbm(v.x * 4 / r, v.y * 4 / r, v.z * 4 / r, seed);
  if (n > .15) c.lerp(new THREE.Color(light), Math.min(.5, (n - .15) * 2));
};

// 叶团表面贴一层真叶子：在叶团表面随便取点，一片片叶子顺着表面朝外长、各自转个角度，轮廓就毛茸茸的不再是光溜溜一团
const UP = V(0, 1, 0);
function fringe(put, geo, at, n, { len = .08, wid = .055, shape = LEAF, colors = [P.leaf, P.leafD, P.leafL], droop = .25, s = [1, 1, 1] } = {}) {
  const pa = geo.attributes.position, na = geo.attributes.normal, q = new THREE.Quaternion(), q2 = new THREE.Quaternion(), m = new THREE.Matrix4(), p = V(0, 0, 0), nn = V(0, 0, 0);
  const shapes = [0, 1, 2].map((k) => leaf({ len, wid, shape, droop, fold: .35, segL: 3, segW: 1, seed: k }));
  for (let i = 0; i < n; i++) {
    const j = (R() * pa.count) | 0;
    p.fromBufferAttribute(pa, j); nn.fromBufferAttribute(na, j);
    if (nn.y < -.55 && R() < .7) continue;   // 底下少长点
    p.x *= s[0]; p.y *= s[1]; p.z *= s[2];
    // 叶尖大致顺着表面（随便哪个方向）、只往外斜出一点；叶根埋进叶团里一点，像是从里面长出来的
    const t = V(R() - .5, R() - .5, R() - .5).cross(nn).normalize(), dir = t.multiplyScalar(.85).addScaledVector(nn, .5).normalize();
    // 叶面朝外（叶子的 +y 尽量对着表面法线），再随便歪一点
    const yv = nn.clone().addScaledVector(dir, -nn.dot(dir)).normalize(), zv = dir.clone().cross(yv);
    m.makeBasis(dir, yv, zv); q2.setFromAxisAngle(V(1, 0, 0), (R() - .5) * 1.0);
    m.multiply(new THREE.Matrix4().makeRotationFromQuaternion(q2)).setPosition(p.clone().addScaledVector(nn, -len * .25).add(V(...at)));
    // 颜色：朝上的亮、朝下的暗（colors 从暗到亮排）
    const lv = Math.max(0, Math.min(colors.length - 1, Math.floor((nn.y * .5 + .5) * colors.length + (R() - .5) * 1.4)));
    put(shapes[i % 3], jit(colors[lv], .05).multiplyScalar(.8), { parent: m.clone(), ao: false });   // 叶面正对着天，会比叶团亮，压暗一点才跟叶团融在一起
  }
}

// ———————————————— 树 ————————————————
function trunk(put, h, { r0 = .085, lean = .06, seed = 0, color = P.trunk } = {}) {
  const a = R() * 6.28, lx = Math.cos(a) * lean, lz = Math.sin(a) * lean;
  const pts = [V(0, -.02, 0), V(lx * .2, h * .3, lz * .2), V(lx * .7 - lz * .3, h * .65, lz * .7 + lx * .3), V(lx, h, lz)];
  put(stem(pts, r0, r0 * .5, { seg: 14, rad: 9, knots: 2, seed }), color, { vcol: (v, c) => { if (noise(v.x * 60, v.y * 14, v.z * 60, seed) > .25) c.multiplyScalar(.85); } });
  for (let i = 0; i < 4; i++) {   // 根往外撑，钻进土里
    const b = i / 4 * 6.28 + R() * .6;
    put(stem([V(Math.cos(b) * r0 * .4, .12, Math.sin(b) * r0 * .4), V(Math.cos(b) * r0 * 1.4, .03, Math.sin(b) * r0 * 1.4), V(Math.cos(b) * r0 * 2.6, -.03, Math.sin(b) * r0 * 2.6)], r0 * .45, r0 * .15, { seg: 6, rad: 6, seed: i }), P.trunkD);
  }
  return V(lx, h, lz);
}
function branches(put, top, h, r, n = 4) {
  const ends = [];
  for (let i = 0; i < n; i++) {
    const b = i / n * 6.28 + R() * .8, y0 = h * (.6 + R() * .3), d = r * (.55 + R() * .25);
    const start = V(top.x * y0 / h, y0, top.z * y0 / h), end = V(Math.cos(b) * d, h + r * (.1 + R() * .3), Math.sin(b) * d);
    put(stem([start, start.clone().lerp(end, .5).add(V(0, .06, 0)), end], .032, .012, { seg: 8, rad: 6, seed: i }), P.trunk);
    ends.push(end);
  }
  return ends;
}
export function tree(o, { leaf: leafC = P.leaf, leafD = P.leafD, leafL = P.leafL, h = 1.0, r = .55, fruit: fruitC = null, petals = null, blossom = null } = {}) {
  const put = putter(o), seed = (R() * 999) | 0;
  const th = h * .7, top = trunk(put, th, { seed });
  const ends = branches(put, top, th, r, 3);
  // 树冠：主冠一大团 + 每根枝头一小团，挤在一起成一个不规则的轮廓
  const cy = th + r * .55;
  const main = canopy(r * .95, { blobs: 7, seed, sy: .82, rough: .22 });
  put(main, jit(leafD, .03), { p: [top.x, cy, top.z], vcol: shade(r, leafL, seed) });
  const mid = new THREE.Color(leafD).lerp(new THREE.Color(leafC), .5), hi = new THREE.Color(leafC).lerp(new THREE.Color(leafL), .45);
  fringe(put, main, [top.x, cy, top.z], 520, { len: r * .2, wid: r * .14, colors: [leafD, mid, leafC, hi] });
  ends.slice(0, 3).forEach((e, i) => {
    const g = canopy(r * (.42 + R() * .12), { blobs: 4, seed: seed + i + 1, sy: .85, detail: 2 }), at = [e.x * 1.05, e.y + r * .05, e.z * 1.05];
    put(g, jit(i % 2 ? leafC : leafD, .04), { p: at, vcol: shade(r * .45, leafL, seed + i) });
    fringe(put, g, at, 140, { len: r * .19, wid: r * .13, colors: [leafD, mid, leafC, hi] });
  });
  const surf = (lo = -.1, hi = .8) => {   // 树冠表面上随便一点
    const a = R() * 6.28, y = lo + R() * (hi - lo), k = Math.sqrt(1 - y * y);
    return V(top.x + Math.cos(a) * k * r * 1.02, cy + y * r * .85, top.z + Math.sin(a) * k * r * 1.02);
  };
  if (fruitC) for (let i = 0; i < 10; i++) {   // 果子：凹蒂、短柄，一个个挂在树冠外沿
    const p = surf(-.5, .5);
    put(fruit(.05, { sy: .9, dent: .3, lump: .03, seed: i }), jit(fruitC, .06), { p: [p.x, p.y - .03, p.z], mat: 'base', vcol: (v, c) => { if (v.x > .02) c.lerp(new THREE.Color('#e9c46a'), .25); } });
    put(stem([[p.x, p.y + .015, p.z], [p.x + .01, p.y + .04, p.z]], .005, .004, { seg: 2, rad: 4 }), P.trunkD);
  }
  if (blossom) for (let i = 0; i < 26; i++) {   // 五瓣小花点在树冠上
    const p = surf(-.2, .9), m = put.mat([p.x, p.y, p.z], [R() - .5, R() * 6, R() - .5]);
    for (let k = 0; k < 5; k++) put(leaf({ len: .035, wid: .03, shape: ROUND, droop: -.1, fold: .2, segL: 4, segW: 1 }), blossom, { r: [0, k / 5 * 6.28, .2], parent: m });
    put(fruit(.008, { lump: .1 }), '#e9c46a', { parent: m, p: [0, .006, 0] });
  }
  if (petals) for (let i = 0; i < 18; i++) {   // 落在地上的花瓣，卷着边
    const a = R() * 6.28, d = .25 + R() * r * 1.3;
    put(leaf({ len: .04, wid: .03, shape: PETAL, droop: -.2, fold: .4, curl: .5, segL: 4, segW: 1, seed: i }), jit(petals, .08), { p: [Math.cos(a) * d, .012, Math.sin(a) * d], r: [0, R() * 6, 0], ao: false });
  }
}

// 松树：一层层往下垂的针叶裙，边缘参差不齐，越往上越小
function skirt(R0, h, seed) {
  const seg = 28, rings = 5, pos = [], idx = [];
  for (let j = 0; j <= rings; j++) for (let i = 0; i < seg; i++) {
    const t = j / rings, a = i / seg * Math.PI * 2;
    const jag = 1 + .2 * Math.sin(a * 9 + seed) * t + noise(Math.cos(a) * 3, Math.sin(a) * 3, t * 2, seed) * .15 * t;
    const r = R0 * t * jag, y = h * (1 - t) - h * .35 * t * t + noise(Math.cos(a) * 4, t * 3, Math.sin(a) * 4, seed + 2) * .03;
    pos.push(Math.cos(a) * r, y, Math.sin(a) * r);
  }
  for (let j = 0; j < rings; j++) for (let i = 0; i < seg; i++) { const a = j * seg + i, b = j * seg + (i + 1) % seg, c = a + seg, d = b + seg; idx.push(a, c, b, b, c, d); }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
  return g;
}
export function pine(o, s = 1) {
  const put = putter(o), seed = (R() * 999) | 0;
  trunk(put, .55 * s, { r0: .06 * s, lean: .02, seed });
  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const k = 1 - i / tiers;
    put(skirt(.5 * s * (.3 + .7 * k), .36 * s, seed + i), jit([P.pineD, P.pine, P.pineL][i % 3], .03), { p: [0, (.32 + i * .21) * s, 0], r: [0, R() * 3, 0], vcol: (v, c) => c.multiplyScalar(.75 + .45 * Math.min(1, Math.max(0, v.y / (.36 * s)))) });
  }
  put(stem([[0, (.32 + tiers * .21) * s, 0], [.01, (.32 + tiers * .21) * s + .16 * s, 0]], .03 * s, .004, { seg: 4, rad: 6 }), P.pineL);
  for (let i = 0; i < 8; i++) { const a = R() * 6.28, d = .2 + R() * .35; put(stem([[Math.cos(a) * d, .01, Math.sin(a) * d], [Math.cos(a) * d + .05, .012, Math.sin(a) * d + .02]], .004, .002, { seg: 2, rad: 3 }), P.trunkD, { ao: false }); }
}
// 意大利柏树：细高的火苗形，一簇簇叶子拧着往上
export function cypress(o, s = 1) {
  const put = putter(o), seed = (R() * 999) | 0, H = 1.9 * s, W = .27 * s;
  trunk(put, .3, { r0: .045, lean: .01, seed });
  let g = new THREE.SphereGeometry(1, 24, 32);
  g = pushN(g, () => 0);
  const pa = g.attributes.position;
  for (let i = 0; i < pa.count; i++) {
    const x = pa.getX(i), y = pa.getY(i), z = pa.getZ(i), t = (y + 1) / 2;
    const prof = Math.pow(Math.sin(Math.PI * Math.pow(t, .62)), .9) * (1 - t * .25);
    const ang = Math.atan2(z, x) + t * 1.4, tuft = 1 + .1 * Math.sin(ang * 7 + t * 20) + fbm(x * 3, t * 9, z * 3, seed) * .18;
    pa.setXYZ(i, x * W * prof * tuft, t * H, z * W * prof * tuft);
  }
  g.computeVertexNormals();
  put(g, jit('#5f7f5a', .04), { p: [0, .18, 0], vcol: (v, c) => { c.multiplyScalar(.75 + .4 * (v.y / H)); if (noise(v.x * 20, v.y * 8, v.z * 20, seed) > .3) c.lerp(new THREE.Color('#7a9a70'), .4); } });
}

// ———————————————— 修剪过的造型树：形状规整，表面一簇簇叶子 ————————————————
const clipped = (geo, amp = .018, seed = 0) => leafy(geo, amp, 16, seed);
const leafCol = (h, seed) => (v, c) => { c.multiplyScalar(.8 + .3 * Math.min(1, Math.max(0, v.y / h + .5))); if (noise(v.x * 30, v.y * 30, v.z * 30, seed) > .35) c.lerp(new THREE.Color(HEDGEL), .45); };
export function hedge(o, d) {
  const put = putter(o), w = Math.max(.9, d.w * .85), seed = (R() * 999) | 0;
  // 一段密的方块先把棱角磨圆（修剪过的绿篱棱是圆的），再在表面起一簇簇叶子
  const g = new THREE.BoxGeometry(w, .42, .42, Math.round(w * 22), 10, 10), half = [w / 2, .21, .21], rr = .08, q = new THREE.Vector3();
  deform(g, (v) => { q.set(Math.max(-half[0] + rr, Math.min(half[0] - rr, v.x)), Math.max(-half[1] + rr, Math.min(half[1] - rr, v.y)), Math.max(-half[2] + rr, Math.min(half[2] - rr, v.z))); const d = v.clone().sub(q); if (d.lengthSq() > 1e-9) v.copy(q.add(d.normalize().multiplyScalar(rr))); });
  const cg = clipped(g, .02, seed);
  put(cg, HEDGED, { p: [0, .21, 0], vcol: leafCol(.42, seed) });
  fringe(put, cg, [0, .21, 0], Math.round(110 * w), { len: .035, wid: .022, droop: .1, colors: [HEDGE, HEDGEL, HEDGED] });
}
export function boxBall(o) {
  const put = putter(o), seed = (R() * 999) | 0;
  put(new THREE.LatheGeometry([[0, 0], [.13, 0], [.15, .04], [.12, .16], [.14, .18], [0, .18]].map(([x, y]) => new THREE.Vector2(x, y)), 24), '#cfc6b8', { mat: 'base' });
  const g = clipped(new THREE.IcosahedronGeometry(.24, 4), .018, seed);
  put(g, HEDGE, { p: [0, .4, 0], vcol: leafCol(.24, seed) });
  fringe(put, g, [0, .4, 0], 90, { len: .035, wid: .022, droop: .1, colors: [HEDGE, HEDGEL, HEDGED] });
}
export function lollipop(o, s = 1) {
  const put = putter(o), seed = (R() * 999) | 0;
  put(stem([[0, -.02, 0], [.01, .35 * s, 0], [0, .7 * s, 0]], .04, .03, { seg: 6, rad: 8, seed }), P.trunk);
  const g = clipped(new THREE.IcosahedronGeometry(.3 * s, 4), .022, seed);
  put(g, HEDGE, { p: [0, .82 * s, 0], vcol: leafCol(.3 * s, seed) });
  fringe(put, g, [0, .82 * s, 0], 110, { len: .04, wid: .025, droop: .1, colors: [HEDGE, HEDGEL, HEDGED] });
  put(clipped(new THREE.TorusGeometry(.16, .065, 10, 32), .015, seed + 1), HEDGED, { p: [0, .05, 0], r: [Math.PI / 2, 0, 0], vcol: leafCol(.1, seed) });
}
export function coneTopiary(o, s = 1, tiers = false) {
  const put = putter(o), seed = (R() * 999) | 0;
  put(new THREE.LatheGeometry([[0, 0], [.15, 0], [.17, .05], [.13, .18], [.16, .2], [0, .2]].map(([x, y]) => new THREE.Vector2(x, y)), 24), '#cfc6b8', { mat: 'base' });
  if (tiers) for (let i = 0; i < 3; i++) { const r = .22 * s * (1 - i * .25); put(clipped(new THREE.IcosahedronGeometry(r, 3), .016, seed + i), jit(HEDGE, .03), { p: [0, .32 + i * .3 * s, 0], s: [1, .78, 1], vcol: leafCol(r, seed) }); }
  else {
    // 圆锥：底下圆润、顶上一个软尖，表面一簇簇叶子
    const pts = []; for (let i = 0; i <= 16; i++) { const t = i / 16; pts.push(new THREE.Vector2(.27 * s * Math.pow(1 - t, .9) * (1 - .6 * Math.pow(1 - t, 8)) + .001, t * 1.02 * s)); }
    const g = clipped(new THREE.LatheGeometry(pts, 32), .018, seed);
    put(g, HEDGE, { p: [0, .2, 0], vcol: leafCol(1 * s, seed) });
    fringe(put, g, [0, .2, 0], 110, { len: .035, wid: .022, droop: .1, colors: [HEDGE, HEDGEL, HEDGED] });
  }
}
// 玫瑰丛：一团深绿的叶子，外沿开着一朵朵卷瓣的玫瑰，还有几个花苞
export function roseBush(o) {
  const put = putter(o), seed = (R() * 999) | 0;
  const g = canopy(.3, { blobs: 6, seed, sy: .8, rough: .25, detail: 2 });
  put(g, jit(P.leafD, .04), { p: [0, .26, 0], vcol: shade(.3, P.leaf, seed) });
  fringe(put, g, [0, .26, 0], 170, { len: .06, wid: .045, shape: ROUND, colors: ['#556f40', P.leafD, P.leaf] });
  for (let i = 0; i < 6; i++) {
    const a = R() * 6.28, y = (R() - .2) * .5, k = Math.sqrt(1 - y * y), p = [Math.cos(a) * k * .33, .26 + y * .25, Math.sin(a) * k * .3];
    const col = R() < .5 ? '#d98f98' : '#eec2c6';
    roseBloom(put, put.mat(p, [(R() - .5) * .5, -a, -(Math.PI / 2 - .5 - y)], 1.5), col, false, true);   // 花朝外
  }
}
// 自然长的灌木：一团团叶子，底下暗；结果的那种挂着小浆果
export function bush(o, { berry = false } = {}) {
  const put = putter(o), seed = (R() * 999) | 0;
  const g = canopy(.32, { blobs: 6, seed, sy: .72, rough: .24, detail: 2 });
  put(g, jit(P.leafD, .04), { p: [0, .22, 0], vcol: shade(.32, P.leafL, seed) });
  fringe(put, g, [0, .22, 0], 230, { len: .065, wid: .045, colors: [P.leafD, P.leafD, P.leaf] });
  if (berry) for (let i = 0; i < 18; i++) { const a = R() * 6.28, y = R() * .6, k = Math.sqrt(1 - y * y); put(fruit(.022, { lump: .05, dent: .1, seed: i }), jit(P.berry, .08), { p: [Math.cos(a) * k * .34, .22 + y * .22, Math.sin(a) * k * .32], mat: 'base' }); }
}

// ———————————————— 花 ————————————————
// 一枝花：茎弯一点，底下几片叶子，顶上一朵（head 决定花的样子）
function flower(put, x, z, h, head, { leaves = 2, leafLen = .07, blade = false } = {}) {
  const lean = (R() - .5) * .05, top = V(x + lean, h, z + (R() - .5) * .03);
  put(stem([V(x, 0, z), V(x + lean * .2, h * .5, z), top], .006, .004, { seg: 6, rad: 4 }), P.leafD);
  for (let i = 0; i < leaves; i++) put(leaf({ len: leafLen, wid: blade ? .028 : .035, shape: blade ? LEAF : ROUND, droop: .3, fold: .45, segL: 6, segW: 2, seed: i }), jit(P.leaf, .06), { p: [x, .01 + i * .03, z], r: [0, R() * 6.28, blade ? 1.0 : .5] });
  head(put.mat([top.x, top.y, top.z], [(R() - .5) * .4, R() * 6, (R() - .5) * .4]));
}
const daisyHead = (put) => (m) => {
  for (let k = 0; k < 10; k++) put(leaf({ len: .045, wid: .015, shape: PETAL, droop: .1, fold: .25, segL: 3, segW: 1, seed: k }), jit(P.white, .03), { r: [0, k / 10 * 6.28, .05], parent: m });
  put(fruit(.016, { sy: .55, dent: -.2, lump: .1 }), '#e8c34a', { parent: m, p: [0, .004, 0] });
};
const cupHead = (put, col) => (m) => {   // 五瓣小圆花（毛茛、小黄花）：花瓣往上兜
  for (let k = 0; k < 5; k++) put(leaf({ len: .035, wid: .032, shape: ROUND, droop: -.15, fold: .45, segL: 4, segW: 2, seed: k }), jit(col, .04), { r: [0, k / 5 * 6.28, .5], parent: m });
  put(fruit(.008, { lump: .15 }), '#f2e2a0', { parent: m, p: [0, .008, 0] });
};
const tulipHead = (put, col) => (m) => {   // 郁金香：六片花瓣立起来围成一个杯子，瓣尖往外翻一点
  for (let k = 0; k < 6; k++) put(leaf({ len: .06, wid: .04, shape: PETAL, droop: -.25, fold: .7, curl: .5, segL: 6, segW: 2, seed: k }), new THREE.Color(col).multiplyScalar(k % 2 ? 1 : .9), { r: [0, k / 6 * 6.28 + (k % 2) * .5, 1.3 - (k % 2) * .12], parent: m, p: [0, -.004, 0] });
};
export function flowerPatch(o, petal, { n = 5, stem: h0 = .2, shape = 'round' } = {}) {
  const put = putter(o);
  for (let i = 0; i < n; i++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5, h = h0 * (.8 + R() * .4);
    if (shape === 'daisy') flower(put, x, z, h, daisyHead(put), { leaves: 3, leafLen: .06 });
    else if (shape === 'tulip') flower(put, x, z, h * 1.2, tulipHead(put, petal), { leaves: 2, leafLen: .14, blade: true });
    else flower(put, x, z, h, cupHead(put, petal), { leaves: 2 });
  }
}
// 三叶草：一片片心形的三出叶贴着地，中间冒几个粉色的小绒球
export function clover(o, lite = false) {
  const put = putter(o);
  for (let i = 0; i < (lite ? 5 : 12); i++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5, h = .025 + R() * .03, a0 = R() * 6;
    put(stem([[x, 0, z], [x, h, z]], .003, .002, { seg: 2, rad: 3 }), P.leafD);
    for (let k = 0; k < 3; k++) put(leaf({ len: .03, wid: .03, shape: HEART, droop: .1, fold: .35, segL: lite ? 2 : 4, segW: 1, seed: k }), jit(P.leaf, .06), { p: [x, h, z], r: [0, a0 + k / 3 * 6.28, .2] });
    if (i % 3 === 0) { const t = [x + .01, .09 + R() * .03, z]; put(stem([[x, 0, z], t], .003, .0025, { seg: 3, rad: 3 }), P.leafD); put(fruit(.022, { sy: 1.1, lump: .25, seed: i, seg: lite ? 7 : 10 }), jit(P.pink, .06), { p: t, vcol: (v, c) => c.multiplyScalar(.8 + .3 * (v.y / .022 + 1) / 2) }); }
  }
}
export function lavender(o) {
  for (let i = 0; i < 2; i++) { const add = plantAdd(o, (i - .5) * .3 + (R() - .5) * .1, (R() - .5) * .25, 1.8 + R() * .3); lavenderPlant(add, 0, 0, 0, rnd, 3); }
}
export function sunflower(o) {
  const add = plantAdd(o, 0, 0, 1.25); sunflowerPlant(add, 0, 0, 0, rnd, 3);
}
// 睡莲：圆叶子平铺在水上（带一道缺口、边微微翘），一朵粉色的花一层层张开
export function lily(o) {
  const put = putter(o);
  for (let i = 0; i < 3; i++) {
    const r = .12 + R() * .04, seg = 28, pos = [0, 0, 0], idx = [];
    for (let k = 0; k <= seg; k++) { const a = .12 + k / seg * (Math.PI * 2 - .24); pos.push(Math.cos(a) * r, .008 * Math.sin(a * 5) + .006, Math.sin(a) * r); }
    for (let k = 1; k <= seg; k++) idx.push(0, k + 1, k);
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    put(g, jit(P.leaf, .06), { p: [(R() - .5) * .5, .012, (R() - .5) * .4], r: [0, R() * 6, 0], ao: false });
  }
  const m = put.mat([.05, .03, 0]);
  for (let ring = 0; ring < 3; ring++) for (let k = 0; k < 8; k++) put(leaf({ len: .06 - ring * .012, wid: .025, shape: PETAL, droop: -.2, fold: .5, segL: 5, segW: 1, seed: k }), ring ? P.pinkL : P.pink, { r: [0, k / 8 * 6.28 + ring * .4, .25 + ring * .4], parent: m, ao: false });
  put(fruit(.012, { lump: .1 }), P.yellow, { parent: m, p: [0, .015, 0], ao: false });
}

// ———————————————— 石头、树桩、蘑菇 ————————————————
const mossy = (r, seed) => (v, c) => { const top = v.y / r; const n = fbm(v.x * 6 / r, v.y * 6 / r, v.z * 6 / r, seed); if (top + n * .6 > .55) c.lerp(new THREE.Color(P.moss), .75); else c.multiplyScalar(.9 + n * .2); };
export function rock(o, s = 1, n = 1) {
  const put = putter(o, 'base');
  for (let i = 0; i < n; i++) {
    const rr = .24 * s * (1 - i * .22), x = (i - (n - 1) / 2) * .32 * s, z = (R() - .5) * .18, seed = (R() * 999) | 0;
    put(rockGeo(rr, { flat: .62, seed, rough: .26 }), jit(i % 2 ? P.rockD : P.rock, .05), { p: [x, rr * .2, z], r: [0, R() * 3, 0], vcol: mossy(rr * .62, seed) });
  }
  for (let i = 0; i < 4; i++) put(rockGeo(.035 * s, { seed: i + 7, flat: .5, detail: 1 }), P.rockD, { p: [(R() - .5) * .7 * s, .008, (R() - .5) * .4] });
}
export function stump(o) {
  const put = putter(o, 'base'), seed = (R() * 999) | 0;
  put(stem([[0, -.02, 0], [.01, .12, 0], [0, .24, 0]], .21, .19, { seg: 6, rad: 18, seed, cap: false, bulge: -.05 }), P.trunk, { vcol: (v, c) => { if (Math.sin(Math.atan2(v.z, v.x) * 14 + noise(v.x * 9, v.y * 9, v.z * 9, seed) * 3) > .3) c.multiplyScalar(.82); } });
  for (let i = 0; i < 5; i++) { const b = i / 5 * 6.28 + R() * .5; put(stem([[Math.cos(b) * .15, .1, Math.sin(b) * .15], [Math.cos(b) * .27, .02, Math.sin(b) * .27], [Math.cos(b) * .38, -.03, Math.sin(b) * .38]], .07, .02, { seg: 6, rad: 7, seed: i }), P.trunkD); }
  // 截面：浅色的木头，一圈圈年轮，中间裂一道缝
  const top = new THREE.CircleGeometry(.195, 40, 0, Math.PI * 2); top.rotateX(-Math.PI / 2);
  put(top, P.woodL, { p: [0, .24, 0], vcol: (v, c) => { const r = Math.hypot(v.x, v.z) + noise(v.x * 20, 0, v.z * 20, seed) * .012; if (Math.sin(r * 160) > .55) c.multiplyScalar(.82); if (r > .175) c.set(P.trunkD); if (Math.abs(v.z + v.x * .3) < .004 && r < .12) c.multiplyScalar(.6); } });
  for (const [x, z, k] of [[.24, .12, 1], [.29, .03, .7], [-.22, .18, .8]]) mushroom(put, x, z, k * .55, '#d48a7c');
}
function mushroom(put, x, z, s, col, lite = false) {
  const SEG = lite ? 12 : 28;
  const seed = (R() * 999) | 0, h = .16 * s, lean = (R() - .5) * .04;
  put(stem([[x, -.01, z], [x + lean * .3, h * .5, z], [x + lean, h, z]], .028 * s, .02 * s, { seg: lite ? 3 : 5, rad: lite ? 6 : 10, seed, bulge: .15, cap: false }), '#efe6d6');
  // 伞盖：边缘往下包、不是正圆，表面几块白斑
  const NR = lite ? 6 : 12, pts = []; for (let i = 0; i <= NR; i++) { const t = i / NR, a = t * Math.PI * .55; pts.push(new THREE.Vector2(Math.sin(a) * .11 * s * (1 + .12 * Math.pow(t, 6)), Math.cos(a) * .07 * s - .02 * s * Math.pow(t, 4))); }
  let cap = new THREE.LatheGeometry(pts.reverse(), SEG);
  cap = pushN(cap, (v) => fbm(v.x * 30 / s, v.y * 30 / s, v.z * 30 / s, seed) * .008 * s);
  put(cap, col, { p: [x + lean, h - .01 * s, z], r: [(R() - .5) * .3, 0, (R() - .5) * .3], vcol: (v, c) => { if (noise(v.x * 90 / s, v.y * 90 / s, v.z * 90 / s, seed) > .42 && v.y > .02 * s) c.set('#f6efe2'); } });
  // 伞盖底下的菌褶
  const gill = new THREE.CircleGeometry(.105 * s, SEG); gill.rotateX(Math.PI / 2);
  put(gill, '#e6d2b8', { p: [x + lean, h - .012 * s, z], vcol: (v, c) => { if (Math.sin(Math.atan2(v.z, v.x) * 30) > .4) c.multiplyScalar(.85); } });
}
export function mushrooms(o) {
  const put = putter(o, 'base');
  for (const [x, z, s, c] of [[0, 0, 1, '#c8584a'], [.16, .1, .65, '#c8584a'], [-.14, .12, .55, '#e0a75e'], [.05, -.16, .45, '#c8584a']]) mushroom(put, x, z, s, c);
  for (let k = 0; k < 6; k++) put(leaf({ len: .07, wid: .03, droop: .3, fold: .4, segL: 5, segW: 1, seed: k }), jit(P.leaf, .06), { p: [(R() - .5) * .4, .01, (R() - .5) * .4], r: [0, R() * 6, .3], mat: 'foliage' });
}

// ———————————————— 空地上自己长的（数量多，做得省一点） ————————————————
// 野花：一两枝，茎、两片叶、一朵小花（五瓣或雏菊）
export function wildFlower(o, petal, daisy = false) {
  const put = putter(o), n = 1 + ((R() * 3) | 0);
  for (let i = 0; i < n; i++) {
    const x = (R() - .5) * .4, z = (R() - .5) * .35, h = .1 + R() * .1, lean = (R() - .5) * .04, top = V(x + lean, h, z);
    put(stem([V(x, 0, z), V(x + lean * .3, h * .5, z), top], .005, .0035, { seg: 4, rad: 3 }), P.leafD);
    for (let k = 0; k < 2; k++) put(leaf({ len: .05, wid: .025, droop: .3, fold: .4, segL: 3, segW: 1, seed: k }), jit(P.leaf, .06), { p: [x, .01, z], r: [0, R() * 6.28, .6] });
    const m = put.mat([top.x, top.y, top.z], [(R() - .5) * .4, R() * 6, (R() - .5) * .4]);
    const np = daisy ? 8 : 5;
    for (let k = 0; k < np; k++) put(leaf({ len: daisy ? .035 : .028, wid: daisy ? .012 : .026, shape: daisy ? PETAL : ROUND, droop: daisy ? .08 : -.12, fold: .35, segL: 2, segW: 1, seed: k }), jit(daisy ? P.white : petal, .04), { r: [0, k / np * 6.28, daisy ? .05 : .45], parent: m });
    put(fruit(.008, { lump: .1, seg: 5 }), daisy ? '#e8c34a' : '#f2e2a0', { parent: m, p: [0, .005, 0] });
  }
}
// 野薰衣草：几支细茎顶着紫穗
export function wildLavender(o) {
  const put = putter(o);
  for (let i = 0; i < 6; i++) {
    const a = R() * 6.28, d = R() * .06, h = .2 + R() * .1, tip = V(Math.cos(a) * (d + .05), h, Math.sin(a) * (d + .05));
    put(stem([V(Math.cos(a) * d, 0, Math.sin(a) * d), V(Math.cos(a) * (d + .02), h * .5, Math.sin(a) * (d + .02)), tip], .003, .002, { seg: 4, rad: 3, cap: false }), '#8a9a72');
    put(fruit(.011, { sy: 3.2, point: .3, lump: .35, seg: 6, seed: i }), jit(P.lav, .06), { p: [tip.x, tip.y + .03, tip.z], vcol: (v, c) => { if (Math.sin(v.y * 380) > .2) c.multiplyScalar(1.15); } });
  }
}
// 蕨草：几片羽状的长叶从中间散开、往下弯
export function fern(o) {
  const put = putter(o), n = 5 + ((R() * 3) | 0);
  for (let i = 0; i < n; i++) {
    const a = i / n * 6.28 + R() * .4, L = .2 + R() * .08, tip = V(Math.cos(a) * L, .12 + R() * .05, Math.sin(a) * L);
    const pts = [V(0, 0, 0), V(Math.cos(a) * L * .4, tip.y * 1.1, Math.sin(a) * L * .4), tip.clone().setY(tip.y * .5)];
    put(stem(pts, .004, .0015, { seg: 5, rad: 3 }), '#6f9058');
    const cv = new THREE.CatmullRomCurve3(pts);
    for (let k = 2; k <= 8; k++) { const p = cv.getPointAt(k / 9); for (const sd of [-1, 1]) put(leaf({ len: .045 * (1.1 - k / 10), wid: .014, droop: .25, fold: .3, segL: 2, segW: 1, seed: k }), jit('#6f9058', .06), { p: [p.x, p.y, p.z], r: [0, -a + sd * 1.3, -.2] }); }
  }
}
// 一簇小蘑菇
export function wildMushrooms(o) {
  const put = putter(o, 'base');
  for (let i = 0; i < 2 + ((R() * 2) | 0); i++) mushroom(put, (R() - .5) * .3, (R() - .5) * .3, .35 + R() * .3, R() < .5 ? '#c8584a' : '#e0a75e', true);
}
// 小石子
export function pebbles(o) {
  const put = putter(o, 'base');
  for (let i = 0; i < 3; i++) { const r = .035 + R() * .035; put(rockGeo(r, { seed: (R() * 99) | 0, flat: .55, detail: 1 }), jit(P.rock, .06), { p: [(R() - .5) * .4, r * .1, (R() - .5) * .4], r: [0, R() * 6, 0] }); }
}
