// 浴室那栋：新巴洛克小殿（照她给的铜绿穹顶参考）——米色砂岩、四角方塔、正中氧化铜绿的大穹顶、
// 穹顶上一圈圆窗和金色顶亭，正面两对柱子托着弧形山花、拱形大窗，门口台阶。
import * as THREE from 'three';
import { bake, box, cyl, cone, ball, torus, lathe } from './kit.js';

const C = { sand: '#efe3cc', sandD: '#ddcdb1', sandL: '#f8f0e1', copper: '#79b3a0', copperD: '#5f9886', copperL: '#94c7b5', gold: '#d2ab5f', orange: '#d98a52', glass: '#7fa6be', door: '#8a4a32' };
function maker(o) {
  const O = new THREE.Matrix4().makeTranslation(o.cx, o.t, o.cz);
  return (geo, color, opt = {}) => bake(geo, color, { ...opt, matrix: opt.m ? O.clone().multiply(opt.m) : O, ao: null });
}
const M = (x, y, z, ry = 0) => new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z);
const rb = (w, h, d, r = .02) => box(w, h, d, r, 3);
const COL = (h) => lathe([[.07, 0], [.07, .04], [.055, .07], [.05, h * .9], [.065, h * .94], [.08, h]], 14);

function archWin(put, m, w, h) {
  const s = new THREE.Shape(); s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, h - w / 2); s.absarc(0, h - w / 2, w / 2, 0, Math.PI, false); s.closePath();
  const fr = new THREE.Shape(); fr.moveTo(-w / 2 - .05, -.02); fr.lineTo(w / 2 + .05, -.02); fr.lineTo(w / 2 + .05, h - w / 2); fr.absarc(0, h - w / 2, w / 2 + .05, 0, Math.PI, false); fr.closePath(); fr.holes.push(s);
  put(new THREE.ExtrudeGeometry(fr, { depth: .05, bevelEnabled: false, curveSegments: 14 }), C.sandL, { m });
  put(new THREE.ExtrudeGeometry(s, { depth: .01, bevelEnabled: false, curveSegments: 14 }), C.glass, { m, p: [0, 0, .01], mat: 'glass' });
  put(box(.015, h, .02), C.sandL, { m, p: [0, h / 2, .03] });
  put(box(w, .015, .02), C.sandL, { m, p: [0, (h - w / 2) * .6, .03] });
  put(rb(.07, .09, .06, .01), C.sandL, { m, p: [0, h + .03, .04] });   // 拱心石
  put(rb(w + .16, .04, .1, .01), C.sandL, { m, p: [0, -.03, .05] });
}

export function baroque(o, d) {
  const put = maker(o);
  const w = 3.0, dp = 2.2, fz = .35, zc = fz - dp / 2, h = 1.3, base = .25;
  put(rb(w + .2, base, dp + .2, .03), C.sandD, { p: [0, base / 2, zc] });
  put(rb(w, h, dp, .02), C.sand, { p: [0, base + h / 2, zc] });
  // 檐口：一道线脚 + 一排齿饰 + 顶上一圈石栏
  put(rb(w + .12, .08, dp + .12, .02), C.sandL, { p: [0, base + h, zc] });
  for (let x = -w / 2 + .05; x < w / 2; x += .08) put(box(.04, .04, .04), C.sandL, { p: [x, base + h - .07, fz + .02] });
  for (let x = -w / 2 + .1; x < w / 2 - .05; x += .07) put(lathe([[.02, 0], [.014, .04], [.025, .08], [.012, .13], [.018, .15]], 8), C.sandL, { p: [x, base + h + .04, fz + .02] });
  put(rb(w + .06, .04, .1, .01), C.sandL, { p: [0, base + h + .21, fz + .02] });
  // 正面：两对柱子、弧形山花、拱形大窗；两边各一扇拱窗
  for (const sx of [-1, 1]) for (const k of [0, 1]) put(COL(h - .05), C.sandL, { p: [sx * (.38 + k * .2), base, fz + .1] });
  put(rb(1.1, .1, .22, .02), C.sandL, { p: [0, base + h - .02, fz + .1] });
  const ps = new THREE.Shape(); ps.moveTo(-.6, 0); ps.lineTo(.6, 0); ps.quadraticCurveTo(0, .55, -.6, 0);
  put(new THREE.ExtrudeGeometry(ps, { depth: .14, bevelEnabled: true, bevelSize: .02, bevelThickness: .02, bevelSegments: 2 }), C.sandL, { p: [0, base + h + .04, fz + .02] });
  put(torus(.08, .02, 8, 18), C.gold, { p: [0, base + h + .17, fz + .17], mat: 'gold' });
  archWin(put, M(0, base + .15, fz + .005), .5, .95);
  put(rb(.4, .55, .05, .02), C.door, { p: [0, base + .28, fz + .03] });
  for (const sx of [-1, 1]) { put(ball(.015, 8, 6), C.gold, { p: [sx * .04, base + .3, fz + .06], mat: 'gold' }); archWin(put, M(sx * 1.05, base + .25, fz + .005), .32, .7); }
  for (let i = 0; i < 4; i++) put(rb(1.0 + i * .12, .07, .15, .01), C.sandL, { p: [0, base - .035 - i * .06, fz + .2 + i * .14] });
  // 四角的塔：从地面起凸出来一截塔身（跟主体一样高），檐口以上一层方塔（四角壁柱、四面拱窗），
  // 再上面一圈八根小圆柱撑着檐，铜绿小穹顶坐在柱子上，顶上金尖
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const x = sx * (w / 2 - .05), z = zc + sz * (dp / 2 - .05), th = .55, tw = .56;
    put(rb(tw + .06, base, tw + .06, .02), C.sandD, { p: [x, base / 2, z] });
    put(rb(tw, h, tw, .02), C.sand, { p: [x, base + h / 2, z] });
    for (const [dx, dz] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) put(box(.06, h, .06), C.sandL, { p: [x + dx * tw / 2, base + h / 2, z + dz * tw / 2] });
    if (sz > 0) archWin(put, M(x, base + .25, z + tw / 2 + .005), .2, .55);
    archWin(put, M(x + sx * (tw / 2 + .005), base + .25, z, sx * Math.PI / 2), .2, .55);
    // 方塔
    // 方塔直接坐在下面的塔身上：先一圈挑出来的线脚把两段接住，不留缝
    const y1 = base + h;
    put(rb(tw + .04, .07, tw + .04, .015), C.sandL, { p: [x, y1 + .035, z] });
    put(rb(tw - .06, th + .02, tw - .06, .02), C.sand, { p: [x, y1 + th / 2 + .02, z] });
    for (const [dx, dz] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) put(box(.06, th, .06), C.sandL, { p: [x + dx * (tw - .06) / 2, y1 + th / 2, z + dz * (tw - .06) / 2] });
    for (const a of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) archWin(put, M(x + Math.sin(a) * ((tw - .06) / 2 + .005), y1 + .13, z + Math.cos(a) * ((tw - .06) / 2 + .005), a), .14, .3);
    put(rb(tw + .02, .06, tw + .02, .01), C.sandL, { p: [x, y1 + th + .03, z] });
    // 柱亭：圆台座、八根柱子、柱顶一整圈柱上楣（檐底、中间一圈、檐口），小穹顶的底边跟檐口一样宽，正好压在柱子上
    const y2 = y1 + th + .06, ch = .32, cr = .17;
    put(cyl(cr + .06, cr + .07, .05, 20), C.sandL, { p: [x, y2 + .025, z] });
    put(cyl(cr + .03, cr + .03, .03, 20), C.sandD, { p: [x, y2 + .065, z] });
    put(cyl(cr - .045, cr - .045, ch, 14), C.glass, { p: [x, y2 + .08 + ch / 2, z], mat: 'glass' });
    for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2 + Math.PI / 8; put(COL(ch), C.sandL, { p: [x + Math.cos(a) * cr, y2 + .08, z + Math.sin(a) * cr], s: [.6, 1, .6] }); }
    const ye = y2 + .08 + ch;
    put(cyl(cr + .045, cr + .045, .035, 20), C.sandL, { p: [x, ye + .0175, z] });
    put(cyl(cr + .035, cr + .035, .05, 20), C.sand, { p: [x, ye + .06, z] });
    put(cyl(cr + .08, cr + .05, .035, 20), C.sandL, { p: [x, ye + .1, z] });
    put(torus(cr + .036, .008, 6, 24), C.gold, { p: [x, ye + .06, z], r: [Math.PI / 2, 0, 0], mat: 'gold' });
    // 小穹顶
    const y3 = ye + .115;
    put(lathe([[cr + .06, 0], [cr + .055, .05], [cr + .01, .15], [.07, .23], [.02, .27], [0, .28]], 20), C.copper, { p: [x, y3, z] });
    put(cyl(.035, .045, .1, 8), C.orange, { p: [x, y3 + .32, z] });
    put(ball(.035, 10, 8), C.gold, { p: [x, y3 + .41, z], mat: 'gold' });
    put(cone(.014, .13, 6), C.gold, { p: [x, y3 + .5, z], mat: 'gold' });
  }
  // 正中大穹顶：圆鼓座（一圈圆窗和壁柱）、铜绿穹顶（八道肋）、金色顶亭
  const dy = base + h + .2, R0 = .85;
  put(cyl(R0 + .05, R0 + .08, .5, 32), C.sand, { p: [0, dy + .25, zc] });
  for (let k = 0; k < 12; k++) {
    const a = k / 12 * Math.PI * 2;
    put(box(.07, .5, .05), C.sandL, { p: [Math.cos(a) * (R0 + .08), dy + .25, zc + Math.sin(a) * (R0 + .08)], r: [0, -a + Math.PI / 2, 0] });
    const b = a + Math.PI / 12;
    put(torus(.07, .02, 6, 14), C.sandL, { p: [Math.cos(b) * (R0 + .07), dy + .27, zc + Math.sin(b) * (R0 + .07)], r: [0, -b + Math.PI / 2, 0] });
    put(cyl(.06, .06, .01, 12), C.glass, { p: [Math.cos(b) * (R0 + .065), dy + .27, zc + Math.sin(b) * (R0 + .065)], r: [Math.PI / 2, 0, -b + Math.PI / 2], mat: 'glass' });
  }
  put(cyl(R0 + .14, R0 + .14, .06, 32), C.sandL, { p: [0, dy + .52, zc] });
  const prof = [[R0 + .05, 0], [R0, .2], [R0 * .9, .45], [R0 * .7, .7], [R0 * .42, .88], [R0 * .2, .95], [0, .97]];
  put(lathe(prof, 32), C.copper, { p: [0, dy + .55, zc] });
  for (let k = 0; k < 8; k++) {
    const a = k / 8 * Math.PI * 2;
    for (let i = 0; i < prof.length - 2; i++) {
      const [r0, y0] = prof[i], [r1, y1] = prof[i + 1];
      const p0 = new THREE.Vector3(Math.cos(a) * r0, dy + .55 + y0, zc + Math.sin(a) * r0), p1 = new THREE.Vector3(Math.cos(a) * r1, dy + .55 + y1, zc + Math.sin(a) * r1);
      const mm = new THREE.Matrix4().lookAt(p0, p1, new THREE.Vector3(0, 1, 0)).setPosition(p0.clone().add(p1).multiplyScalar(.5));
      put(box(.05, .04, p0.distanceTo(p1) + .02), C.copperD, { m: mm });
    }
    const b = a + Math.PI / 8, rr = R0 * .78;   // 穹顶上的小圆窗
    put(torus(.06, .018, 6, 14), C.copperL, { p: [Math.cos(b) * rr, dy + .55 + .62, zc + Math.sin(b) * rr], r: [-.7, -b + Math.PI / 2, 0] });
  }
  // 顶亭：一圈小柱、橙色的小穹顶、金球和金尖
  const ly = dy + .55 + .95;
  put(cyl(.22, .24, .05, 16), C.sandL, { p: [0, ly, zc] });
  for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2; put(cyl(.018, .018, .24, 6), C.sandL, { p: [Math.cos(a) * .18, ly + .14, zc + Math.sin(a) * .18] }); }
  put(cyl(.12, .12, .22, 12), C.glass, { p: [0, ly + .14, zc], mat: 'glass' });
  put(cyl(.23, .23, .04, 16), C.sandL, { p: [0, ly + .27, zc] });
  put(lathe([[.2, 0], [.18, .08], [.1, .16], [0, .2]], 16), C.orange, { p: [0, ly + .29, zc] });
  put(ball(.05, 12, 10), C.gold, { p: [0, ly + .52, zc], mat: 'gold' });
  put(cone(.02, .25, 6), C.gold, { p: [0, ly + .68, zc], mat: 'gold' });
}
