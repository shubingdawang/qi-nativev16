// 她和 clawd：还是潮玩手办的比例（大头、短身子、哑光软胶），但每一块都按真东西的形状捏：
// - 头：不是正圆，脸颊鼓、下巴收、后脑勺圆
// - 头发：一整片头发表面有一缕缕的发丝沟；刘海一簇簇、尖尖的发梢；辫子是三股真的编起来，辫尾散开几缕
// - 毛衣：竖着的针织纹、腰上松松的褶、卷起来的高领；灯笼袖鼓起来、罗纹袖口；手是带大拇指的小手
// - 裙子：一道道压褶，越往下越深，裙摆微微不齐
// - 靴子：鞋头圆圆往前翘、鞋底沿着脚形、靴口翻边、搭扣
// - clawd：软软的方块身子（底下宽一点、肚子微微鼓）、手是一头细的小短手、腿是带圆脚掌的小短腿
// 接口跟原来一样：userData 里的 legs / arms / head / eyes / mouth / oMouth（她），body / arms / legs / eyes（他）
import * as THREE from 'three';
import { stem, leaf, fruit, smooth, deform, pushN, fbm, noise, PETAL } from './sculpt.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
function kit(grp) {
  const mats = new Map();
  const matOf = (c, rough, side) => { const k = c + rough + side; if (!mats.has(k)) mats.set(k, new THREE.MeshStandardMaterial({ color: c, roughness: rough, metalness: 0, side })); return mats.get(k); };
  return (geo, c, p = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1], parent = grp, rough = .55, side = THREE.FrontSide) => {
    const mesh = new THREE.Mesh(geo, matOf(c, rough, side));
    mesh.position.set(...p); mesh.rotation.set(...r); mesh.scale.set(...s); parent.add(mesh);
    mesh.castShadow = true;
    return mesh;
  };
}
const lathe = (pts, seg = 48) => new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(x, y)), seg);

// ———————————————— 她 ————————————————
const SKIN = '#f8dfd2', HAIR = '#5b3a2e', HAIRL = '#6c4636', PINK = '#eba7b3', PINKD = '#d98a99', CREAM = '#f7efe6', BOOT = '#6f4337', BOOTL = '#8a5747', SOLE = '#2b2526', BOW = '#f08ea0';
const HR = .3;   // 头的半径

// 头：脸颊往两边鼓、下巴往里收一点、头顶稍微扁
function headGeo() {
  const g = smooth(new THREE.SphereGeometry(1, 56, 40));
  deform(g, (v) => {
    let { x, y, z } = v;
    const cheek = Math.exp(-((y + .32) ** 2) / .07) * Math.max(0, z + .3);   // 脸颊：前面偏下那一圈
    x *= 1.06 * (1 + .07 * cheek); z *= .98 * (1 + .03 * cheek);
    if (y < -.55) { const t = (-y - .55) / .45; x *= 1 - .22 * t * t; z *= 1 - .1 * t * t; }   // 下巴
    if (y > .5) y = .5 + (y - .5) * .9;   // 头顶稍扁
    v.set(x * HR, y * .98 * HR, z * HR);
  });
  g.computeVertexNormals();
  return g;
}
// 头发表面：一缕缕发丝沟（顺着从头顶往下的方向）；发际线前高后低——额头上方收住（刘海从那儿盖下来），后面一直盖到后颈
function hairShell({ lift = 1.07, seed = 0, flare = .06 } = {}) {
  const g = smooth(new THREE.SphereGeometry(1, 72, 48));
  deform(g, (v) => {
    const hz = Math.hypot(v.x, v.z) || 1, front = Math.max(0, Math.min(1, (v.z / hz - .55) / .4));   // 只看朝哪个方向（绕头一圈），不看高低
    // 发际线：正脸那一块（左右五十多度）收到额头上方，两边鬓角垂到脸颊旁边，后面盖到后颈
    const back = Math.max(0, -v.z / hz), hl = -.55 - .27 * back + (.52 + .55) * front * front * (3 - 2 * front);
    if (v.y < hl) { const h = Math.sqrt(Math.max(0, 1 - hl * hl)), k = h / (Math.hypot(v.x, v.z) || 1); v.set(v.x * k, hl, v.z * k); }
    const r = v.length(), th = Math.acos(v.y / r), ph = Math.atan2(v.z, v.x);
    const groove = Math.pow(Math.abs(Math.sin(ph * 26 + noise(Math.cos(ph) * 2, th * 3, Math.sin(ph) * 2, seed) * 2.5)), 6);   // 发丝之间的细沟
    const vol = 1 + .04 * Math.sin(th * 1.6) - .024 * groove * Math.min(1, th * 2) + flare * Math.pow(Math.max(0, th - 1.6) / 1.2, 2) * (1 - front);
    let x = v.x;
    const cheek = Math.exp(-((v.y + .32) ** 2) / .07) * Math.max(0, v.z + .3);
    x *= 1.06 * (1 + .07 * cheek);
    v.set(x * HR * lift * vol, v.y * .98 * HR * lift * vol, v.z * HR * lift * vol);
  });
  g.computeVertexNormals();
  return g;
}
// 刘海：额前一片，分成一簇簇，每簇下面是尖尖的发梢，簇和簇之间一道沟
function bangsGeo() {
  const g = smooth(new THREE.SphereGeometry(1, 96, 24, Math.PI / 2 - 1.3, 2.6, 0, 1.0));
  const clumps = 9;
  deform(g, (v) => {
    const r = v.length(); let th = Math.acos(v.y / r); const ph = Math.atan2(v.z, -v.x);   // ph：从左到右
    const u = (ph - (Math.PI / 2 - 1.3)) / 2.6;   // 0 ~ 1
    const f = u * clumps, c = Math.floor(f), t = f - c;
    const len = .2 + .08 * Math.sin(c * 2.3 + 1) + .06 * (1 - Math.abs(u - .5) * 2);   // 每簇长短不一，中间长
    const tip = Math.pow(1 - Math.abs(t * 2 - 1), 1.6);   // 尖：簇中间最长、两边收上去
    if (th > .55) th = .55 + (th - .55) * (1.6 + len * tip * 1.9);   // 簇和簇之间也盖过发际线，簇尖垂到眉毛
    const groove = Math.pow(1 - Math.abs(t * 2 - 1), .35);   // 簇和簇之间往里凹一点
    const k = 1.075 * (1 + .015 * groove + .03 * Math.sin(th * 2));
    const s = Math.sin(th);
    v.set(-Math.cos(ph) * s * k, Math.cos(th) * k, Math.sin(ph) * s * k);
    const cheek = Math.exp(-((v.y + .32) ** 2) / .07) * Math.max(0, v.z + .3);
    v.x *= 1.06 * (1 + .07 * cheek);
    v.multiplyScalar(HR); v.y *= .98;
  });
  g.computeVertexNormals();
  return g;
}
// 三股辫：三根发束绕着中线一左一右交叉压着往下编，越往下越细
function braid(m, parent, len, r0, color, colorL) {
  const N = 3, turns = 3.2, pts = [[], [], []];
  for (let i = 0; i <= 60; i++) {
    const t = i / 60, s = t * turns * Math.PI * 2, w = (1 - t * .45);
    for (let k = 0; k < N; k++) {
      const ph = s + k * Math.PI * 2 / 3;
      pts[k].push(V(Math.sin(ph) * r0 * .75 * w, -t * len, Math.sin(ph * 2) * r0 * .35 * w + .002 * k));
    }
  }
  pts.forEach((p, k) => m(stem(p, r0 * .62, r0 * .4, { seg: 90, rad: 10, cap: false, seed: k }), k === 1 ? colorL : color, [0, 0, 0], [0, 0, 0], [1, 1, 1], parent, .6));
}
// 辫尾：几缕往外散开、尖尖的
function tuft(m, parent, y, n, len, color) {
  for (let i = 0; i < n; i++) {
    const a = i / n * Math.PI * 2 + .3, sp = .3 + (i % 2) * .2;
    m(stem([V(0, y, 0), V(Math.cos(a) * len * .15, y - len * .5, Math.sin(a) * len * .15), V(Math.cos(a) * len * sp, y - len, Math.sin(a) * len * sp * .7)], .02, .002, { seg: 10, rad: 7, seed: i }), color, [0, 0, 0], [0, 0, 0], [1, 1, 1], parent, .6);
  }
}
// 蝴蝶结：两片鼓起来的环（缎带对折成圈）、中间打结、底下两条飘带
function bowKnot(m, parent) {
  for (const sx of [-1, 1]) {
    // 环：一条缎带绕一圈，中间鼓、两头捏扁
    const pts = []; for (let i = 0; i <= 24; i++) { const a = i / 24 * Math.PI * 2; pts.push(V(sx * (.06 - Math.cos(a) * .055), Math.sin(a) * .04, 0)); }
    const g = stem(pts, .022, .022, { seg: 48, rad: 10, cap: false });
    deform(g, (v) => { const k = Math.min(1, Math.abs(v.x) / .05); v.z *= .45; v.y *= .55 + .55 * k; });
    g.computeVertexNormals();
    m(g, BOW, [0, 0, 0], [0, 0, sx * .2], [1, 1, 1], parent, .4);
    m(leaf({ len: .085, wid: .035, shape: (u) => Math.pow(Math.sin(Math.PI * Math.min(.5, u) * 1) , .6) * (1 - .25 * u), droop: .5, fold: .3, curl: .3, segL: 8, segW: 2 }), BOW, [0, -.01, .004], [0, sx > 0 ? 0 : Math.PI, -1.15], [1, 1, 1], parent, .4, THREE.DoubleSide);
  }
  m(fruit(.024, { sx: .9, sy: 1.15, sz: .7, lump: .05, dent: .05 }), '#e57d91', [0, 0, .006], [0, 0, 0], [1, 1, 1], parent, .4);
}

export function figureHer() {
  const grp = new THREE.Group(), m = kit(grp);
  // ———— 腿和靴子（绕胯转）————
  const legs = [-1, 1].map((sx) => {
    const l = new THREE.Group(); l.position.set(sx * .085, .3, 0); grp.add(l);
    m(stem([V(0, .02, 0), V(0, -.07, .004), V(0, -.19, 0)], .047, .04, { seg: 8, rad: 14, cap: false }), SKIN, [0, 0, 0], [0, 0, 0], [1, 1, 1], l, .6);
    // 靴筒：往上微微张开
    m(lathe([[.049, 0], [.052, .03], [.054, .08], [.058, .11]], 40), BOOT, [0, -.285, -.004], [0, 0, 0], [1, 1, 1], l, .45, THREE.DoubleSide);
    // 靴口翻边：一圈软软的、有起伏的翻边
    const cuff = new THREE.TorusGeometry(.058, .016, 12, 40); deform(cuff, (v) => { v.z += Math.sin(Math.atan2(v.y, v.x) * 5) * .004; });
    cuff.computeVertexNormals();
    m(cuff, BOOTL, [0, -.172, -.004], [Math.PI / 2, 0, 0], [1, 1, 1], l, .5);
    // 鞋：一只鞋的形状——后跟圆、脚背高、鞋头圆圆往前一点并微微翘
    const foot = smooth(new THREE.SphereGeometry(1, 32, 20));
    deform(foot, (v) => {
      let { x, y, z } = v;
      const front = Math.max(0, z);
      y = y < 0 ? y * .35 : y * (1 - .45 * front);   // 底平、鞋头矮
      if (z > .6 && y > -.2) y += (z - .6) * .12;   // 鞋头翘
      v.set(x * .062 * (1 + .1 * front), y * .07, z * .1);
    });
    foot.computeVertexNormals();
    m(foot, BOOT, [0, -.265, .022], [0, 0, 0], [1, 1, 1], l, .45);
    // 鞋底：顺着脚的轮廓压一圈厚底
    const sh = new THREE.Shape(); for (let i = 0; i <= 40; i++) { const a = i / 40 * Math.PI * 2, z = Math.sin(a), k = 1 + .12 * Math.max(0, z); const px = Math.cos(a) * .064 * k, pz = z * .104; i ? sh.lineTo(px, pz) : sh.moveTo(px, pz); }
    const sole = new THREE.ExtrudeGeometry(sh, { depth: .018, bevelEnabled: true, bevelSize: .005, bevelThickness: .005, bevelSegments: 3, curveSegments: 40 });
    sole.rotateX(Math.PI / 2);
    m(sole, SOLE, [0, -.268, .02], [0, 0, 0], [1, 1, 1], l, .75);
    // 搭扣带：绕过脚背的一条弯弯的带子，金色小扣
    const strap = new THREE.TorusGeometry(.064, .008, 6, 32, Math.PI); strap.scale(1, .6, 1);
    m(strap, BOOTL, [0, -.245, .05], [0, 0, 0], [1, 1, 1], l, .5);
    m(new THREE.TorusGeometry(.009, .003, 6, 12), '#d8b878', [sx * .045, -.232, .05], [0, sx * .9, 0], [1, 1, 1], l, .3);
    return l;
  });
  // ———— 裙子：一道道压褶，越往下褶越深，裙摆微微不齐 ————
  const sk = lathe([[.13, .49], [.15, .45], [.19, .37], [.222, .31], [.228, .292]].reverse(), 96);
  deform(sk, (v) => {
    const a = Math.atan2(v.z, v.x), t = Math.min(1, Math.max(0, (.49 - v.y) / .2));
    const pleat = Math.abs(((a / (Math.PI * 2) * 18) % 1 + 1) % 1 * 2 - 1);   // 三角波：一个个压褶的棱
    const k = 1 + (pleat - .5) * .07 * t;
    v.x *= k; v.z *= k;
    if (t > .9) v.y += noise(Math.cos(a) * 3, 0, Math.sin(a) * 3, 4) * .006;
  });
  sk.computeVertexNormals();
  m(sk, CREAM, [0, 0, 0], [0, 0, 0], [1, 1, 1], grp, .6, THREE.DoubleSide);
  // ———— 毛衣：竖针织纹、腰上松松的褶、高领卷边 ————
  const sw = lathe([[.13, 0], [.16, .015], [.172, .06], [.178, .12], [.17, .2], [.14, .25], [.09, .285], [.0, .3]], 96);
  deform(sw, (v) => {
    const a = Math.atan2(v.z, v.x);
    const rib = 1 + Math.pow(Math.abs(Math.cos(a * 30)), 3) * .012;   // 针织的竖纹
    const sag = v.y < .1 ? 1 + fbm(Math.cos(a) * 2, v.y * 6, Math.sin(a) * 2, 7) * .05 * (1 - v.y / .1) : 1;   // 下摆松松的褶
    v.x *= rib * sag; v.z *= rib * sag * .86;
  });
  sw.computeVertexNormals();
  m(sw, PINK, [0, .44, 0], [0, 0, 0], [1, 1, 1], grp, .7);
  const hem = new THREE.TorusGeometry(.15, .024, 12, 64); deform(hem, (v) => { const a = Math.atan2(v.y, v.x); v.z += Math.cos(a * 30) * .002; v.x *= 1 + fbm(Math.cos(a) * 2, 0, Math.sin(a) * 2, 7) * .05; v.y *= .86 * (1 + fbm(Math.cos(a) * 2, 0, Math.sin(a) * 2, 7) * .05); });
  hem.computeVertexNormals();
  m(hem, PINKD, [0, .455, 0], [Math.PI / 2, 0, 0], [1, 1, 1], grp, .75);
  // 高领：往下翻的一圈，表面起伏
  const col = lathe([[.072, 0], [.086, .015], [.09, .045], [.08, .07], [.07, .075]], 48);
  deform(col, (v) => { const a = Math.atan2(v.z, v.x); const k = 1 + Math.cos(a * 30) * .015 + Math.sin(a * 3) * .02; v.x *= k; v.z *= k; });
  col.computeVertexNormals();
  m(col, PINK, [0, .725, 0], [0, 0, 0], [1, 1, 1], grp, .7);
  m(new THREE.TorusGeometry(.078, .018, 10, 40), PINKD, [0, .79, 0], [Math.PI / 2, 0, 0], [1, 1, 1], grp, .75);
  // ———— 手臂：灯笼袖鼓起来、罗纹袖口、带大拇指的小手 ————
  const arms = [-1, 1].map((sx) => {
    const a = new THREE.Group(); a.position.set(sx * .16, .68, 0); a.rotation.z = sx * .18; grp.add(a);
    const sl = stem([V(0, .03, 0), V(sx * .012, -.07, .004), V(sx * .014, -.18, 0)], .06, .046, { seg: 16, rad: 18, bulge: .32, cap: false, seed: sx + 2 });
    deform(sl, (v) => { const a2 = Math.atan2(v.z, v.x - sx * .01); const k = 1 + Math.pow(Math.abs(Math.cos(a2 * 7)), 4) * .05 * Math.sin(Math.min(1, Math.max(0, (.02 - v.y) / .2)) * Math.PI); v.x = sx * .01 + (v.x - sx * .01) * k; v.z *= k; });   // 袖子上几道鼓起来的褶
    sl.computeVertexNormals();
    m(sl, PINK, [0, 0, 0], [0, 0, 0], [1, 1, 1], a, .7);
    m(new THREE.SphereGeometry(.06, 24, 16), PINK, [0, .02, 0], [0, 0, 0], [1, 1, 1], a, .7);   // 肩膀圆过去
    const cf = new THREE.CylinderGeometry(.044, .046, .04, 32, 1, true); deform(cf, (v) => { const k = 1 + Math.cos(Math.atan2(v.z, v.x) * 16) * .06; v.x *= k; v.z *= k; });
    cf.computeVertexNormals();
    m(cf, PINKD, [sx * .014, -.2, 0], [0, 0, 0], [1, 1, 1], a, .75);
    // 小手：手掌扁一点，四指并拢成一团，大拇指往前
    const hand = smooth(new THREE.SphereGeometry(1, 24, 18));
    deform(hand, (v) => { v.set(v.x * .036, v.y * .046 * (v.y < 0 ? 1.1 : 1), v.z * .028); });
    hand.computeVertexNormals();
    m(hand, SKIN, [sx * .014, -.255, .004], [0, 0, sx * -.08], [1, 1, 1], a, .6);
    m(stem([V(0, 0, 0), V(-sx * .006, -.012, .014), V(-sx * .006, -.024, .02)], .012, .009, { seg: 6, rad: 10 }), SKIN, [sx * .014 - sx * .02, -.238, .012], [0, 0, 0], [1, 1, 1], a, .6);
    return a;
  });
  // ———— 头 ————
  const head = new THREE.Group(); head.position.y = 1.03; grp.add(head);
  m(headGeo(), SKIN, [0, 0, 0], [0, 0, 0], [1, 1, 1], head, .6);
  // 耳朵：外圈一道耳廓，里面凹一点
  for (const sx of [-1, 1]) {
    const ear = smooth(new THREE.SphereGeometry(1, 20, 14)); deform(ear, (v) => { const inner = Math.max(0, v.x * sx) * Math.exp(-(v.y * v.y + v.z * v.z) * 3); v.set(v.x * .022 - sx * inner * .012, v.y * .055, v.z * .042); });
    ear.computeVertexNormals();
    m(ear, SKIN, [sx * .315, -.04, -.01], [0, 0, 0], [1, 1, 1], head, .6);
  }
  // 眼睛：眼白、大大的棕色瞳孔、黑瞳仁、两点高光，上眼线外眼角翘出两根睫毛
  const eyes = [];
  for (const sx of [-1, 1]) {
    const e = new THREE.Group(); e.position.set(sx * .118, -.045, .265); e.rotation.y = sx * .33; head.add(e); eyes.push(e);
    m(new THREE.SphereGeometry(.062, 32, 24), '#fbfaf8', [0, 0, 0], [0, 0, 0], [1, 1, .38], e, .3);
    m(new THREE.SphereGeometry(.047, 32, 24), '#6b3c2c', [sx * -.006, -.004, .012], [0, 0, 0], [1, 1.08, .4], e, .25);
    m(new THREE.SphereGeometry(.022, 20, 16), '#1e1412', [sx * -.006, -.004, .024], [0, 0, 0], [1, 1.12, .3], e, .2);
    m(new THREE.SphereGeometry(.012, 12, 10), '#ffffff', [sx * -.006 + sx * .014, .016, .031], [0, 0, 0], [1, 1, .3], e, .1);
    m(new THREE.SphereGeometry(.0065, 10, 8), '#ffffff', [sx * -.006 - sx * .012, -.02, .031], [0, 0, 0], [1, 1, .3], e, .1);
    // 上眼线：中间粗、两头细，外眼角那头往上挑
    const lid = []; for (let i = 0; i <= 16; i++) { const t = i / 16, a = Math.PI * (.08 + .84 * t); lid.push(V(Math.cos(a) * .064 * sx, Math.sin(a) * .062 + (t < .2 ? (0.2 - t) * .02 : 0), .014)); }
    m(stem(lid, .006, .006, { seg: 24, rad: 6, bulge: .7 }), '#2b1d18', [0, 0, 0], [0, 0, 0], [1, 1, 1], e, .4);
    for (const k of [0, 1]) m(stem([V(-sx * -.06, .02 - k * .014, .014), V(-sx * -.075, .03 - k * .012, .012), V(-sx * -.084, .046 - k * .01, .008)], .004, .0008, { seg: 6, rad: 4 }), '#2b1d18', [0, 0, 0], [0, 0, 0], [1, 1, 1], e, .4);
    m(fruit(.04, { sx: 1.2, sy: .55, sz: .3, lump: 0, dent: 0 }), '#f3a9a3', [sx * .05, -.085, -.01], [0, 0, 0], [1, 1, 1], e, .7);   // 腮红
  }
  const mouth = m(new THREE.TorusGeometry(.02, .006, 8, 16, Math.PI), '#b9605e', [0, -.15, .287], [0, 0, Math.PI], [1, .8, 1], head, .4);
  const oMouth = m(new THREE.TorusGeometry(.016, .007, 8, 16), '#b9605e', [0, -.15, .287], [0, 0, 0], [1, 1.2, 1], head, .4); oMouth.visible = false;
  m(fruit(.012, { sx: 1, sy: .75, sz: .6, lump: 0, dent: 0 }), '#efc6b4', [0, -.085, .3], [0, 0, 0], [1, 1, 1], head, .6);
  // 头发：后脑和头顶一整片（带发丝沟、后面往下盖到后颈），刘海一簇簇尖尖的
  m(hairShell({ seed: 2 }), HAIR, [0, .012, -.012], [0, 0, 0], [1, 1, 1], head, .62);
  m(bangsGeo(), HAIRL, [0, .018, 0], [0, 0, 0], [1, 1, 1], head, .62);
  // 鬓角：一缕顺着脸边垂下来、发梢往里勾
  for (const sx of [-1, 1]) m(stem([V(sx * .27, .05, .1), V(sx * .3, -.06, .12), V(sx * .28, -.16, .12), V(sx * .25, -.2, .14)], .045, .006, { seg: 16, rad: 10, seed: sx + 5 }), HAIR, [0, 0, 0], [0, 0, 0], [1, 1, .75], head, .62);
  // 两条三股辫：从耳后垂下来，绑粉色发圈，辫尾散开
  for (const sx of [-1, 1]) {
    const b = new THREE.Group(); b.position.set(sx * .27, -.12, -.03); b.rotation.z = sx * .32; head.add(b);
    m(stem([V(0, .1, .02), V(0, .02, 0), V(0, -.06, 0)], .07, .06, { seg: 8, rad: 16 }), HAIR, [0, 0, 0], [0, 0, 0], [1, 1, 1], b, .62);   // 辫根：头发收拢过来
    braid(m, b, .28, .07, HAIR, HAIRL);
    const tie = new THREE.TorusGeometry(.03, .013, 10, 24); deform(tie, (v) => { v.z += noise(v.x * 60, v.y * 60, 0, 3) * .003; }); tie.computeVertexNormals();
    m(tie, BOW, [0, -.3, 0], [Math.PI / 2, 0, 0], [1, 1, 1], b, .4);
    tuft(m, b, -.31, 5, .11, HAIR);
  }
  // 头顶右边的蝴蝶结
  const bow = new THREE.Group(); bow.position.set(.16, .24, .1); bow.rotation.set(.2, .3, -.4); head.add(bow);
  bowKnot(m, bow);
  grp.scale.setScalar(.95);
  grp.userData = { legs, arms, head, eyes, mouth, oMouth };
  return grp;
}

// ———————————————— clawd ————————————————
// 身子：圆角很大的软块——底下比顶上宽一点、正面肚子微微鼓、顶上微微拱，表面有一点点手捏的不平
function clawdBody(W, H, D) {
  const g = smooth(new THREE.SphereGeometry(1, 48, 36));
  const p = 4.2;   // 越大越方
  deform(g, (v) => {
    const sgn = (a) => Math.sign(a) * Math.pow(Math.abs(a), 2 / p);
    let x = sgn(v.x), y = sgn(v.y), z = sgn(v.z);
    const low = (1 - y) / 2;
    x *= 1 + .05 * low; z *= 1 + .04 * low;
    if (z > 0) z *= 1 + .05 * Math.exp(-(y * y) * 2) * (1 - x * x);   // 肚子
    if (y > 0) y *= 1 + .04 * (1 - x * x) * (1 - z * z);   // 顶上拱一点
    v.set(x * W / 2, y * H / 2, z * D / 2);
    v.addScaledVector(v.clone().normalize(), fbm(v.x * 5, v.y * 5, v.z * 5, 11) * .004);
  });
  g.computeVertexNormals();
  return g;
}
export function figureClawd() {
  const grp = new THREE.Group(), m = kit(grp);
  const C = '#dd7a5c', CD = '#c86a4e';
  const body = new THREE.Group(); body.position.y = .1; grp.add(body);
  m(clawdBody(.62, .46, .44), C, [0, .23, 0], [0, 0, 0], [1, 1, 1], body, .5);
  const eyes = [];
  for (const sx of [-1, 1]) {
    // 眼睛：竖着的小药丸，微微嵌进身子里，顶上一点高光
    eyes.push(m(new THREE.CapsuleGeometry(.03, .07, 10, 20), '#1d1614', [sx * .14, .27, .222], [0, 0, 0], [1, 1, .55], body, .15));
    m(new THREE.SphereGeometry(.011, 10, 8), '#ffffff', [sx * .14 + .008, .31, .24], [0, 0, 0], [1, 1, .5], body, .1);
    m(fruit(.035, { sx: 1.15, sy: .6, sz: .3, lump: 0, dent: 0 }), '#f0a08c', [sx * .22, .16, .214], [0, 0, 0], [1, 1, 1], body, .7);
  }
  // 小手：跟 2D 里一样，是身子两侧、眼睛那么高的一块扁扁的软方块，跟身子同色，往外伸出一小截；右手（arms[1]）挥手时绕肩转
  const arms = [-1, 1].map((sx) => {
    const a = new THREE.Group(); a.position.set(sx * .285, .27, 0); a.rotation.z = Math.PI / 2; body.add(a);
    const dir = -sx;   // 转了 90° 以后，沿 -sx·y 长的就朝外
    const g = smooth(new THREE.SphereGeometry(1, 24, 18)), p = 3.4;
    deform(g, (v) => {
      const sgn = (q) => Math.sign(q) * Math.pow(Math.abs(q), 2 / p);
      const x = sgn(v.x), y = sgn(v.y), z = sgn(v.z);
      const t = (y + 1) / 2;   // 0 贴身子 → 1 手尖
      v.set(x * .078 * (1 - .1 * t), dir * (t * .17 - .02), z * .11 * (1 - .12 * t));
    });
    g.computeVertexNormals();
    m(g, C, [0, 0, 0], [0, 0, 0], [1, 1, 1], a, .5);
    return a;
  });
  // 小短腿：跟 2D 里一样，是四根细细直直的小方条，跟身子同色，没有另外的脚掌
  const legs = [];
  for (const [x, z] of [[-.21, .1], [-.09, -.1], [.09, .1], [.21, -.1]]) {
    const l = new THREE.Group(); l.position.set(x, .065, z); grp.add(l);
    const g = smooth(new THREE.SphereGeometry(1, 20, 16)), p = 3.6;
    deform(g, (v) => {
      const sgn = (q) => Math.sign(q) * Math.pow(Math.abs(q), 2 / p);   // 方方的小柱子，棱角磨圆
      v.set(sgn(v.x) * .036, sgn(v.y) * .066 + .005, sgn(v.z) * .042);
    });
    g.computeVertexNormals();
    m(g, C, [0, 0, 0], [0, 0, 0], [1, 1, 1], l, .5);
    legs.push(l);
  }
  grp.userData = { body, arms, legs, eyes };
  return grp;
}
