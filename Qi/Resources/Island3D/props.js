// 剩下那些景：都按手办的做法——圆角、软胶和木头的质感、细节放满。原点是占地底边中点，脸朝 +z
import * as THREE from 'three';
import { bake, R, jit, box, cyl, cone, ball, torus, blob, lathe, disc } from './kit.js';

const W = {
  wood: '#b98a62', woodD: '#8f6646', woodL: '#d4ad84', straw: '#e3c27a', strawD: '#c9a35c', iron: '#4e535b', gold: '#c9a45c',
  white: '#f8f4ec', cream: '#f2e8d8', red: '#d9706a', redD: '#b85550', blue: '#8fb3d1', blueD: '#6f95b8', green: '#7fa36b', greenD: '#5f8450',
  pink: '#f1b3bd', yellow: '#f3d27a', glass: '#bcd8e4', stone: '#d8d0c2', stoneD: '#b7ad9d', canvas: '#f4ead8', snow: '#fbfcfd', coral: '#f08f8c',
  lamp: '#f6d79a', leaf: '#8fae74', leafD: '#6f9058',
};
const putter = (o) => (geo, color, opt = {}) => {
  const p = opt.p || [0, 0, 0];
  return bake(geo, color, { ...opt, ao: opt.ao === false ? null : o.t, p: [o.cx + p[0], o.t + p[1], o.cz + p[2]] });
};
const rb = (w, h, d, r = .02) => box(w, h, d, r, 3);
const capsule = (r, l) => new THREE.CapsuleGeometry(r, l, 6, 12);

export function signpost(o) {
  const put = putter(o);
  put(cyl(.04, .05, 1.0, 10), W.woodD, { p: [0, .5, 0] });
  put(ball(.05, 10, 8), W.woodD, { p: [0, 1.02, 0] });
  for (const [y, a, l] of [[.82, .25, .5], [.62, -.3, .44]]) {
    put(rb(l, .14, .04, .03), W.woodL, { p: [Math.cos(a) * .12, y, 0], r: [0, a, 0] });
    put(cone(.07, .08, 3), W.woodL, { p: [Math.cos(a) * (.12 + l / 2 + .03), y, Math.sin(-a) * (l / 2 + .03)], r: [0, a, -Math.PI / 2], s: [1, 1, .3] });
    for (let k = 0; k < 3; k++) put(box(l * .55 - k * .05, .012, .006), W.woodD, { p: [Math.cos(a) * .12, y + .03 - k * .03, .023], r: [0, a, 0] });
  }
  for (let i = 0; i < 4; i++) put(blob(.06, 1, .6), W.leaf, { p: [(R() - .5) * .3, .04, (R() - .5) * .2] });
}

export function greenhouse(o, d) {
  const put = putter(o);
  const w = Math.max(1.6, d.w * .8), dp = 1.4, h = .8;
  put(rb(w + .1, .12, dp + .1, .03), W.stone, { p: [0, .06, -dp / 2 + .3] });
  // 白色铁框 + 玻璃，屋顶是弧形的拱
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) put(box(.04, h, .04), W.white, { p: [sx * w / 2, .12 + h / 2, -dp / 2 + .3 + sz * dp / 2] });
  for (let i = 0; i <= 5; i++) { const x = -w / 2 + i * w / 5; put(box(.025, h, .025), W.white, { p: [x, .12 + h / 2, .3] }); put(box(.025, h, .025), W.white, { p: [x, .12 + h / 2, .3 - dp] }); }
  for (const z of [.3, .3 - dp]) put(box(w, h - .04, .01), W.glass, { p: [0, .12 + h / 2, z], mat: 'glass' });
  for (const sx of [-1, 1]) put(box(.01, h - .04, dp), W.glass, { p: [sx * w / 2, .12 + h / 2, .3 - dp / 2], mat: 'glass' });
  const arch = new THREE.CylinderGeometry(w / 2, w / 2, dp, 20, 1, true, -Math.PI / 2, Math.PI); arch.rotateX(Math.PI / 2); arch.rotateZ(0);
  put(arch, W.glass, { p: [0, .12 + h, .3 - dp / 2], r: [0, 0, Math.PI / 2], s: [1, 1, 1], mat: 'glass' });
  for (let i = 0; i <= 5; i++) put(torus(w / 2, .014, 4, 20, Math.PI), W.white, { p: [0, .12 + h, .3 - i * dp / 5] });
  put(box(.03, .03, dp), W.white, { p: [0, .12 + h + w / 2, .3 - dp / 2] });
  // 里面：两排花盆和架子
  for (const sx of [-1, 1]) {
    put(rb(.3, .04, dp - .2, .01), W.wood, { p: [sx * (w / 2 - .22), .42, .3 - dp / 2] });
    for (let k = 0; k < 4; k++) { const z = .3 - .25 - k * (dp - .4) / 3; put(lathe([[0, 0], [.06, 0], [.075, .09], [0, .09]], 10), W.red, { p: [sx * (w / 2 - .22), .44, z] }); put(blob(.07, 1), W.green, { p: [sx * (w / 2 - .22), .58, z] }); put(ball(.025, 8, 6), [W.pink, W.yellow, W.white, W.coral][k], { p: [sx * (w / 2 - .22), .64, z + .03] }); }
  }
  put(rb(.34, .62, .03, .01), W.white, { p: [0, .43, .31] });   // 门
  put(box(.28, .54, .01), W.glass, { p: [0, .43, .33], mat: 'glass' });
}

export function lighthouse(o) {
  const put = putter(o);
  put(cyl(.6, .66, .2, 24), W.stoneD, { p: [0, .1, 0] });
  const tower = lathe([[.5, 0], [.46, .8], [.4, 1.6], [.36, 2.2]], 24);
  put(tower, W.white, { p: [0, .2, 0] });
  for (let i = 0; i < 4; i++) { const y = .2 + i * .55 + .1, r = .5 - (i * .55 + .1) / 2.2 * .14; put(cyl(r + .008, r + .02, .25, 24, true), W.red, { p: [0, y + .12, 0] }); }
  for (const y of [.7, 1.4]) { put(rb(.14, .22, .05, .03), W.blueD, { p: [0, .2 + y, .45 - y * .05] }); }
  put(rb(.2, .34, .05, .04), W.woodD, { p: [0, .37, .5] });
  put(cyl(.5, .48, .08, 24), W.white, { p: [0, 2.44, 0] });
  for (let k = 0; k < 20; k++) { const a = k / 20 * 6.28; put(box(.015, .18, .015), W.iron, { p: [Math.cos(a) * .47, 2.56, Math.sin(a) * .47] }); }
  put(torus(.47, .012, 4, 32), W.iron, { p: [0, 2.65, 0], r: [Math.PI / 2, 0, 0] });
  put(cyl(.26, .26, .38, 16), W.glass, { p: [0, 2.67, 0], mat: 'glass' });
  put(ball(.14, 16, 12), W.lamp, { p: [0, 2.67, 0], mat: 'glow' });
  put(cone(.34, .34, 16), W.redD, { p: [0, 3.03, 0] });
  put(ball(.05, 10, 8), W.gold, { p: [0, 3.23, 0], mat: 'gold' });
}

export function telescope(o) {
  const put = putter(o);
  put(cyl(.3, .34, .08, 20), W.stone, { p: [0, .04, 0] });
  for (let k = 0; k < 3; k++) { const a = k / 3 * 6.28; put(cyl(.018, .022, .7, 8), W.woodD, { p: [Math.cos(a) * .14, .38, Math.sin(a) * .14], r: [Math.sin(a) * .35, 0, -Math.cos(a) * .35] }); }
  const m = new THREE.Matrix4().makeRotationX(-.7).setPosition(o.cx, o.t + .76, o.cz);
  bake(cyl(.07, .09, .7, 16), W.blueD, { matrix: m });
  bake(cyl(.095, .095, .08, 16), W.gold, { matrix: m, p: [0, .33, 0], mat: 'gold' });
  bake(cyl(.04, .05, .14, 12), W.gold, { matrix: m, p: [0, -.4, 0], mat: 'gold' });
  bake(cyl(.085, .085, .01, 16), W.glass, { matrix: m, p: [0, .37, 0], mat: 'glass' });
  for (let k = 0; k < 6; k++) put(ball(.02, 6, 4), W.yellow, { p: [(R() - .5) * .5, .085, (R() - .5) * .5], mat: 'glow' });
}

export function scarecrow(o) {
  const put = putter(o);
  put(cyl(.035, .04, 1.1, 8), W.woodD, { p: [0, .55, 0] });
  put(cyl(.025, .025, .8, 8), W.woodD, { p: [0, .82, 0], r: [0, 0, Math.PI / 2] });
  put(rb(.34, .36, .18, .06), '#c97b62', { p: [0, .74, 0] });
  for (const sx of [-1, 1]) { put(capsule(.06, .2), '#c97b62', { p: [sx * .26, .82, 0], r: [0, 0, Math.PI / 2] }); for (let k = 0; k < 4; k++) put(cone(.015, .08, 4), W.straw, { p: [sx * (.42 + R() * .03), .82 + (R() - .5) * .06, (R() - .5) * .04], r: [0, 0, sx * Math.PI / 2 + (R() - .5)] }); }
  for (let k = 0; k < 4; k++) put(rb(.09, .09, .01, .01), ['#e8c06a', '#9fc3d4', '#f1b3bd', '#a3c47f'][k], { p: [-.08 + (k % 2) * .14, .66 + (k > 1 ? .12 : 0), .095] });   // 补丁
  put(ball(.14, 18, 14), W.canvas, { p: [0, 1.06, 0] });
  for (const sx of [-1, 1]) put(box(.04, .04, .01), '#3b3330', { p: [sx * .05, 1.08, .135], r: [0, 0, .78] });
  put(torus(.04, .007, 4, 10, Math.PI), '#3b3330', { p: [0, 1.0, .135], r: [0, 0, Math.PI] });
  put(cyl(.24, .26, .03, 20), W.straw, { p: [0, 1.17, 0] });
  put(cone(.13, .22, 16), W.straw, { p: [0, 1.29, 0] });
  put(torus(.12, .015, 6, 20), W.redD, { p: [0, 1.2, 0], r: [Math.PI / 2, 0, 0] });
  put(ball(.03, 8, 6), '#2c2a2a', { p: [.18, 1.21, .05] });   // 一只停在帽檐上的小鸟
}

export function haybale(o) {
  const put = putter(o);
  const g = cyl(.28, .28, .5, 24); put(g, W.straw, { p: [0, .28, 0], r: [0, 0, Math.PI / 2] });
  for (const sx of [-1, 1]) { put(cyl(.27, .27, .01, 24), W.strawD, { p: [sx * .252, .28, 0], r: [0, 0, Math.PI / 2] }); for (const r of [.18, .1]) put(torus(r, .008, 4, 20), '#b8924e', { p: [sx * .26, .28, 0], r: [0, Math.PI / 2, 0] }); }
  for (const x of [-.12, .12]) put(torus(.285, .012, 4, 28), W.woodD, { p: [x, .28, 0], r: [0, Math.PI / 2, 0] });
  for (let k = 0; k < 12; k++) put(cone(.008, .1, 3), W.straw, { p: [(R() - .5) * .5, .55 + R() * .02, (R() - .5) * .3], r: [(R() - .5) * 1.2, 0, (R() - .5) * 1.2] });
}

export function wheelbarrow(o) {
  const put = putter(o);
  put(rb(.5, .2, .34, .05), W.red, { p: [0, .34, 0], r: [0, 0, -.12] });
  put(rb(.44, .04, .28, .02), W.redD, { p: [0, .43, 0], r: [0, 0, -.12] });
  put(cyl(.13, .13, .05, 20), '#3e3a3a', { p: [.32, .13, 0], r: [Math.PI / 2, 0, 0] });
  put(cyl(.05, .05, .07, 12), W.iron, { p: [.32, .13, 0], r: [Math.PI / 2, 0, 0] });
  for (const sz of [-1, 1]) { put(cyl(.015, .015, .62, 6), W.woodD, { p: [-.05, .3, sz * .15], r: [0, 0, Math.PI / 2 - .12] }); put(cyl(.015, .015, .25, 6), W.woodD, { p: [-.18, .14, sz * .14] }); }
  for (let k = 0; k < 6; k++) put(ball(.06, 10, 8), [W.coral, '#e8c06a', '#a3c47f'][k % 3], { p: [-.15 + (k % 3) * .14, .46, -.08 + Math.floor(k / 3) * .14] });
}

export function well(o) {
  const put = putter(o);
  put(cyl(.4, .44, .45, 20, false), W.stone, { p: [0, .225, 0] });
  for (let i = 0; i < 3; i++) for (let k = 0; k < 14; k++) { const a = k / 14 * 6.28 + i * .22; put(rb(.16, .12, .06, .02), jit(W.stone, .06), { p: [Math.cos(a) * .43, .08 + i * .14, Math.sin(a) * .43], r: [0, -a + Math.PI / 2, 0] }); }
  put(cyl(.34, .34, .02, 20), '#6f93a6', { p: [0, .4, 0], mat: 'water' });
  for (const sx of [-1, 1]) put(rb(.07, .85, .07, .02), W.woodD, { p: [sx * .38, .75, 0] });
  put(cyl(.04, .04, .82, 10), W.wood, { p: [0, .95, 0], r: [0, 0, Math.PI / 2] });
  put(cyl(.006, .006, .4, 4), '#d9c6a2', { p: [0, .74, 0] });
  put(lathe([[0, 0], [.08, 0], [.1, .14], [0, .14]], 12), W.woodL, { p: [0, .47, 0] });
  for (const s of [-1, 1]) put(rb(.95, .04, .45, .02), W.red, { p: [0, 1.2, s * .17], r: [s * .6, 0, 0] });
  put(cyl(.03, .03, 1, 8), W.redD, { p: [0, 1.33, 0], r: [0, 0, Math.PI / 2] });
  put(blob(.1, 1), W.leaf, { p: [.36, .5, .25] });
}

export function beehive(o) {
  const put = putter(o);
  put(rb(.36, .1, .36, .02), W.woodD, { p: [0, .25, 0] });
  for (let k = 0; k < 4; k++) put(box(.04, .22, .04), W.woodD, { p: [k % 2 ? .14 : -.14, .11, k > 1 ? .14 : -.14] });
  for (let i = 0; i < 4; i++) put(rb(.32 - i * .045, .12, .32 - i * .045, .05), i % 2 ? W.straw : W.strawD, { p: [0, .36 + i * .1, 0] });
  put(ball(.08, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), W.straw, { p: [0, .7, 0] });
  put(rb(.06, .04, .02, .01), '#4a3a30', { p: [0, .34, .16] });
  for (let k = 0; k < 4; k++) { const x = (R() - .5) * .5, y = .4 + R() * .4, z = .15 + R() * .2; put(capsule(.014, .02), W.yellow, { p: [x, y, z], r: [0, 0, Math.PI / 2] }); put(box(.02, .004, .015), '#2c2a2a', { p: [x, y, z] }); put(ball(.01, 6, 4), '#ffffff', { p: [x, y + .015, z - .005], s: [1, .4, 1.4] }); }
}

export function flowerpot(o) {
  const put = putter(o);
  put(lathe([[0, 0], [.13, 0], [.16, .22], [.18, .24], [.18, .28], [0, .28]], 18), '#d4855f', { p: [0, 0, 0] });
  put(torus(.17, .015, 6, 24), '#c37350', { p: [0, .26, 0], r: [Math.PI / 2, 0, 0] });
  put(blob(.15, 2), W.green, { p: [0, .38, 0] });
  for (let k = 0; k < 9; k++) { const a = k / 9 * 6.28; put(ball(.035, 8, 6), k % 3 ? W.pink : W.white, { p: [Math.cos(a) * .12, .42 + Math.sin(k) * .05, Math.sin(a) * .12] }); }
}

export function roseArch(o, d) {
  const put = putter(o), w = Math.max(.9, d.w * .8);
  for (const sx of [-1, 1]) for (const sz of [-.1, .1]) put(cyl(.018, .018, 1.0, 6), W.white, { p: [sx * w / 2, .5, sz] });
  for (const sz of [-.1, .1]) put(torus(w / 2, .018, 6, 24, Math.PI), W.white, { p: [0, 1.0, sz] });
  for (let i = 0; i < 6; i++) for (const sx of [-1, 1]) put(box(.01, .01, .2), W.white, { p: [sx * w / 2, .15 + i * .16, 0] });
  for (let i = 0; i < 26; i++) {
    const t = R(), a = Math.PI * t, onArch = i % 2 === 0;
    const x = onArch ? Math.cos(a) * w / 2 : (R() < .5 ? -1 : 1) * w / 2, y = onArch ? 1.0 + Math.sin(a) * w / 2 : .2 + R() * .8;
    put(blob(.06, 1, .8), W.greenD, { p: [x, y, (R() - .5) * .2] });
    if (i % 3 !== 2) put(ball(.035, 8, 6), R() < .5 ? W.pink : '#d9707f', { p: [x + (R() - .5) * .06, y + .03, (R() - .5) * .25] });
  }
}

export function picnic(o, d) {
  const put = putter(o), w = Math.max(1, d.w * .8);
  for (let i = 0; i < 6; i++) for (let k = 0; k < 6; k++) put(box(w / 6, .012, w * .75 / 6), (i + k) % 2 ? W.red : W.white, { p: [-w / 2 + (i + .5) * w / 6, .006, -w * .375 + (k + .5) * w * .75 / 6], ao: false });
  put(rb(.34, .16, .24, .04), W.woodL, { p: [-.15, .09, 0] });
  put(torus(.12, .012, 6, 16, Math.PI), W.woodD, { p: [-.15, .17, 0] });
  for (let k = 0; k < 3; k++) put(ball(.05, 10, 8), [W.coral, '#a3c47f', '#e8c06a'][k], { p: [-.22 + k * .07, .19, .05] });
  put(lathe([[0, 0], [.05, 0], [.05, .16], [.02, .22], [.02, .26], [0, .26]], 12), '#9fc3a8', { p: [.22, 0, .1], mat: 'glass' });
  for (const [x, z] of [[.15, -.2], [.32, -.12]]) { put(cyl(.05, .04, .06, 12), W.white, { p: [x, .03, z] }); put(cyl(.045, .045, .01, 12), '#c77a6a', { p: [x, .06, z] }); }
  put(cyl(.11, .11, .015, 20), W.white, { p: [.05, .01, .18] });
  for (let k = 0; k < 3; k++) put(rb(.05, .03, .04, .01), ['#f3d27a', '#f1b3bd', '#d9a46c'][k], { p: [.02 + k * .03, .03, .18] });
}

export function umbrella(o) {
  const put = putter(o);
  put(cyl(.012, .015, 1.1, 8), W.white, { p: [0, .55, 0], r: [0, 0, .1] });
  const n = 10;
  for (let k = 0; k < n; k++) {
    const g = new THREE.ConeGeometry(.62, .26, 2, 1, true, k / n * Math.PI * 2, Math.PI * 2 / n);
    put(g, k % 2 ? W.white : W.blue, { p: [-.1, 1.15, 0], r: [0, 0, .1] });
  }
  for (let k = 0; k < n; k++) { const a = k / n * 6.28 + Math.PI / n; put(ball(.02, 6, 4), k % 2 ? W.blue : W.white, { p: [-.1 + Math.cos(a) * .62, 1.02, Math.sin(a) * .62] }); }
  put(ball(.03, 8, 6), W.white, { p: [-.115, 1.3, 0] });
  put(cyl(.2, .22, .06, 16), W.stone, { p: [0, .03, 0] });
}

export function deckchair(o) {
  const put = putter(o);
  for (const sx of [-1, 1]) { put(box(.03, .03, .7), W.wood, { p: [sx * .2, .2, 0], r: [-.35, 0, 0] }); put(box(.03, .03, .55), W.wood, { p: [sx * .2, .22, .02], r: [.6, 0, 0] }); }
  const m = new THREE.Matrix4().makeRotationX(-.35).setPosition(o.cx, o.t + .24, o.cz);
  for (let i = 0; i < 6; i++) bake(box(.38, .012, .11), i % 2 ? W.white : W.blue, { matrix: m, p: [0, 0, -.3 + i * .11] });
  bake(rb(.3, .06, .12, .03), W.white, { matrix: m, p: [0, .04, -.28] });
  put(cyl(.06, .07, .02, 14), W.white, { p: [.35, .01, .15] });
  put(lathe([[0, 0], [.04, 0], [.045, .1], [.06, .12], [0, .12]], 10), '#f3b24a', { p: [.35, .02, .15], mat: 'glass' });
}

export function shells(o) {
  const put = putter(o);
  for (let i = 0; i < 4; i++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5;
    if (i % 2) { for (let k = 0; k < 6; k++) put(cone(.025, .1, 4), W.pink, { p: [x, .015, z], r: [Math.PI / 2, 0, (k - 2.5) * .25], s: [1, 1, .4] }); }
    else put(lathe([[0, 0], [.05, .02], [.03, .08], [0, .12]], 10), W.cream, { p: [x, .0, z], r: [0, 0, 1.2] });
  }
  for (let k = 0; k < 5; k++) { const a = k / 5 * 6.28; put(capsule(.012, .05), W.coral, { p: [.15 + Math.cos(a) * .04, .01, .1 + Math.sin(a) * .04], r: [Math.PI / 2, 0, -a] }); }
}

export function rowboat(o, d) {
  const put = putter(o), L = Math.max(1.2, d.w * .8);
  const hull = lathe([[0, 0], [.16, .02], [.24, .1], [.27, .2], [.27, .24]], 20); hull.scale(1, 1, 1);
  put(hull, W.wood, { p: [0, -.05, 0], s: [L / .54, 1, 1] });
  put(torus(.27, .025, 6, 24), W.white, { p: [0, .19, 0], r: [Math.PI / 2, 0, 0], s: [L / .54, 1, 1] });
  for (const x of [-.25, .15]) put(rb(.12, .03, .5, .01), W.woodL, { p: [x * L, .12, 0] });
  for (const s of [-1, 1]) put(cyl(.015, .015, .8, 6), W.woodD, { p: [-.05, .22, s * .25], r: [0, s * .3, Math.PI / 2 - .2] });
  put(torus(.06, .012, 6, 14), W.white, { p: [L * .45, .2, 0] });
}

export function campfire(o) {
  const put = putter(o);
  for (let k = 0; k < 10; k++) { const a = k / 10 * 6.28; put(blob(.06, 1, .7, .2), jit(W.stoneD, .06), { p: [Math.cos(a) * .26, .04, Math.sin(a) * .26] }); }
  for (let k = 0; k < 4; k++) { const a = k / 4 * 6.28 + .4; put(cyl(.035, .04, .4, 8), W.woodD, { p: [Math.cos(a) * .06, .1, Math.sin(a) * .06], r: [Math.sin(a) * 1.1, 0, -Math.cos(a) * 1.1] }); }
  put(cone(.12, .32, 10), '#f3a33f', { p: [0, .26, 0], mat: 'glow' });
  put(cone(.07, .22, 10), '#ffd977', { p: [0, .24, 0], mat: 'glow' });
  for (const [x, z] of [[.4, .1], [-.38, .16]]) { put(cyl(.1, .11, .12, 12), W.wood, { p: [x, .06, z] }); put(cyl(.095, .095, .01, 12), W.woodL, { p: [x, .125, z] }); }
  put(cyl(.006, .006, .5, 4), W.iron, { p: [.1, .32, -.05], r: [0, 0, -.9] });
  put(ball(.03, 8, 6), W.white, { p: [.32, .48, -.05] });   // 签子上烤着的棉花糖
}

export function logpile(o, d) {
  const put = putter(o), L = Math.max(.6, d.w * .45);
  for (let r = 0; r < 3; r++) for (let i = 0; i < 4 - r; i++) {
    const x = -.24 + i * .16 + r * .08, y = .07 + r * .13;
    put(cyl(.07, .07, L, 12), jit(W.wood, .06), { p: [x, y, 0], r: [Math.PI / 2, 0, 0] });
    for (const s of [-1, 1]) { put(cyl(.065, .065, .01, 12), W.woodL, { p: [x, y, s * L / 2], r: [Math.PI / 2, 0, 0] }); put(torus(.035, .005, 4, 10), W.woodD, { p: [x, y, s * (L / 2 + .006)] }); }
  }
  put(cyl(.012, .012, .5, 6), W.woodD, { p: [.38, .25, .1], r: [0, 0, .3] });
  put(rb(.14, .05, .02, .01), W.iron, { p: [.42, .45, .1], r: [0, 0, .3] });   // 斜靠着一把斧头
}

export function tent(o, d) {
  const put = putter(o), L = Math.max(1, d.w * .7);
  for (const s of [-1, 1]) put(rb(.66, .02, L, .01), s > 0 ? W.canvas : '#ead9bd', { p: [s * .21, .3, 0], r: [0, 0, -s * .87] });
  put(new THREE.CircleGeometry(.44, 3, Math.PI / 2, Math.PI * 2), '#e8d2ae', { p: [0, .02, L / 2], s: [1, 1.38, 1] });
  put(new THREE.CircleGeometry(.2, 3, Math.PI / 2, Math.PI * 2), '#4a3f38', { p: [0, .0, L / 2 + .005], s: [1, 1.4, 1] });
  put(cyl(.012, .012, .7, 6), W.woodD, { p: [0, .3, L / 2 + .02] });
  put(cyl(.012, .012, .7, 6), W.woodD, { p: [0, .3, -L / 2 - .02] });
  for (let k = 0; k < 6; k++) put(rb(.06, .03, .005, .005), ['#f08f8c', '#f3d27a', '#8fb3d1'][k % 3], { p: [-.25 + k * .1, .58 - Math.abs(-.25 + k * .1) * .8, L / 2 + .03], r: [0, 0, Math.PI / 4] });
  put(cyl(.005, .005, .55, 4), '#d9c6a2', { p: [0, .58, L / 2 + .03], r: [0, 0, Math.PI / 2] });
}

export function mushrooms(o) {
  const put = putter(o);
  for (const [x, z, s, c] of [[0, 0, 1, W.red], [.16, .1, .65, W.red], [-.14, .12, .55, '#e8b46a'], [.05, -.16, .45, W.red]]) {
    put(lathe([[.03, 0], [.04 * s + .01, .02], [.035 * s + .01, .16 * s], [0, .16 * s]], 12), W.cream, { p: [x, 0, z] });
    put(ball(.12 * s, 18, 12, 0, Math.PI * 2, 0, Math.PI / 2), c, { p: [x, .14 * s, z], s: [1, .8, 1] });
    for (let k = 0; k < 5; k++) { const a = k * 1.3; put(ball(.018 * s, 8, 6), W.white, { p: [x + Math.cos(a) * .07 * s, .2 * s + Math.sin(k) * .01, z + Math.sin(a) * .07 * s] }); }
  }
  for (let k = 0; k < 5; k++) put(blob(.05, 1, .5), W.leaf, { p: [(R() - .5) * .4, .02, (R() - .5) * .4] });
}

export function birdhouse(o) {
  const put = putter(o);
  put(cyl(.025, .03, 1.0, 8), W.woodD, { p: [0, .5, 0] });
  put(rb(.24, .24, .22, .03), W.blue, { p: [0, 1.1, 0] });
  for (const s of [-1, 1]) put(rb(.22, .02, .28, .01), W.red, { p: [s * .07, 1.27, 0], r: [0, 0, s * -.75] });
  put(cyl(.04, .04, .01, 16), '#3a302c', { p: [0, 1.12, .112], r: [Math.PI / 2, 0, 0] });
  put(cyl(.008, .008, .06, 6), W.woodD, { p: [0, 1.06, .13], r: [Math.PI / 2, 0, 0] });
  put(ball(.035, 10, 8), '#e8b46a', { p: [.06, 1.25, .1] });
  put(ball(.02, 8, 6), '#e8b46a', { p: [.09, 1.28, .12] });
  put(cone(.008, .02, 4), '#f0a040', { p: [.1, 1.28, .14], r: [Math.PI / 2, 0, 0] });
}

export function reeds(o) {
  const put = putter(o);
  for (let k = 0; k < 9; k++) {
    const x = (R() - .5) * .5, z = (R() - .5) * .4, h = .4 + R() * .3, tilt = (R() - .5) * .2;
    put(cyl(.006, .01, h, 4), W.greenD, { p: [x, h / 2, z], r: [tilt, 0, tilt] });
    if (k % 2) put(capsule(.02, .08), '#8a5a3c', { p: [x + tilt * h * .5, h, z - tilt * h * .5] });
    else put(cone(.02, .3, 3), W.green, { p: [x, .15, z], r: [0, k, (R() - .5) * .6], s: [1, 1, .2] });
  }
}

export function stones(o, d) {
  const put = putter(o);
  for (let i = 0; i < Math.max(3, d.w * 2); i++) put(cyl(.15 + R() * .05, .17, .05, 10), jit(W.stone, .06), { p: [-d.w / 2 + .25 + i * .35, .025, (R() - .5) * .2], s: [1, 1, .8 + R() * .3] });
}

export function lanterns(o, d) {
  const put = putter(o), w = Math.max(1, d.w * .85);
  for (const sx of [-1, 1]) put(cyl(.02, .025, 1.1, 8), W.woodD, { p: [sx * w / 2, .55, 0] });
  const n = 7;
  for (let k = 0; k <= n; k++) {
    const t = k / n, x = -w / 2 + t * w, y = 1.05 - Math.sin(t * Math.PI) * .22;
    if (k < n) { const x2 = -w / 2 + (k + 1) / n * w, y2 = 1.05 - Math.sin((k + 1) / n * Math.PI) * .22; put(cyl(.004, .004, Math.hypot(x2 - x, y2 - y), 4), '#5a4a40', { p: [(x + x2) / 2, (y + y2) / 2, 0], r: [0, 0, Math.atan2(y2 - y, x2 - x) - Math.PI / 2] }); }
    if (k > 0 && k < n) put(ball(.04, 10, 8), ['#f6d79a', '#f3b4c0', '#bfe0e8'][k % 3], { p: [x, y - .06, 0], s: [1, 1.2, 1], mat: 'glow' });
  }
}

export function windmill(o) {
  const put = putter(o);
  put(cyl(.5, .58, .2, 8), W.stoneD, { p: [0, .1, -.4] });
  const body = lathe([[.5, 0], [.45, .8], [.38, 1.6]], 8); body.rotateY(Math.PI / 8);
  put(body, W.cream, { p: [0, .2, -.4] });
  for (const y of [.7, 1.3]) put(rb(.16, .22, .04, .03), W.blueD, { p: [0, .2 + y, -.4 + .46 - y * .04] });
  put(rb(.24, .4, .05, .06), W.woodD, { p: [0, .4, .1] });
  put(cone(.48, .6, 8), W.red, { p: [0, 2.1, -.4], r: [0, Math.PI / 8, 0] });
  put(ball(.05, 10, 8), W.gold, { p: [0, 2.42, -.4], mat: 'gold' });
  put(cyl(.06, .06, .3, 10), W.woodD, { p: [0, 1.82, -.05], r: [Math.PI / 2, 0, 0] });
  for (let k = 0; k < 4; k++) {
    const m = new THREE.Matrix4().makeRotationZ(k * Math.PI / 2 + .3).setPosition(o.cx, o.t + 1.82, o.cz + .12);
    bake(box(.04, 1.0, .03), W.woodD, { matrix: m, p: [0, .5, 0] });
    bake(box(.22, .78, .015), W.canvas, { matrix: m, p: [.12, .58, .01] });
    for (let i = 0; i < 4; i++) bake(box(.22, .01, .02), W.woodD, { matrix: m, p: [.12, .25 + i * .2, .015] });
  }
}

export function wheat(o) {
  const put = putter(o);
  for (let k = 0; k < 14; k++) {
    const x = (R() - .5) * .6, z = (R() - .5) * .5, h = .45 + R() * .15, tilt = (R() - .5) * .25;
    put(cyl(.006, .008, h, 4), W.strawD, { p: [x, h / 2, z], r: [tilt, 0, tilt] });
    for (let i = 0; i < 4; i++) for (const s of [-1, 1]) put(ball(.016, 6, 4), W.straw, { p: [x + tilt * h * .5 + s * .012, h - .02 + i * .03, z - tilt * h * .5], s: [1, 1.5, 1] });
  }
}

export function coralPink(o) {
  const put = putter(o);
  const branch = (x, y, z, a, l, dep) => {
    const ex = x + Math.sin(a) * l, ey = y + Math.cos(a) * l;
    put(capsule(.03 - dep * .006, l), W.coral, { p: [(x + ex) / 2, (y + ey) / 2, z], r: [0, 0, -a] });
    if (dep < 2) { branch(ex, ey, z, a - .5, l * .7, dep + 1); branch(ex, ey, z + .03, a + .45, l * .65, dep + 1); }
  };
  for (const [x, z] of [[0, 0], [.18, .1], [-.15, .08]]) branch(x, 0, z, (R() - .5) * .3, .18, 0);
  for (let k = 0; k < 6; k++) put(ball(.03, 8, 6), '#f6b1a9', { p: [(R() - .5) * .4, .03, (R() - .5) * .3] });
}

export function seaweed(o) {
  const put = putter(o);
  for (let k = 0; k < 5; k++) {
    const x = (R() - .5) * .4, z = (R() - .5) * .3;
    for (let i = 0; i < 6; i++) put(capsule(.03, .06), i % 2 ? '#5f9a7a' : '#4f8a6a', { p: [x + Math.sin(i * .9 + k) * .04, .05 + i * .08, z], r: [0, 0, Math.sin(i + k) * .3] });
  }
}

export function snowman(o) {
  const put = putter(o);
  put(ball(.28, 24, 18), W.snow, { p: [0, .26, 0] });
  put(ball(.2, 24, 18), W.snow, { p: [0, .64, 0] });
  put(ball(.15, 24, 18), W.snow, { p: [0, .94, 0] });
  for (const y of [.55, .66, .77]) put(ball(.022, 8, 6), '#3a3434', { p: [0, y, .195] });
  for (const sx of [-1, 1]) put(ball(.02, 8, 6), '#3a3434', { p: [sx * .05, .98, .135] });
  put(cone(.025, .14, 10), '#f0a040', { p: [0, .94, .2], r: [Math.PI / 2, 0, 0] });
  put(torus(.15, .04, 8, 20), W.red, { p: [0, .8, 0], r: [Math.PI / 2, 0, 0] });
  put(rb(.08, .2, .03, .01), W.red, { p: [.08, .7, .15], r: [0, 0, .2] });
  put(cyl(.13, .13, .02, 20), '#3a3434', { p: [0, 1.06, 0] });
  put(cyl(.09, .09, .16, 20), '#3a3434', { p: [0, 1.15, 0] });
  put(cyl(.092, .092, .03, 20), W.red, { p: [0, 1.1, 0] });
  for (const sx of [-1, 1]) put(cyl(.012, .008, .32, 5), W.woodD, { p: [sx * .3, .7, 0], r: [0, 0, sx * -1.1] });
}

export function sled(o) {
  const put = putter(o);
  for (const sz of [-1, 1]) { put(torus(.08, .014, 6, 12, Math.PI), W.iron, { p: [.32, .1, sz * .17], r: [0, 0, -Math.PI / 2] }); put(box(.64, .02, .02), W.iron, { p: [0, .02, sz * .17] }); for (const x of [-.2, .15]) put(box(.02, .12, .02), W.iron, { p: [x, .08, sz * .17] }); }
  for (let i = 0; i < 5; i++) put(rb(.12, .03, .42, .01), i % 2 ? W.red : W.woodL, { p: [-.25 + i * .12, .15, 0] });
  put(rb(.5, .12, .3, .04), '#9fc3d4', { p: [-.05, .23, 0] });
  for (let k = 0; k < 2; k++) put(rb(.14, .14, .14, .02), [W.red, '#a3c47f'][k], { p: [-.15 + k * .18, .36, 0], r: [0, k, 0] });
}
