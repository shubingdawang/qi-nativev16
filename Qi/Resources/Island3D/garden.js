// 庄园花园：修剪过的绿篱和造型树、玫瑰丛、细高的柏树、圆柱邮筒。跟那几栋老房子配
import * as THREE from 'three';
import { bake, R, jit, box, cyl, cone, ball, torus, blob, lathe } from './kit.js';
import { P } from './models.js';

const IRON = '#3f3a3c', GOLD = '#c8a96c';
const HEDGE = '#4a6643', HEDGED = '#3f5a3b', HEDGEL = '#587650';
const putter = (o) => (geo, color, opt = {}) => {
  const p = opt.p || [0, 0, 0];
  return bake(geo, color, { ...opt, ao: opt.ao === false ? null : o.t, p: [o.cx + p[0], o.t + p[1], o.cz + p[2]] });
};

// 黄杨绿篱：修得方方正正的一段，圆角
export function hedge(o, d) {
  const put = putter(o), w = Math.max(.9, d.w * .85);
  put(box(w, .42, .42, .1, 3), HEDGED, { p: [0, .21, 0] });
  put(box(w - .06, .08, .38, .04, 2), HEDGEL, { p: [0, .41, 0], line: 0 });
  for (let i = 0; i < 8; i++) put(ball(.025, 6, 4), HEDGEL, { p: [(R() - .5) * w, .1 + R() * .3, .215], line: 0 });
}
// 球形黄杨
export function boxBall(o) {
  const put = putter(o);
  put(lathe([[0, 0], [.13, 0], [.15, .04], [.12, .16], [.14, .18], [0, .18]], 12), '#cfc6b8', { line: .006 });   // 石盆
  put(blob(.24, 2, 1, .05), HEDGE, { p: [0, .4, 0] });
}
// 玫瑰丛
export function roseBush(o) {
  const put = putter(o);
  for (const [x, z, r] of [[-.18, 0, .22], [.18, .03, .21], [0, -.08, .26], [0, .12, .18]]) put(blob(r, 1, .85), jit(P.leafD, .05), { p: [x, r * .8, z] });
  for (let i = 0; i < 14; i++) {
    const a = R() * 6.28, dd = .24 + R() * .06, y = .15 + R() * .3, c = jit(R() < .5 ? '#d98f98' : '#eec2c6', .05);
    put(ball(.04, 8, 6), c, { p: [Math.cos(a) * dd, y, Math.sin(a) * dd * .8], line: .005 });
    put(torus(.022, .008, 4, 8), new THREE.Color(c).multiplyScalar(.85), { p: [Math.cos(a) * dd, y + .02, Math.sin(a) * dd * .8], r: [Math.PI / 2, 0, 0], line: 0 });
  }
}
// 棒棒糖造型树：细树干、一个圆球，底下一圈小绿篱
export function lollipop(o, s = 1) {
  const put = putter(o);
  put(cyl(.035, .045, .7 * s, 8), P.trunk, { p: [0, .35 * s, 0] });
  put(blob(.3 * s, 2, 1, .05), HEDGE, { p: [0, .82 * s, 0] });
  put(blob(.16 * s, 1, 1, .05), HEDGEL, { p: [-.06, .98 * s, .08], line: 0 });
  put(torus(.16, .06, 6, 16), HEDGED, { p: [0, .05, 0], r: [Math.PI / 2, 0, 0], line: .008 });
}
// 圆锥造型树（也可以是三层的螺旋塔）
export function coneTopiary(o, s = 1, tiers = false) {
  const put = putter(o);
  put(lathe([[0, 0], [.15, 0], [.17, .05], [.13, .18], [.16, .2], [0, .2]], 12), '#cfc6b8', { line: .006 });
  if (tiers) for (let i = 0; i < 3; i++) put(blob(.22 * s * (1 - i * .25), 1, .75, .05), jit(HEDGE, .03), { p: [0, .32 + i * .3 * s, 0] });
  else { put(cone(.26 * s, 1.0 * s, 16), HEDGE, { p: [0, .2 + .5 * s, 0] }); put(torus(.17 * s, .02, 4, 16), HEDGEL, { p: [0, .2 + .5 * s, 0], r: [Math.PI / 2, 0, 0], line: 0 }); }
}
// 意大利柏树：细高的一支
export function cypress(o, s = 1) {
  const put = putter(o);
  put(cyl(.04, .05, .2, 6), P.trunk, { p: [0, .1, 0] });
  const g = new THREE.SphereGeometry(.26 * s, 14, 12); g.scale(1, 3.6, 1);
  { const pa = g.attributes.position; for (let i = 0; i < pa.count; i++) { const y = pa.getY(i); const k = y > 0 ? 1 - y / (.26 * s * 3.6) * .45 : 1; pa.setX(i, pa.getX(i) * k); pa.setZ(i, pa.getZ(i) * k); } g.computeVertexNormals(); }
  put(g, jit('#5f7f5a', .04), { p: [0, .2 + .26 * s * 3.6, 0] });
  for (let i = 0; i < 5; i++) put(blob(.08 * s, 1), '#6f8f68', { p: [(R() - .5) * .2, .4 + R() * 1.3 * s, .18 * s], line: 0 });
}
// 维多利亚圆柱邮筒
export function pillarBox(o) {
  const put = putter(o), RED = '#a85a5a';
  put(cyl(.15, .17, .08, 16), RED, { p: [0, .04, 0] });
  put(cyl(.13, .13, .62, 16), RED, { p: [0, .39, 0] });
  put(torus(.135, .015, 4, 18), '#8f4a4a', { p: [0, .58, 0], r: [Math.PI / 2, 0, 0], line: 0 });
  put(cyl(.17, .15, .06, 16), RED, { p: [0, .73, 0] });
  put(ball(.15, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), RED, { p: [0, .76, 0], s: [1, .7, 1] });
  put(ball(.03, 8, 6), GOLD, { p: [0, .88, 0], line: .004 });
  put(box(.13, .025, .02), IRON, { p: [0, .62, .13], line: 0 });
  put(box(.07, .05, .01), GOLD, { p: [0, .48, .132], line: 0 });
}
// 石头鸟浴盆（给零星的花丛换个样子用）
export function birdbath(o) {
  const put = putter(o);
  put(lathe([[0, 0], [.12, 0], [.12, .04], [.05, .08], [.04, .35], [.06, .4], [.22, .46], [.24, .5], [0, .5]], 14), '#d6cdbf', { line: .008 });
  put(cyl(.2, .2, .015, 14), '#a9cbd8', { p: [0, .49, 0], line: 0 });
}
