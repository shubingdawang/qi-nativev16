// 岛上每一样景的模型。原点是占地底边的中点，y 是地面，脸朝 +z（地图往下）
import * as THREE from 'three';
import { bake, R, jit, box, cyl, cone, ball, torus, disc, blob, jag, lathe, tri3 } from './kit.js';

export const P = {
  paper: '#efdcc0', sky: '#9db4cb', mount: '#9aa7ae',
  grass: '#94a872', grassD: '#7d9260', grassL: '#a6b884', flowers: '#9caf78', path: '#dcd4c6', slab: '#e6dccb', sand: '#eadcbc', soil: '#a88566', soilL: '#b8957a',
  stone: '#d4cbbd', wood: '#b38b66', water: '#93b9cf', sea: '#7f9fb0', seaD: '#5d7f93', cliff: '#b09074', cliffD: '#8f735c', rockC: '#9d958a',
  leaf: '#8fae74', leafD: '#76955e', leafL: '#aec78f', pink: '#efc3c4', pinkD: '#e1a5aa', pinkL: '#f7dcdb', autumn: '#e2ab6c', autumnD: '#cc8b52', autumnL: '#efc48c',
  pine: '#6f8f68', pineD: '#5a7954', pineL: '#86a37c', trunk: '#8a6a50', trunkD: '#6f533e',
  cream: '#efe5d6', creamD: '#e2d4bf', terra: '#c9846a', terraD: '#b06f58', roofBlue: '#8fa3b8', roofBlueD: '#7a8fa5', roofGreen: '#9aae8a', roofGreenD: '#86997a',
  trim: '#f7f1e8', door: '#8c6248', glass: '#bcd2db', ink: '#5a4436', beam: '#7e5f49', brick: '#b97a64', curtain: '#efd2c6',
  rock: '#bdb5a8', rockD: '#a39b8f', moss: '#9cb27e', woodL: '#c9a37e', woodD: '#94704f', metal: '#6f7275', lamp: '#f6dc9e',
  red: '#d98b84', yellow: '#ecd37f', white: '#f8f4ec', lav: '#a69ac4', lavD: '#8f82b2', peach: '#efb995', berry: '#b9677a', apple: '#d7766c',
};

// 以景的原点为准摆一块
const putter = (o) => (geo, color, opt = {}) => {
  const p = opt.p || [0, 0, 0];
  return bake(geo, color, { ...opt, ao: opt.ao === false ? null : o.t, p: [o.cx + p[0], o.t + p[1], o.cz + p[2]] });
};

// ———————————————— 树 ————————————————
export function tree(o, { leaf = P.leaf, leafD = P.leafD, leafL = P.leafL, h = 1.0, r = .55, fruit = null, petals = null, blossom = null } = {}) {
  const put = putter(o);
  const th = h * .62;
  put(cyl(.065, .1, th, 9), P.trunk, { p: [0, th / 2, 0], r: [0, 0, (R() - .5) * .08] });
  for (let i = 0; i < 3; i++) {   // 根
    const a = i / 3 * 6.28 + R();
    put(cone(.05, .16, 6), P.trunkD, { p: [Math.cos(a) * .08, .04, Math.sin(a) * .08], r: [Math.sin(a) * 1.2, 0, -Math.cos(a) * 1.2], line: .008 });
  }
  for (const [a, y, l] of [[.4, .75, .32], [2.6, .62, .28], [4.4, .82, .25]]) {   // 枝
    put(cyl(.022, .035, l, 6), P.trunk, { p: [Math.cos(a) * l * .35, th * y + l * .3, Math.sin(a) * l * .35], r: [Math.sin(a) * .9, 0, -Math.cos(a) * .9], line: .008 });
  }
  // 树冠：中间一大团，四周一圈小团，顶上几团亮一点的
  put(blob(r * .82, 2), jit(leafD, .03), { p: [0, h * .9, 0] });
  const n = 7;
  for (let i = 0; i < n; i++) {
    const a = i / n * 6.28 + R() * .5, rr = r * (.42 + R() * .15), d = r * .62;
    put(blob(rr, 1), jit(i % 2 ? leaf : leafD, .04), { p: [Math.cos(a) * d, h * (.72 + R() * .2), Math.sin(a) * d] });
  }
  for (let i = 0; i < 3; i++) {
    const a = i / 3 * 6.28 + 1, d = r * .3;
    put(blob(r * (.36 + R() * .1), 1), jit(leafL, .03), { p: [Math.cos(a) * d, h * 1.15 + R() * .06, Math.sin(a) * d] });
  }
  if (fruit) for (let i = 0; i < 9; i++) {
    const a = R() * 6.28, yy = h * (.7 + R() * .45), d = r * (.8 + R() * .15);
    put(ball(.05, 8, 6), jit(fruit, .05), { p: [Math.cos(a) * d, yy, Math.sin(a) * d], line: .007 });
    put(cyl(.006, .006, .04, 4), P.trunkD, { p: [Math.cos(a) * d, yy + .05, Math.sin(a) * d], line: 0 });
  }
  if (blossom) for (let i = 0; i < 16; i++) {
    const a = R() * 6.28, yy = h * (.75 + R() * .5), d = r * (.85 + R() * .2);
    put(ball(.03, 6, 4), blossom, { p: [Math.cos(a) * d, yy, Math.sin(a) * d], line: 0 });
  }
  if (petals) for (let i = 0; i < 14; i++) {   // 落在地上的花瓣 / 叶子
    const a = R() * 6.28, d = .2 + R() * r * 1.3;
    put(box(.06, .008, .04), jit(petals, .06), { p: [Math.cos(a) * d, .01, Math.sin(a) * d], r: [0, R() * 3, 0], line: 0, ao: false });
  }
}

export function pine(o, s = 1) {
  const put = putter(o);
  put(cyl(.05, .08, .4 * s, 8), P.trunk, { p: [0, .2 * s, 0] });
  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const k = 1 - i / tiers;
    put(jag(.46 * s * (.35 + .65 * k), .42 * s, 12), jit([P.pineD, P.pine, P.pineL][i % 3], .03), { p: [0, (.42 + i * .2) * s, 0], r: [0, R() * 3, 0] });
  }
  put(cone(.05 * s, .14 * s, 6), P.pineL, { p: [0, (.42 + tiers * .2) * s + .04, 0], line: .008 });
  for (let i = 0; i < 6; i++) {   // 松针落地
    const a = R() * 6.28, d = .2 + R() * .3;
    put(box(.05, .006, .015), P.pineD, { p: [Math.cos(a) * d, .008, Math.sin(a) * d], r: [0, R() * 3, 0], line: 0, ao: false });
  }
}

export function bush(o, { berry = false, flower = null } = {}) {
  const put = putter(o);
  for (const [x, z, r] of [[-.2, .02, .24], [.2, .04, .23], [0, -.08, .3], [-.06, .14, .2], [.12, -.16, .2]]) put(blob(r, 1, .85), jit(P.leaf, .06), { p: [x, r * .75, z] });
  for (const [x, z] of [[-.08, -.02], [.1, .02]]) put(blob(.16, 1), jit(P.leafL, .03), { p: [x, .42, z] });
  if (berry) for (let i = 0; i < 12; i++) { const a = R() * 6.28, d = .26 + R() * .06; put(ball(.035, 6, 5), jit(P.berry, .05), { p: [Math.cos(a) * d, .16 + R() * .26, Math.sin(a) * d * .8], line: .006 }); }
  if (flower) for (let i = 0; i < 8; i++) { const a = R() * 6.28, d = .25; put(ball(.03, 6, 4), flower, { p: [Math.cos(a) * d, .2 + R() * .25, Math.sin(a) * d * .8], line: 0 }); }
}

// ———————————————— 花草 ————————————————
function leafPair(put, x, z, y, s = 1) {
  for (const sx of [-1, 1]) put(blob(.05 * s, 1, .3), P.leaf, { p: [x + sx * .045 * s, y, z], s: [1.6, 1, .8], r: [0, 0, sx * .4], line: .006 });
}
export function flowerPatch(o, petal, { n = 5, stem = .2, shape = 'round' } = {}) {
  const put = putter(o);
  for (let i = 0; i < n; i++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5, hh = stem * (.8 + R() * .4);
    put(cyl(.01, .013, hh, 5), P.leafD, { p: [x, hh / 2, z], line: .005 });
    leafPair(put, x, z, hh * .35);
    const c = jit(petal, .05);
    if (shape === 'tulip') {
      put(lathe([[0, 0], [.03, .005], [.045, .04], [.04, .08], [.028, .095]], 8), c, { p: [x, hh - .01, z], line: .006 });
    } else if (shape === 'daisy') {
      for (let k = 0; k < 8; k++) { const a = k / 8 * 6.28; put(box(.045, .008, .018), P.white, { p: [x + Math.cos(a) * .035, hh, z + Math.sin(a) * .035], r: [0, -a, 0], line: .004 }); }
      put(ball(.02, 6, 4), P.yellow, { p: [x, hh + .008, z], s: [1, .6, 1], line: .004 });
    } else {
      for (let k = 0; k < 5; k++) { const a = k / 5 * 6.28; put(ball(.024, 6, 4), c, { p: [x + Math.cos(a) * .028, hh, z + Math.sin(a) * .028], s: [1, .6, 1], line: .004 }); }
      put(ball(.016, 6, 4), P.white, { p: [x, hh + .01, z], line: 0 });
    }
  }
}
export function clover(o) {
  const put = putter(o);
  for (let i = 0; i < 9; i++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5;
    for (let k = 0; k < 3; k++) { const a = k / 3 * 6.28 + R(); put(ball(.03, 6, 4), P.leaf, { p: [x + Math.cos(a) * .03, .03, z + Math.sin(a) * .03], s: [1, .3, 1], line: 0 }); }
    if (i % 2 === 0) { put(cyl(.006, .006, .1, 4), P.leafD, { p: [x, .06, z], line: 0 }); put(ball(.03, 7, 5), jit(P.pink, .06), { p: [x, .12, z], s: [1, 1.2, 1], line: .005 }); }
  }
}
export function lavender(o) {
  const put = putter(o);
  for (let i = 0; i < 9; i++) {
    const x = (R() - .5) * .55, z = (R() - .5) * .45, hh = .28 + R() * .14, tilt = [(R() - .5) * .3, 0, (R() - .5) * .3];
    put(cyl(.008, .011, hh, 4), P.leafD, { p: [x, hh / 2, z], r: tilt, line: 0 });
    for (let k = 0; k < 4; k++) put(ball(.022 - k * .003, 6, 4), jit(k % 2 ? P.lav : P.lavD, .04), { p: [x + tilt[2] * -hh * .5, hh + k * .035, z + tilt[0] * hh * .5], s: [1, 1.3, 1], line: .004 });
  }
  for (let i = 0; i < 4; i++) put(blob(.06, 1, .5), P.leafD, { p: [(R() - .5) * .4, .03, (R() - .5) * .3], line: .005 });
}
export function sunflower(o) {
  const put = putter(o);
  put(cyl(.018, .025, .78, 6), P.leafD, { p: [0, .39, 0] });
  for (const [y, sx] of [[.25, 1], [.42, -1], [.58, 1]]) put(blob(.08, 1, .25), P.leaf, { p: [sx * .08, y, 0], s: [1.8, 1, 1], r: [0, 0, sx * .5], line: .006 });
  const head = new THREE.Matrix4().makeRotationX(-.25).setPosition(o.cx, o.t + .8, o.cz + .03);
  for (let k = 0; k < 14; k++) { const a = k / 14 * 6.28; bake(blob(.05, 0, .3), jit(P.yellow, .04), { matrix: head, p: [Math.cos(a) * .1, Math.sin(a) * .1, 0], s: [1.6, .7, .5], r: [0, 0, a], line: .004, ao: null }); }
  bake(cyl(.075, .075, .04, 14), '#8a6446', { matrix: head, p: [0, 0, .015], r: [Math.PI / 2, 0, 0], line: .006 });
  bake(cyl(.06, .06, .01, 14), '#6e4e36', { matrix: head, p: [0, 0, .037], r: [Math.PI / 2, 0, 0], line: 0 });
}
export function lily(o) {
  const put = putter(o);
  for (let i = 0; i < 3; i++) put(disc(.13 + R() * .04, 14, .3, Math.PI * 1.8), P.leaf, { p: [(R() - .5) * .5, .012, (R() - .5) * .4], r: [0, R() * 6, 0], line: .006, ao: false });
  for (let k = 0; k < 8; k++) { const a = k / 8 * 6.28; put(blob(.04, 0, .5), k % 2 ? P.pinkL : P.pink, { p: [.05 + Math.cos(a) * .035, .04, Math.sin(a) * .035], s: [1.3, .8, .7], r: [0, -a, .5], line: .004, ao: false }); }
  put(ball(.02, 6, 4), P.yellow, { p: [.05, .06, 0], line: 0, ao: false });
}

// ———————————————— 石头、树桩 ————————————————
export function rock(o, s = 1, n = 1) {
  const put = putter(o);
  for (let i = 0; i < n; i++) {
    const rr = .22 * s * (1 - i * .22), x = (i - (n - 1) / 2) * .3 * s, z = (R() - .5) * .18;
    put(blob(rr, 1, .7, .35), jit(i % 2 ? P.rockD : P.rock, .05), { p: [x, rr * .5, z], r: [0, R() * 3, 0] });
    put(blob(rr * .55, 1, .35, .3), jit(P.moss, .05), { p: [x - rr * .15, rr * .88, z], line: 0 });   // 顶上一点青苔
  }
  for (let i = 0; i < 3; i++) put(blob(.04 * s, 0, .6), P.rockD, { p: [(R() - .5) * .7 * s, .02, (R() - .5) * .4], line: .005 });
}
export function stump(o) {
  const put = putter(o);
  put(cyl(.2, .25, .24, 14), P.trunk, { p: [0, .12, 0] });
  for (let i = 0; i < 8; i++) { const a = i / 8 * 6.28; put(box(.03, .22, .04), P.trunkD, { p: [Math.cos(a) * .215, .11, Math.sin(a) * .215], r: [0, -a, 0], line: 0 }); }
  put(cyl(.19, .19, .02, 14), P.woodL, { p: [0, .245, 0], line: 0 });
  for (const r of [.13, .07]) put(torus(r, .006, 4, 20), P.woodD, { p: [0, .256, 0], r: [Math.PI / 2, 0, 0], line: 0 });
  for (const [x, z, s] of [[.22, .1, 1], [.26, .02, .7], [-.2, .16, .8]]) {   // 一小簇蘑菇
    put(cyl(.012 * s, .016 * s, .06 * s, 6), P.white, { p: [x, .03 * s, z], line: .004 });
    put(ball(.04 * s, 8, 5, 0, Math.PI * 2, 0, Math.PI / 2), '#d48a7c', { p: [x, .06 * s, z], line: .005 });
  }
}

// ———————————————— 小物件 ————————————————
export function fence(o, w) {
  const put = putter(o);
  const posts = Math.max(2, Math.round(w) + 1);
  for (let i = 0; i < posts; i++) {
    const x = -w / 2 + .08 + i * (w - .16) / (posts - 1);
    put(box(.08, .46, .08, .015), P.woodD, { p: [x, .23, .3] });
    put(box(.1, .03, .1, .01), P.woodL, { p: [x, .475, .3], line: .006 });
  }
  for (const y of [.15, .34]) put(box(w - .1, .045, .035, .01), P.wood, { p: [0, y, .3] });
  const pickets = Math.round(w * 5);
  for (let i = 0; i < pickets; i++) {
    const x = -w / 2 + .17 + i * (w - .34) / Math.max(1, pickets - 1);
    put(box(.045, .36, .02), jit(P.woodL, .04), { p: [x, .19, .325], line: .005 });
    put(cone(.032, .05, 4), P.woodL, { p: [x, .395, .325], r: [0, .78, 0], line: .004 });
  }
}
export function crate(o) {
  const put = putter(o);
  put(box(.5, .36, .44, .02), P.woodD, { p: [0, .18, 0] });
  for (const y of [.06, .18, .3]) for (const z of [-.225, .225]) put(box(.52, .09, .02), jit(P.woodL, .04), { p: [0, y, z], line: .004 });
  for (const x of [-.24, .24]) for (const z of [-.21, .21]) put(box(.05, .38, .05), P.wood, { p: [x, .19, z], line: .004 });
  for (let i = 0; i < 7; i++) put(ball(.06, 8, 6), jit([P.apple, P.peach, P.yellow][i % 3], .05), { p: [-.15 + (i % 4) * .1, .38 + (i > 3 ? .03 : 0), -.1 + (i > 3 ? .12 : 0) + (i % 2) * .05], line: .006 });
}
export function barrel(o) {
  const put = putter(o);
  const n = 14;
  for (let i = 0; i < n; i++) { const a = i / n * 6.28; put(box(.09, .5, .03), jit(P.wood, .05), { p: [Math.cos(a) * .2, .25, Math.sin(a) * .2], r: [0, -a + Math.PI / 2, 0], s: [1, 1, 1], line: .004 }); }
  for (const y of [.09, .41]) put(torus(.212, .014, 4, 24), P.metal, { p: [0, y, 0], r: [Math.PI / 2, 0, 0], line: .004 });
  put(cyl(.19, .19, .02, 16), '#9cc2d2', { p: [0, .46, 0], line: 0 });
  put(box(.03, .12, .03), P.woodD, { p: [.12, .52, .05], r: [.3, 0, .4], line: .004 });   // 舀水的小木勺
}
export function bench(o, w) {
  const put = putter(o);
  const L = w * .82;
  for (let i = 0; i < 4; i++) put(box(L, .03, .075, .01), jit(P.woodL, .03), { p: [0, .27, -.13 + i * .085] });
  for (let i = 0; i < 3; i++) put(box(L, .06, .025, .01), jit(P.woodL, .03), { p: [0, .38 + i * .08, -.2 - i * .02], r: [-.2, 0, 0] });
  for (const sx of [-1, 1]) {
    put(box(.04, .26, .04), P.ink, { p: [sx * L * .42, .13, .1], line: .005 });
    put(box(.04, .56, .04), P.ink, { p: [sx * L * .42, .28, -.18], r: [-.2, 0, 0], line: .005 });
    put(box(.04, .03, .34), P.ink, { p: [sx * L * .42, .4, -.02], line: .005 });   // 扶手
  }
}
export function lamp(o) {
  const put = putter(o);
  put(cyl(.1, .12, .08, 10), '#4d5156', { p: [0, .04, 0] });
  put(cyl(.035, .05, 1.2, 8), '#4d5156', { p: [0, .64, 0] });
  for (const y of [.2, 1.05]) put(torus(.045, .012, 4, 12), '#4d5156', { p: [0, y, 0], r: [Math.PI / 2, 0, 0], line: .004 });
  // 灯笼：四根小柱、四面玻璃、顶
  put(box(.2, .03, .2), '#4d5156', { p: [0, 1.25, 0], line: .005 });
  for (const [x, z] of [[-.085, -.085], [.085, -.085], [-.085, .085], [.085, .085]]) put(box(.02, .22, .02), '#4d5156', { p: [x, 1.37, z], line: .004 });
  put(box(.16, .2, .16), P.lamp, { p: [0, 1.37, 0], line: 0 });
  put(cone(.16, .12, 4), '#4d5156', { p: [0, 1.54, 0], r: [0, .78, 0], line: .006 });
  put(ball(.025, 6, 4), '#4d5156', { p: [0, 1.62, 0], line: .004 });
}
export function mailbox(o) {
  const put = putter(o);
  put(box(.07, .52, .07), P.woodD, { p: [0, .26, 0] });
  put(box(.24, .12, .34, .02), '#c97e72', { p: [0, .58, 0] });
  put(cyl(.12, .12, .34, 12, false), '#c97e72', { p: [0, .64, 0], r: [Math.PI / 2, 0, 0], s: [1, 1, 1] });
  put(box(.012, .14, .03), '#e8c46a', { p: [.13, .72, .08], line: .004 });
  put(box(.012, .05, .07), '#e8c46a', { p: [.13, .77, .11], line: .004 });   // 小红旗（立着 = 有信）
  put(cyl(.09, .09, .02, 12), '#b46a5e', { p: [0, .62, .175], r: [Math.PI / 2, 0, 0], line: .005 });
}

// ———————————————— 房子 ————————————————
// style：wall 墙、roof/roofD 两坡、door、timber 木框、logs 原木屋、awning 条纹雨棚、extra 门口小东西
export function house(o, d, st) {
  const put = putter(o);
  const w = d.w * .84, dep = 2.1, wallH = 1.02, base = .16, zc = -dep / 2 + .3, fz = zc + dep / 2, bz = zc - dep / 2;
  // 地基：一圈石块
  put(box(w + .14, base, dep + .14), P.stone, { p: [0, base / 2, zc], line: .01 });
  for (let x = -w / 2; x < w / 2 - .05; x += .26) put(box(.22 + R() * .04, .08, .03), jit(P.rock, .06), { p: [x + .13, .07, fz + .075], line: .004 });
  const y0 = base;
  if (st.logs) {   // 原木屋：一根根横着的原木，转角露出木头的圆头
    const n = 7, lr = wallH / n / 2;
    for (let i = 0; i < n; i++) {
      const y = y0 + lr + i * lr * 2;
      for (const z of [fz - lr, bz + lr]) put(cyl(lr, lr, w + .14, 10), jit(st.wall, .04), { p: [0, y, z], r: [0, 0, Math.PI / 2], line: .006 });
      for (const x of [-w / 2 + lr, w / 2 - lr]) put(cyl(lr, lr, dep + .14, 10), jit(st.wall, .04), { p: [x, y, zc], r: [Math.PI / 2, 0, 0], line: .006 });
    }
    put(box(w - .1, wallH, dep - .1), st.wall, { p: [0, y0 + wallH / 2, zc], line: 0 });
  } else {
    put(box(w, wallH, dep, .03), st.wall, { p: [0, y0 + wallH / 2, zc] });
    if (st.timber) {   // 木框：四角立柱、腰线、檐下一道
      for (const x of [-w / 2, w / 2]) for (const z of [fz, bz]) put(box(.07, wallH, .07), P.beam, { p: [x, y0 + wallH / 2, z], line: .006 });
      for (const y of [y0 + .02, y0 + wallH * .5, y0 + wallH - .03]) {
        put(box(w + .04, .05, .04), P.beam, { p: [0, y, fz + .01], line: .006 });
        for (const x of [-w / 2 - .01, w / 2 + .01]) put(box(.04, .05, dep + .04), P.beam, { p: [x, y, zc], line: .006 });
      }
      for (const sx of [-1, 1]) put(box(.04, wallH * .5, .04), P.beam, { p: [sx * w * .18, y0 + wallH * .75, fz + .01], r: [0, 0, sx * .5], line: .005 });
    }
  }
  // 屋顶：两坡，每坡一排排瓦（下面一排压着上面一排的边），檐口出挑
  const top = y0 + wallH, rh = .62, over = .2, half = dep / 2 + over, slope = Math.hypot(half, rh), ang = Math.atan2(rh, half);
  for (const s of [-1, 1]) {
    const m = new THREE.Matrix4().makeRotationX(s * ang).setPosition(o.cx, o.t + top + rh / 2 - .02, o.cz + zc + s * half / 2);
    bake(box(w + .44, .05, slope + .02), st.roofD, { matrix: m, p: [0, -.02, 0], line: .012 });
    const rows = 7;
    for (let i = 0; i < rows; i++) {
      const v = -slope / 2 + (i + .5) * slope / rows;
      bake(box(w + .46, .04, slope / rows + .03, .012), jit(i % 2 ? st.roof : st.roofD, .025), { matrix: m, p: [0, .025 + (rows - i) * .004, s * v], r: [s * .06, 0, 0], line: .006 });
    }
    bake(box(w + .5, .05, .04), P.trim, { matrix: m, p: [0, -.01, s * (slope / 2 + .01)], line: .006 });   // 檐口封板
  }
  put(cyl(.05, .05, w + .5, 10), st.roofD, { p: [0, top + rh + .015, zc], r: [0, 0, Math.PI / 2], line: .008 });   // 屋脊
  // 山墙 + 阁楼小圆窗
  for (const sx of [-1, 1]) {
    const x = sx * (w / 2 - (st.logs ? .02 : .005));
    const a = [x, top, zc - dep / 2], b = [x, top, zc + dep / 2], c = [x, top + rh - .02, zc];
    put(sx > 0 ? tri3(a, c, b) : tri3(a, b, c), st.gable || st.wall, { p: [0, 0, 0], line: 0, ao: false });
    put(torus(.1, .02, 6, 16), P.trim, { p: [x + sx * .02, top + rh * .4, zc], r: [0, Math.PI / 2, 0], line: .005 });
    put(cyl(.09, .09, .02, 14), P.glass, { p: [x + sx * .015, top + rh * .4, zc], r: [0, 0, Math.PI / 2], line: 0 });
  }
  // 烟囱：砖色，一道道砖缝，顶上压一块，冒两团烟
  const chx = w * .27, chz = zc - dep * .18, chH = .55;
  put(box(.22, chH, .22), st.brick || P.brick, { p: [chx, top + rh * .55 + chH / 2 - .1, chz], line: .01 });
  for (let i = 0; i < 4; i++) put(box(.225, .012, .225), '#a5685a', { p: [chx, top + rh * .55 + i * .11, chz], line: 0 });
  put(box(.27, .05, .27), P.ink, { p: [chx, top + rh * .55 + chH - .07, chz], line: .006 });
  for (const [dy, r, dx] of [[.12, .07, 0], [.27, .09, .08], [.45, .11, .05]]) put(blob(r, 1), '#f4efe8', { p: [chx + dx, top + rh * .55 + chH + dy, chz - .02], line: 0, ao: false });
  // 门：门框、四块凸起的门板、把手，上面一个小雨棚，旁边一盏门灯，门口两级台阶和一块地垫
  const dw = .34, dh = .62;
  put(box(dw + .1, dh + .06, .04), P.trim, { p: [0, y0 + dh / 2, fz + .01], line: .006 });
  put(box(dw, dh, .04), st.door, { p: [0, y0 + dh / 2 - .01, fz + .025], line: .006 });
  for (const [x, y] of [[-.07, .17], [.07, .17], [-.07, .43], [.07, .43]]) put(box(.11, .2, .015), jit(st.door, .06).multiplyScalar(1.08), { p: [x, y0 + y, fz + .05], line: .003 });
  put(ball(.022, 8, 6), '#e3c06a', { p: [.12, y0 + .3, fz + .06], line: .004 });
  const am = new THREE.Matrix4().makeRotationX(.5).setPosition(o.cx, o.t + y0 + dh + .16, o.cz + fz + .14);
  bake(box(dw + .26, .04, .32), st.roofD, { matrix: am, line: .008 });
  for (const sx of [-1, 1]) put(box(.03, .03, .2), P.beam, { p: [sx * (dw / 2 + .08), y0 + dh + .06, fz + .1], r: [-.6, 0, 0], line: .004 });
  put(box(.1, .14, .1), P.lamp, { p: [dw / 2 + .2, y0 + .62, fz + .07], line: .006 });
  put(box(.13, .03, .13), P.ink, { p: [dw / 2 + .2, y0 + .705, fz + .07], line: .004 });
  put(box(.03, .08, .05), P.ink, { p: [dw / 2 + .2, y0 + .52, fz + .035], line: .004 });
  put(box(dw + .2, .07, .16), P.stone, { p: [0, .035 + .07, fz + .1], line: .006 });
  put(box(dw + .34, .07, .18), P.stone, { p: [0, .035, fz + .22], line: .006 });
  put(box(.36, .012, .18), '#c4a27c', { p: [0, .075, fz + .38], line: .003 });
  // 窗：窗框、窗台、玻璃、十字窗棂、里面的窗帘、两边百叶窗、窗下花箱
  const win = (x, z, faceX = 0) => {
    const m = new THREE.Matrix4().makeRotationY(faceX * Math.PI / 2).setPosition(o.cx + x, o.t + y0 + .58, o.cz + z);
    bake(box(.34, .36, .04), P.trim, { matrix: m, line: .006, ao: null });
    bake(box(.27, .29, .03), P.glass, { matrix: m, p: [0, 0, .012], line: 0, ao: null });
    for (const sx of [-1, 1]) bake(box(.08, .26, .02), P.curtain, { matrix: m, p: [sx * .09, 0, .005], line: 0, ao: null });
    bake(box(.27, .018, .02), P.trim, { matrix: m, p: [0, 0, .03], line: 0, ao: null });
    bake(box(.018, .29, .02), P.trim, { matrix: m, p: [0, 0, .03], line: 0, ao: null });
    bake(box(.4, .03, .08), P.trim, { matrix: m, p: [0, -.19, .03], line: .004, ao: null });
    for (const sx of [-1, 1]) {
      bake(box(.12, .34, .02), st.shutter || '#8fa58a', { matrix: m, p: [sx * .25, 0, .02], line: .005, ao: null });
      for (let k = 0; k < 4; k++) bake(box(.1, .012, .01), new THREE.Color(st.shutter || '#8fa58a').multiplyScalar(.85), { matrix: m, p: [sx * .25, -.12 + k * .08, .033], line: 0, ao: null });
    }
    bake(box(.36, .08, .1, .015), P.woodD, { matrix: m, p: [0, -.25, .06], line: .005, ao: null });
    for (let k = 0; k < 5; k++) {
      bake(blob(.04, 0, .8), P.leaf, { matrix: m, p: [-.14 + k * .07, -.2, .07], line: .004, ao: null });
      bake(ball(.025, 6, 4), [P.pink, P.red, P.yellow, P.white, P.lav][k], { matrix: m, p: [-.14 + k * .07, -.17, .09], line: 0, ao: null });
    }
  };
  for (const sx of [-1, 1]) if (w * .32 > .38) win(sx * w * .32, fz + .02);
  win(w / 2 + .02, zc, 1);
  win(-w / 2 - .02, zc, -1);
  // 雨水管
  put(cyl(.022, .022, wallH + .1, 6), P.metal, { p: [-w / 2 + .05, y0 + wallH / 2, fz + .05], line: .004 });
  // 门口的小东西
  if (st.extra === 'pots') for (const sx of [-1, 1]) {
    put(lathe([[0, 0], [.07, 0], [.09, .14], [.1, .15], [0, .15]], 10), P.terra, { p: [sx * (dw / 2 + .32), .0, fz + .26], line: .006 });
    put(blob(.09, 1), P.leaf, { p: [sx * (dw / 2 + .32), .22, fz + .26] });
    for (let k = 0; k < 3; k++) put(ball(.025, 6, 4), P.pink, { p: [sx * (dw / 2 + .32) + (k - 1) * .05, .29, fz + .3], line: 0 });
  }
  if (st.extra === 'logs') {   // 屋侧一堆柴
    for (let r = 0; r < 3; r++) for (let i = 0; i < 4 - r; i++) put(cyl(.06, .06, .5, 8), jit(P.trunk, .06), { p: [w / 2 + .22, .07 + r * .11, zc - .3 + i * .13 + r * .065], r: [Math.PI / 2, 0, 0], line: .005 });
  }
  if (st.awning) {   // 厨房：窗上一条红白条纹的雨棚，门口两箱菜
    const m = new THREE.Matrix4().makeRotationX(.55).setPosition(o.cx - w * .32, o.t + y0 + .86, o.cz + fz + .14);
    for (let i = 0; i < 6; i++) bake(box(.09, .025, .3), i % 2 ? P.white : '#d9897e', { matrix: m, p: [-.225 + i * .09, 0, 0], line: .004, ao: null });
    for (const x of [w * .3, w * .3 + .32]) {
      put(box(.28, .16, .2), P.woodL, { p: [x, .08, fz + .3], line: .006 });
      for (let k = 0; k < 4; k++) put(ball(.045, 7, 5), [P.apple, '#e8c06a', '#9cbf72', P.peach][k], { p: [x - .09 + k * .06, .19, fz + .3], line: .004 });
    }
  }
}

export function fallback(o) {   // 还没单独做模型的：一个小木台 + 一团叶子
  const put = putter(o);
  put(box(.5, .12, .5, .04), P.woodL, { p: [0, .06, 0] });
  put(blob(.22, 1), P.leaf, { p: [0, .3, 0] });
}

export const BUILD = {
  treeGreen: (o) => tree(o, {}),
  treePink: (o) => tree(o, { leaf: P.pink, leafD: P.pinkD, leafL: P.pinkL, petals: P.pink, blossom: P.white }),
  treeBig: (o) => tree(o, { h: 1.15, r: .62, fruit: P.apple }),
  treeOrange: (o) => tree(o, { leaf: P.autumn, leafD: P.autumnD, leafL: P.autumnL, petals: P.autumn }),
  treeSmall: (o) => tree(o, { h: .72, r: .38 }),
  pinkSmall: (o) => tree(o, { h: .72, r: .38, leaf: P.pink, leafD: P.pinkD, leafL: P.pinkL, blossom: P.white }),
  olive: (o) => tree(o, { h: .72, r: .4, fruit: P.peach }),
  pine: (o) => pine(o, 1.25),
  bonsai: (o) => pine(o, .75),
  bush: (o) => bush(o), berry: (o) => bush(o, { berry: true }),
  rock: (o) => rock(o, 1.1), pebble: (o) => rock(o, .55), rocks: (o) => rock(o, 1, 3), stump,
  daisy: (o) => flowerPatch(o, P.white, { shape: 'daisy' }), clover,
  flowerY: (o) => flowerPatch(o, P.yellow), flowerR: (o) => flowerPatch(o, P.red, { shape: 'tulip' }),
  tulipPeach: (o) => flowerPatch(o, P.peach, { shape: 'tulip' }), lavender, sunflower, lily,
  houseOrange: (o, d) => house(o, d, { wall: P.cream, roof: P.terra, roofD: P.terraD, door: P.door, timber: true, extra: 'pots', shutter: '#9aae8a' }),
  cabin: (o, d) => house(o, d, { wall: '#c9a27c', gable: '#c9a27c', roof: P.roofBlue, roofD: P.roofBlueD, door: '#7a5a44', logs: true, extra: 'logs', shutter: '#8fa3b8' }),
  shop: (o, d) => house(o, d, { wall: '#f1e7da', roof: P.roofGreen, roofD: P.roofGreenD, door: '#7b8f6a', awning: true, shutter: '#c99a86' }),
  houseBeige: (o, d) => house(o, d, { wall: '#f1e7da', roof: '#c9a48a', roofD: '#b48f76', door: '#8fa3b8', timber: true, extra: 'pots', shutter: '#a9bcc8' }),
  fence: (o, d) => fence(o, d.w), fenceV: (o, d) => fence(o, d.w),
  crate, barrel, bench: (o, d) => bench(o, d.w), lamp, mailbox,
};
