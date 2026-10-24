// 栖 · 3D 小岛
//
// 画法参考、部分改写自 StarFold146/Nyx 的「记忆小镇」（town/shop/look.js、town/look2.js，MIT License，
// Copyright (c) 2026 StarFold146）：三阶卡通光、往外撑的背面描边壳、水彩后期（纸纹、颜色往边上积、轻微手抖、暖光）。
//
// 为了手机不烫：
// - 岛上不动的东西（地、树、房子、花……）合成一个网格 + 一个描边网格，整座岛两次绘制
// - 影子只在搭好时算一次，之后不再更新
// - 只有镜头动、人在走、海在晃的时候才重画；闲着时海一秒只晃几帧
// - 后期用一张预先算好的纸纹图，不在每个像素上现算噪声
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { grad, toon, hullMat, store, bake, worldUV, R, jit, box, cyl, cone, ball, blob, disc, torus, OPT, lathe } from './kit.js';
import { G, grandManor, fountain, parterre, urn } from './grand.js';
import { mansion } from './mansion.js';
import { roseManor } from './roseManor.js';
import { bakery } from './bakery.js';
import { baroque as baroqueHall } from './baroque.js';
import * as PR from './props.js';
import * as AT from './atmos.js';
import { placeObject, dressClawd } from './voxel.js';
import * as TX from './tex.js';
import { P, BUILD, fallback, flowerPatch, clover, bush, lavender } from './models.js';
import { victorian, gothic, rococo, baroque, gasLamp, ironFence, ironBench } from './manor.js';
import { hedge, boxBall, roseBush, lollipop, coneTopiary, cypress, pillarBox } from './garden.js';

// 老房子配庄园花园：房子换成维多利亚 / 哥特 / 洛可可 / 巴洛克，小树修剪成造型树，灌木是绿篱和玫瑰
Object.assign(BUILD, {
  houseOrange: (o, d) => victorian(o, d),
  cabin: (o, d) => gothic(o, d),
  shop: (o, d) => rococo(o, d),
  houseBeige: (o, d) => baroque(o, d),
  lamp: gasLamp, fence: (o, d) => ironFence(o, d.w), fenceV: (o, d) => ironFence(o, d.w), bench: (o, d) => ironBench(o, d.w), mailbox: pillarBox,
  bush: (o, d) => (R() < .5 ? hedge(o, d) : boxBall(o)), berry: roseBush,
  treeSmall: (o) => coneTopiary(o, 1, R() < .4), olive: (o) => lollipop(o), bonsai: (o) => cypress(o, .8), pine: (o) => cypress(o, 1.2),
  houseOrange: (o, d) => mansion(o, d), cabin: (o, d) => roseManor(o, d), shop: (o, d) => bakery(o, d), houseBeige: (o, d) => baroqueHall(o, d),
  signpost: PR.signpost, greenhouse: PR.greenhouse, lighthouse: PR.lighthouse, telescope: PR.telescope, scarecrow: PR.scarecrow,
  haybale: PR.haybale, wheelbarrow: PR.wheelbarrow, well: PR.well, beehive: PR.beehive, flowerpot: PR.flowerpot, roseArch: PR.roseArch,
  picnic: PR.picnic, umbrella: PR.umbrella, deckchair: PR.deckchair, shells: PR.shells, rowboat: PR.rowboat, campfire: PR.campfire,
  logpile: PR.logpile, tent: PR.tent, mushrooms: PR.mushrooms, birdhouse: PR.birdhouse, reeds: PR.reeds, stones: PR.stones,
  lanterns: PR.lanterns, windmill: PR.windmill, wheat: PR.wheat, coralPink: PR.coralPink, seaweed: PR.seaweed, snowman: PR.snowman, sled: PR.sled, fountain: (o, d) => fountain(o, d), parterre: (o, d) => parterre(o, d),
  urnPed: (o) => { const put = (g, c, opt = {}) => bake(g, c, { ...opt, ao: o.t, p: [o.cx + (opt.p?.[0] ?? 0), o.t + (opt.p?.[1] ?? 0), o.cz + (opt.p?.[2] ?? 0)] }); put(box(.3, .08, .3), G.stoneD); put(box(.22, .5, .22), G.marble, { p: [0, .29, 0] }); put(box(.3, .06, .3), G.marble, { p: [0, .57, 0] }); urn(put, 0, .6, 0, .9); },
});

// ———————————————————— 数据 ————————————————————
let D = window.ISLAND;
if (!D && location.search.includes('gallery')) {
  // 预览用：把每一种景排成一排排，挨个看
  const kinds = ['houseBeige', 'signpost', 'greenhouse', 'lighthouse', 'telescope', 'scarecrow', 'haybale', 'wheelbarrow', 'well', 'beehive', 'flowerpot', 'roseArch', 'fountain', 'picnic', 'umbrella', 'deckchair', 'shells', 'rowboat', 'campfire', 'logpile', 'tent', 'mushrooms', 'birdhouse', 'reeds', 'stones', 'lanterns', 'windmill', 'wheat', 'coralPink', 'seaweed', 'snowman', 'sled'];
  const GW = 30, GH = 26, ground = Array(GW * GH).fill('grass');
  for (let x = 0; x < GW; x++) for (const y of [0, 1, GH - 1, GH - 2]) ground[y * GW + x] = 'sea';
  for (let y = 0; y < GH; y++) for (const x of [0, 1, GW - 1, GW - 2]) ground[y * GW + x] = 'sea';
  const decor = []; let x = 3, y = 4, rowH = 0;
  for (const k of kinds) { const w = k === 'houseBeige' ? 4 : ['greenhouse', 'picnic', 'roseArch', 'tent', 'lanterns', 'rowboat', 'fountain', 'windmill'].includes(k) ? 2 : 1; if (x + w > GW - 3) { x = 3; y += 4; } decor.push({ kind: k, x, y, w, h: 2 }); x += w + 2; }
  D = { w: GW, h: GH, ground, decor, her: [8, 3], him: [9, 3] };
}
if (!D) {
  D = await (await fetch('island.json')).json();
  D.her = [14, 17]; D.him = [13, 17];
  D.decor.push({ kind: 'fountain', x: 16, y: 18, w: 2, h: 2 });
}
const W = D.w, H = D.h;
const TOP = { sea: null, water: -.24, sand: -.07, path: -.03, wood: -.04, soil: .02, stone: .01, grass: 0, flowers: 0 };
const g = (x, y) => (x < 0 || y < 0 || x >= W || y >= H) ? 'sea' : D.ground[y * W + x];
const topAt = (x, y) => TOP[g(x, y)] ?? null;
const BOTTOM = -1.1;

// ———————————————————— 地 ————————————————————
function groundColor(kind, x, y) {
  const n = ((x * 73856093) ^ (y * 19349663)) & 255;
  const k = 1 + (n / 255 - .5) * .025;
  const base = { grass: P.grass, flowers: P.flowers, path: P.path, sand: P.sand, soil: P.soil, stone: P.stone, wood: P.wood, water: P.water }[kind] || P.grass;
  return new THREE.Color(base).multiplyScalar(k);
}
function buildGround() {
  const pos = [], nor = [], col = [];
  const tri = (a, b, c, n, cc) => { for (const v of [a, b, c]) { pos.push(...v); nor.push(...n); col.push(cc.r, cc.g, cc.b); } };
  const quad = (a, b, c, d, n, cc) => { tri(a, b, c, n, cc); tri(a, c, d, n, cc); };
  // 朝上的三角：绕向不对就换一下（正面要逆时针）
  const triUp = (a, b, c, cc) => {
    const cy = (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]);
    if (cy >= 0) tri(a, b, c, [0, 1, 0], cc); else tri(a, c, b, [0, 1, 0], cc);
  };
  const land = (x, y) => topAt(x, y) != null;
  const SEG = 7;
  const cliffA = new THREE.Color(P.cliff), cliffB = new THREE.Color(P.cliffD), rockC = new THREE.Color(P.rockC);
  // 一段岸壁（法线朝海）：上面一窄条地色，下面两层土，最底下一层石头
  const wall = (a, b, t, lipC, sx, sz) => {
    let nx = -(b[1] - a[1]), nz = b[0] - a[0];
    if (nx * sx + nz * sz < 0) { [a, b] = [b, a]; nx = -nx; nz = -nz; }
    const l = Math.hypot(nx, nz) || 1, n = [nx / l, 0, nz / l];
    const bands = [[t, t - .08, lipC], [t - .08, t - .3, cliffA], [t - .3, -.5, cliffB], [-.5, BOTTOM, rockC]];
    for (const [hi, lo, c] of bands) if (hi > lo) quad([a[0], hi, a[1]], [a[0], lo, a[1]], [b[0], lo, b[1]], [b[0], hi, b[1]], n, c);
  };
  const arc = (cx, cy, dx, dy) => {
    const a0 = Math.atan2(0, dx); let a1 = Math.atan2(dy, 0);
    if (a1 - a0 > Math.PI) a1 -= 2 * Math.PI; if (a1 - a0 < -Math.PI) a1 += 2 * Math.PI;
    const pts = [];
    for (let i = 0; i <= SEG; i++) { const a = a0 + (a1 - a0) * i / SEG; pts.push([cx + Math.cos(a) * .5, cy + Math.sin(a) * .5]); }
    return pts;
  };
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const kind = g(x, y), t = TOP[kind];
    const cx = x + .5, cy = y + .5;
    if (t == null) {
      // 海里的这一格：哪个角两边都是陆地，就补一块凹进去的圆角（岸线不再是直角的锯齿）
      for (const [dx, dy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
        if (!land(x + dx, y) || !land(x, y + dy)) continue;
        const nt = Math.min(topAt(x + dx, y), topAt(x, y + dy));
        const c = groundColor(g(x + dx, y), x + dx, y), lipC = c.clone().multiplyScalar(.92);
        const kx = x + (dx > 0 ? 1 : 0), ky = y + (dy > 0 ? 1 : 0);
        const pts = arc(cx, cy, dx, dy);
        for (let i = 0; i < SEG; i++) {
          const p = pts[i], q = pts[i + 1];
          triUp([p[0], nt, p[1]], [q[0], nt, q[1]], [kx, nt, ky], c);
          wall(p, q, nt, lipC, cx - (p[0] + q[0]) / 2, cy - (p[1] + q[1]) / 2);
        }
      }
      continue;
    }
    const c = groundColor(kind, x, y), lipC = c.clone().multiplyScalar(.92);
    for (const [dx, dy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      const hx = land(x + dx, y), vy = land(x, y + dy);
      const qx0 = Math.min(cx, cx + dx * .5), qx1 = Math.max(cx, cx + dx * .5), qy0 = Math.min(cy, cy + dy * .5), qy1 = Math.max(cy, cy + dy * .5);
      if (!hx && !vy) {
        const pts = arc(cx, cy, dx, dy);
        for (let i = 0; i < SEG; i++) {
          const p = pts[i], q = pts[i + 1];
          triUp([cx, t, cy], [p[0], t, p[1]], [q[0], t, q[1]], c);
          wall(p, q, t, lipC, (p[0] + q[0]) / 2 - cx, (p[1] + q[1]) / 2 - cy);
        }
      } else {
        quad([qx0, t, qy0], [qx0, t, qy1], [qx1, t, qy1], [qx1, t, qy0], [0, 1, 0], c);
        if (!hx) { const ex = cx + dx * .5; wall([ex, qy0], [ex, qy1], t, lipC, dx, 0); }
        if (!vy) { const ey = cy + dy * .5; wall([qx0, ey], [qx1, ey], t, lipC, 0, dy); }
      }
    }
    // 陆地之间高低不一样（路比草低一点、池塘凹下去）：照旧露一截侧面
    for (const [dx, dy, nx, nz] of [[0, -1, 0, -1], [0, 1, 0, 1], [-1, 0, -1, 0], [1, 0, 1, 0]]) {
      const nt = topAt(x + dx, y + dy);
      if (nt == null) continue;
      const lo = Math.max(nt, kind === 'wood' ? t - .12 : BOTTOM);
      if (lo >= t - .001) continue;
      let a, b;
      if (dy === -1) { a = [x + 1, y]; b = [x, y]; } else if (dy === 1) { a = [x, y + 1]; b = [x + 1, y + 1]; }
      else if (dx === -1) { a = [x, y]; b = [x, y + 1]; } else { a = [x + 1, y + 1]; b = [x + 1, y]; }
      quad([a[0], t, a[1]], [a[0], lo, a[1]], [b[0], lo, b[1]], [b[0], t, b[1]], [nx, 0, nz], c.clone().multiplyScalar(.84));
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  store.parts.push(geo);
  groundDetail();
}

// 地上的细节：草丛、小花、石板路、沙滩贝壳、田垄和小苗、木桥的板和绳、池塘边的石头、岸下的礁石
function groundDetail() {
  const occupied = new Set();
  for (const d of D.decor) for (let dx = 0; dx < d.w; dx++) occupied.add(d.y * W + d.x + dx);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const kind = g(x, y), t = TOP[kind];
    if (t == null) {
      // 岸下的礁石
      const nearLand = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => topAt(x + dx, y + dy) != null);
      if (nearLand && R() < .35) bake(blob(.12 + R() * .1, 1, .6, .3), jit(P.rockC, .08), { p: [x + .2 + R() * .6, -.32, y + .2 + R() * .6], line: .008 });
      continue;
    }
    const free = !occupied.has(y * W + x);
    if (kind === 'grass' || kind === 'flowers') {
      const tufts = free ? (R() < .55 ? 1 + (R() * 3 | 0) : 0) : 1;
      for (let k = 0; k < tufts; k++) {
        const px = x + .15 + R() * .7, pz = y + .15 + R() * .7, c = jit(R() < .5 ? P.grassD : P.leafL, .05);
        for (let i = 0; i < 4; i++) bake(cone(.018, .1 + R() * .08, 4), c, { p: [px + (R() - .5) * .06, t + .05, pz + (R() - .5) * .06], r: [(R() - .5) * .6, 0, (R() - .5) * .6], line: 0 });
      }
      if (free && R() < .12) bake(blob(.07 + R() * .04, 1, .45), jit(P.grassL, .04), { p: [x + R(), t + .01, y + R()], line: .006 });
      if (kind === 'flowers') for (let i = 0; i < 3; i++) {
        const cc = [P.pink, P.yellow, P.white, P.lav][(R() * 4) | 0], px = x + .15 + R() * .7, pz = y + .15 + R() * .7;
        bake(cyl(.006, .006, .08, 4), P.leafD, { p: [px, t + .04, pz], line: 0 });
        for (let k = 0; k < 4; k++) { const a = k / 4 * 6.28; bake(ball(.017, 5, 4), cc, { p: [px + Math.cos(a) * .018, t + .085, pz + Math.sin(a) * .018], line: 0 }); }
      }
    }
    if (kind === 'path') {   // 碎石路：细细的一层小石子，挨着草的那边一道石头路缘
      for (let i = 0; i < 7; i++) bake(blob(.025 + R() * .02, 0, .5), jit(R() < .5 ? '#c9c0b2' : '#e2dbcf', .05), { p: [x + R(), t + .006, y + R()], line: 0 });
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nk = g(x + dx, y + dy);
        if (nk === 'path' || nk === 'wood' || nk === 'sea') continue;
        bake(box(dx ? .08 : 1, .08, dy ? .08 : 1), jit('#cdc4b6', .04), { p: [x + .5 + dx * .46, t + .04, y + .5 + dy * .46], line: .006 });
      }
    }
    if (kind === 'sand') {
      if (R() < .1) bake(ball(.035, 7, 4, 0, Math.PI * 2, 0, Math.PI / 2), jit(P.white, .03), { p: [x + R(), t, y + R()], s: [1.3, .6, 1], line: .004 });
      if (R() < .03) { const px = x + R(), pz = y + R(); for (let k = 0; k < 5; k++) { const a = k / 5 * 6.28; bake(box(.06, .012, .022), '#e9a98c', { p: [px + Math.cos(a) * .03, t + .006, pz + Math.sin(a) * .03], r: [0, -a, 0], line: .003 }); } }
      if (R() < .25) bake(box(.5, .006, .02), new THREE.Color(P.sand).multiplyScalar(.95), { p: [x + .5, t + .002, y + R()], r: [0, (R() - .5) * .3, 0], line: 0 });
    }
    if (kind === 'soil') {   // 田：一道道垄，垄上小苗
      for (const dz of [.2, .5, .8]) {
        bake(box(.96, .06, .14, .025, 1), new THREE.Color(P.soilL), { p: [x + .5, t + .03, y + dz], line: 0 });
        for (const dx of [.25, .75]) if (R() < .7) for (const sx of [-1, 1]) bake(blob(.03, 0, .4), P.leaf, { p: [x + dx + sx * .025, t + .08, y + dz], s: [1.5, 1, .8], r: [0, 0, sx * .5], line: .003 });
      }
    }
    if (kind === 'wood') {   // 木桥：一块块木板（有缝）、两边桥柱和绳子
      const horiz = g(x - 1, y) === 'wood' || g(x + 1, y) === 'wood';
      for (let i = 0; i < 5; i++) {
        const k = .1 + i * .2;
        bake(box(horiz ? .17 : .96, .03, horiz ? .96 : .17), jit(P.wood, .06), { p: [horiz ? x + k : x + .5, t + .012, horiz ? y + .5 : y + k], line: .004 });
      }
      for (const s of [0, 1]) {
        const px = horiz ? x + .5 : x + .05 + s * .9, pz = horiz ? y + .05 + s * .9 : y + .5;
        bake(cyl(.04, .045, .95, 7), '#3f3a3c', { p: [px, t + .04, pz], line: .006 });
        bake(ball(.04, 8, 6), '#c8a96c', { p: [px, t + .53, pz], line: .004 });
        bake(box(horiz ? 1 : .03, .03, horiz ? .03 : 1), '#3f3a3c', { p: [horiz ? x + .5 : px, t + .42, horiz ? pz : y + .5], line: .004 });
        for (let k = 0; k < 5; k++) bake(box(.012, .3, .012), '#3f3a3c', { p: [horiz ? x + .1 + k * .2 : px, t + .27, horiz ? pz : y + .1 + k * .2], line: 0 });
      }
    }
    if (kind === 'water') {   // 池塘：挨着岸的边上砌一圈石头岸，岸顶一道压顶石
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nt = topAt(x + dx, y + dy);
        if (nt == null || g(x + dx, y + dy) === 'water') continue;
        const px = x + .5 + dx * .45, pz = y + .5 + dy * .45;
        bake(box(dx ? .1 : 1, nt - t + .06, dy ? .1 : 1), jit('#cfc6b8', .03), { p: [px, (nt + t) / 2 + .03, pz], line: .006 });
        bake(box(dx ? .16 : 1.04, .04, dy ? .16 : 1.04), P.trim, { p: [px, nt + .07, pz], line: .005 });
      }
      if (R() < .3) bake(disc(.1, 12, .3, 5.6), P.leaf, { p: [x + .2 + R() * .6, t + .005, y + .2 + R() * .6], r: [0, R() * 6, 0], line: .004 });
    }
  }
}

// ———————————————————— 景 ————————————————————
let shadowGeo = [];
function shadowDisc(x, t, z, r) {
  const geo = new THREE.CircleGeometry(r, 18); geo.rotateX(-Math.PI / 2); geo.translate(x, t + .004, z);
  shadowGeo.push(geo);
}
// 房子先搭，记下它在地上实际占多大（3D 的房子比 2D 地图上的图大）；
// 别的景落在房子占的地方就不摆，人走路也绕开这些地方（App 里用 window.__blocked）
const BIG = new Set(['houseOrange', 'cabin', 'shop', 'houseBeige', 'greenhouse', 'lighthouse', 'windmill']);
const footprints = [];
function buildDecor() {
  const list = D.decor.filter((d) => topAt(d.x, d.y) != null);
  for (const d of list.filter((d) => BIG.has(d.kind))) {
    const o = { cx: d.x + d.w / 2, cz: d.y + .5, t: topAt(d.x, d.y) };
    const before = Object.fromEntries(Object.entries(store.groups).map(([k, v]) => [k, v.length]));
    (BUILD[d.kind] || fallback)(o, d);
    const bb = new THREE.Box3();
    for (const [k, v] of Object.entries(store.groups)) for (let i = before[k]; i < v.length; i++) { v[i].computeBoundingBox(); bb.union(v[i].boundingBox); }
    // 只算一人高以下的部分：屋檐、雨棚伸出去不算挡路
    footprints.push({ x0: bb.min.x, x1: bb.max.x, z0: bb.min.z, z1: bb.max.z, kind: d.kind });
  }
  const hit = (x, z, r) => footprints.some((f) => x + r > f.x0 && x - r < f.x1 && z + r > f.z0 && z - r < f.z1);
  for (const d of list.filter((d) => !BIG.has(d.kind))) {
    const o = { cx: d.x + d.w / 2, cz: d.y + .5, t: topAt(d.x, d.y) };
    if (hit(o.cx, o.cz, Math.min(.45, d.w * .3))) continue;
    (BUILD[d.kind] || fallback)(o, d);
    shadowDisc(o.cx, o.t, o.cz, Math.min(.65, d.w * .36));
  }
  // 走不进去的格子：房子占的、湖里海里
  const blocked = new Set();
  for (const f of footprints) for (let y = Math.floor(f.z0); y <= Math.floor(f.z1); y++) for (let x = Math.floor(f.x0); x <= Math.floor(f.x1); x++) blocked.add(y * W + x);
  window.__blocked = blocked; window.__footprints = footprints;
}


// 空地上自动长出来的小东西：野花丛、三叶草、蕨草、小灌木、蘑菇、小石子（只是装饰，不存进她岛上的布局）。
// 离路、房子、摆好的景至少一格，不挡着走路
function scatter() {
  const near = new Set();
  const mark = (x, y) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) near.add((y + dy) * W + x + dx); };
  for (const d of D.decor) for (let dx = 0; dx < d.w; dx++) near.add(d.y * W + d.x + dx);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const k = g(x, y); if (k !== 'grass' && k !== 'flowers') mark(x, y); }
  if (window.__blocked) for (const c of window.__blocked) near.add(c);
  mark(D.her[0], D.her[1]); mark(D.him[0], D.him[1]);
  const petals = ['#f3c4cf', '#fff6e0', '#f6dc8a', '#d9c8ee', '#f7b9a8'];
  let s = 97; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (near.has(y * W + x)) continue;
    const t = TOP[g(x, y)]; if (t == null) continue;
    for (let rep = 0; rep < 2; rep++) {
    const o = { cx: x + .15 + r() * .7, cz: y + .15 + r() * .7, t }, v = r();
    if (v < .3) flowerPatch(o, petals[(r() * petals.length) | 0], { n: 2 + (r() * 3 | 0), stem: .12 + r() * .1, shape: r() < .3 ? 'daisy' : 'round' });
    else if (v < .42) clover(o);
    else if (v < .5) lavender(o);
    else if (v < .58) { for (let i = 0; i < 5; i++) bake(cone(.05, .28 + r() * .12, 4), jit('#6f9058', .06), { p: [o.cx + (r() - .5) * .2, t + .14, o.cz + (r() - .5) * .2], r: [(r() - .5) * .9, r() * 3, (r() - .5) * .9], s: [1, 1, .25], ao: t, line: 0 }); }
    else if (v < .605) bush(o, { flower: r() < .5 ? '#fff6e0' : '#f3c4cf' });
    else if (v < .66) { for (let i = 0; i < 3; i++) { const mx = o.cx + (r() - .5) * .3, mz = o.cz + (r() - .5) * .3, ms = .5 + r() * .5; bake(cyl(.015 * ms, .02 * ms, .07 * ms, 6), '#f4ecdf', { p: [mx, t + .035 * ms, mz], ao: t, line: 0 }); bake(ball(.05 * ms, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), r() < .5 ? '#d9706a' : '#e8b46a', { p: [mx, t + .065 * ms, mz], ao: t, line: 0 }); } }
    else if (v < .72) { for (let i = 0; i < 3; i++) bake(blob(.04 + r() * .04, 1, .55, .3), jit('#bdb5a8', .06), { p: [o.cx + (r() - .5) * .4, t + .015, o.cz + (r() - .5) * .4], ao: t, line: 0 }); }
    }
  }
}

// ———————————————————— 两个人 ————————————————————
// 人物不合进岛里（要动），每块单独一个网格，各带一层描边壳
function makeKit(grp) {
  const mats = new Map();
  const matOf = (c) => { if (!mats.has(c)) mats.set(c, new THREE.MeshStandardMaterial({ color: c, roughness: .62 })); return mats.get(c); };
  return (geo, c, p, r = [0, 0, 0], s = [1, 1, 1], line = .012, parent = grp) => {
    const mesh = new THREE.Mesh(geo, matOf(c));
    mesh.position.set(...p); mesh.rotation.set(...r); mesh.scale.set(...s); parent.add(mesh);
    if (line && OPT.outline) {
      let h = new THREE.BufferGeometry(); h.setAttribute('position', geo.attributes.position.clone()); if (geo.index) h.setIndex(geo.index.clone());
      h = mergeVertices(h, 1e-3); h.computeVertexNormals();
      const pa = h.attributes.position, na = h.attributes.normal;
      for (let i = 0; i < pa.count; i++) pa.setXYZ(i, pa.getX(i) + na.getX(i) * line / s[0], pa.getY(i) + na.getY(i) * line / s[1], pa.getZ(i) + na.getZ(i) * line / s[2]);
      mesh.add(new THREE.Mesh(h, hullMat));
    }
    return mesh;
  };
}

// 潮玩手办风：大头、圆润、哑光软胶质感（按她给的参考），保留她自己的样子——棕发、粉色蝴蝶结、粉色衣服
function toyKit(grp) {
  const mats = new Map();
  const matOf = (c, rough = .55) => { const k = c + rough; if (!mats.has(k)) mats.set(k, new THREE.MeshStandardMaterial({ color: c, roughness: rough, metalness: 0 })); return mats.get(k); };
  return (geo, c, p, r = [0, 0, 0], s = [1, 1, 1], parent = grp, rough = .55) => {
    const mesh = new THREE.Mesh(geo, matOf(c, rough));
    mesh.position.set(...p); mesh.rotation.set(...r); mesh.scale.set(...s); parent.add(mesh);
    return mesh;
  };
}
const sph = (r, a = 32, b = 24, ...rest) => new THREE.SphereGeometry(r, a, b, ...rest);
const cap = (r, l, a = 12, b = 20) => new THREE.CapsuleGeometry(r, l, a, b);
const rbox = (w, h, d, r, seg = 6) => new RoundedBoxGeometry(w, h, d, seg, r);

function figureHer() {
  const grp = new THREE.Group(), m = toyKit(grp);
  const SKIN = '#f8dfd2', HAIR = '#5b3a2e', HAIRL = '#6c4636', PINK = '#eba7b3', PINKD = '#d98a99', CREAM = '#f7efe6', BOOT = '#6f4337', BOOTL = '#8a5747', SOLE = '#2b2526', BOW = '#f08ea0';
  // 靴子：粗粗的短靴、黑色厚底
  const legs = [-1, 1].map((sx) => {
    const l = new THREE.Group(); l.position.set(sx * .085, 0, 0); grp.add(l);
    // 腿：短短一截，浅肤色
    m(cap(.045, .09, 10, 20), SKIN, [0, .24, 0], [0, 0, 0], [1, 1, 1], l, .6);
    // 短靴：一整只圆角的靴子（鞋头圆圆地往前一点），靴口一圈翻边，贴着鞋形的厚鞋底，脚背一条搭扣带
    m(cyl(.054, .058, .1, 28), BOOT, [0, .12, -.005], [0, 0, 0], [1, 1, 1], l, .45);
    m(torus(.056, .013, 10, 28), BOOTL, [0, .17, -.005], [Math.PI / 2, 0, 0], [1, 1, 1], l, .5);
    m(rbox(.12, .085, .18, .042, 8), BOOT, [0, .062, .022], [0, 0, 0], [1, 1, 1], l, .45);
    m(rbox(.122, .028, .184, .03, 6), SOLE, [0, .014, .022], [0, 0, 0], [1, 1, 1], l, .75);
    m(rbox(.1, .014, .03, .007, 4), BOOTL, [0, .103, .055], [0, 0, 0], [1, 1, 1], l, .5);
    m(rbox(.018, .018, .01, .004, 2), '#d8b878', [sx * .03, .108, .06], [0, 0, 0], [1, 1, 1], l, .3);
    return l;
  });
  // 裙子：米白色的短 A 字裙，下摆一圈粉色线
  const sk = lathe([[.225, .29], [.222, .31], [.17, .41], [.13, .49]], 40); sk.computeVertexNormals();
  m(sk, CREAM, [0, 0, 0]);
  m(new THREE.CircleGeometry(.225, 40).rotateX(Math.PI / 2), CREAM, [0, .29, 0]);
  m(torus(.224, .008, 6, 40), PINK, [0, .3, 0], [Math.PI / 2, 0, 0]);
  // 粉色宽松毛衣：一道道竖纹、高领、灯笼袖、罗纹袖口
  const sweater = lathe([[.12, 0], [.165, .02], [.175, .1], [.165, .2], [.13, .26], [.08, .29], [0, .3]], 40);
  { const pa = sweater.attributes.position; for (let i = 0; i < pa.count; i++) { const a = Math.atan2(pa.getZ(i), pa.getX(i)); const k = 1 + Math.cos(a * 36) * .012; pa.setX(i, pa.getX(i) * k); pa.setZ(i, pa.getZ(i) * k); } sweater.computeVertexNormals(); }
  m(sweater, PINK, [0, .44, 0], [0, 0, 0], [1, 1, .85]);
  m(torus(.15, .025, 10, 32), PINKD, [0, .455, 0], [Math.PI / 2, 0, 0], [1, .85, 1]);   // 下摆罗纹
  m(cyl(.075, .085, .06, 28), PINK, [0, .755, 0]);
  m(torus(.075, .018, 10, 28), PINKD, [0, .785, 0], [Math.PI / 2, 0, 0]);
  const arms = [-1, 1].map((sx) => {
    const a = new THREE.Group(); a.position.set(sx * .16, .68, 0); a.rotation.z = sx * .18; grp.add(a);
    m(cap(.065, .12), PINK, [sx * .01, -.09, 0], [0, 0, 0], [1, 1, .95], a);
    m(torus(.05, .02, 8, 20), PINKD, [sx * .012, -.2, 0], [Math.PI / 2, 0, 0], [1, 1, 1], a);
    m(sph(.045, 20, 16), SKIN, [sx * .012, -.25, .005], [0, 0, 0], [1, 1.05, .95], a);
    return a;
  });
  // 头：大大圆圆，脸朝 +z
  const head = new THREE.Group(); head.position.y = 1.03; grp.add(head);
  const eyes = [];
  m(sph(.3), SKIN, [0, 0, 0], [0, 0, 0], [1.06, .98, .98], head);
  for (const sx of [-1, 1]) m(sph(.06, 16, 12), SKIN, [sx * .31, -.03, 0], [0, 0, 0], [.6, 1, .9], head);   // 耳朵
  // 眼睛：白色眼白、大大的棕色瞳孔、黑色瞳仁、两点高光，上面一道弯弯的眼线（不往下压，看着温柔）
  for (const sx of [-1, 1]) {
    const e = new THREE.Group(); e.position.set(sx * .118, -.04, .262); e.rotation.y = sx * .32; head.add(e); eyes.push(e);
    m(sph(.062, 24, 18), '#fbfaf8', [0, 0, 0], [0, 0, 0], [1, 1, .38], e, .3);
    m(sph(.047, 24, 18), '#6b3c2c', [sx * -.006, -.004, .012], [0, 0, 0], [1, 1.08, .4], e, .25);
    m(sph(.022, 16, 12), '#1e1412', [sx * -.006, -.004, .024], [0, 0, 0], [1, 1.12, .3], e, .2);
    m(sph(.012, 10, 8), '#ffffff', [sx * -.006 + sx * .014, .016, .031], [0, 0, 0], [1, 1, .3], e, .1);
    m(sph(.0065, 8, 6), '#ffffff', [sx * -.006 - sx * .012, -.02, .031], [0, 0, 0], [1, 1, .3], e, .1);
    m(torus(.062, .009, 8, 24, Math.PI * .9), '#2b1d18', [0, .004, .012], [0, 0, Math.PI * .05], [1, 1.02, 1], e, .4);   // 上眼线
    m(sph(.04, 16, 12), '#f3a9a3', [sx * .05, -.085, -.01], [0, 0, 0], [1.2, .55, .3], e, .7);   // 腮红
  }
  const mouth = m(torus(.02, .006, 8, 16, Math.PI), '#b9605e', [0, -.15, .285], [0, 0, Math.PI], [1, .8, 1], head, .4);   // 小小的笑
  const oMouth = m(torus(.016, .007, 8, 16), '#b9605e', [0, -.15, .285], [0, 0, 0], [1, 1.2, 1], head, .4); oMouth.visible = false;   // 惊讶时的小圆嘴
  m(sph(.012, 10, 8), '#efc6b4', [0, -.085, .298], [0, 0, 0], [1, .7, .6], head);   // 鼻头
  // 头发：整个后脑和头顶一层，前面一排齐刘海，中间一缕尖尖的分发
  m(sph(.318, 36, 24, 0, Math.PI * 2, 0, Math.PI * .62), HAIR, [0, .015, -.012], [-.5, 0, 0], [1.06, 1, 1], head, .62);
  m(sph(.316, 36, 16, Math.PI / 2 - 1.25, 2.5, 0, .9), HAIRL, [0, .02, .0], [0, 0, 0], [1.06, 1, 1.02], head, .62);
  for (const sx of [-1, 1]) m(cap(.05, .14), HAIR, [sx * .27, -.08, .1], [0, 0, sx * .15], [1, 1, .9], head, .62);   // 鬓角
  // 两条粗辫子：一节一节的，绑粉色发圈，辫尾一小撮
  for (const sx of [-1, 1]) {
    const b = new THREE.Group(); b.position.set(sx * .27, -.12, -.02); b.rotation.z = sx * .35; head.add(b);
    for (let k = 0; k < 3; k++) m(sph(.068 - k * .006, 20, 16), k % 2 ? HAIRL : HAIR, [sx * .02, -.07 - k * .1, 0], [0, 0, 0], [1, 1.25, 1], b, .62);
    m(torus(.035, .016, 8, 16), BOW, [sx * .03, -.34, 0], [Math.PI / 2, 0, 0], [1, 1, 1], b, .4);
    m(cone(.06, .12, 16), HAIR, [sx * .03, -.42, 0], [Math.PI, 0, 0], [1, 1, .8], b, .62);
  }
  // 头顶右边一个粉色蝴蝶结
  const bow = new THREE.Group(); bow.position.set(.16, .24, .1); bow.rotation.set(.2, .3, -.4); head.add(bow);
  for (const sx of [-1, 1]) m(sph(.065, 20, 16), BOW, [sx * .07, 0, 0], [0, 0, sx * .25], [1.25, .85, .5], bow, .4);
  m(sph(.035, 16, 12), '#e57d91', [0, 0, .01], [0, 0, 0], [1, 1, .8], bow, .4);
  grp.scale.setScalar(.95);
  grp.userData = { legs, arms, head, eyes, mouth, oMouth };
  return grp;
}

// clawd 也换成同一套软胶手办：圆角很大的身子、两只亮亮的黑眼睛、两边短短的小手、四条圆圆的小腿
function figureClawd() {
  const grp = new THREE.Group(), m = toyKit(grp);
  const C = '#dd7a5c', CD = '#c86a4e';
  const body = new THREE.Group(); body.position.y = .1; grp.add(body);
  const eyesH = [];
  m(rbox(.62, .46, .44, .16, 8), C, [0, .23, 0], [0, 0, 0], [1, 1, 1], body, .5);
  for (const sx of [-1, 1]) {
    eyesH.push(m(cap(.03, .07, 8, 16), '#1d1614', [sx * .14, .27, .218], [0, 0, 0], [1, 1, .6], body, .15));
    m(sph(.011, 8, 6), '#ffffff', [sx * .14 + .008, .31, .235], [0, 0, 0], [1, 1, .5], body, .1);
    m(sph(.035, 12, 10), '#f0a08c', [sx * .22, .16, .21], [0, 0, 0], [1.1, .6, .3], body, .7);
  }
  const arms = [-1, 1].map((sx) => m(cap(.055, .07, 8, 16), CD, [sx * .34, .16, 0], [0, 0, Math.PI / 2], [1, 1, 1.1], body, .5));
  const legs = [];
  for (const [x, z] of [[-.21, .1], [-.09, -.1], [.09, .1], [.21, -.1]]) legs.push(m(cap(.045, .04, 8, 16), CD, [x, .065, z], [0, 0, 0], [1, 1, 1], grp, .5));
  grp.userData = { body, arms, legs, eyes: eyesH };
  return grp;
}

// ———————————————————— 场景 ————————————————————
const cv = document.getElementById('cv');
const renderer = new THREE.WebGLRenderer({ canvas: cv, antialias: true, powerPreference: 'low-power', preserveDrawingBuffer: true });
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0;
const DPR = Math.min(devicePixelRatio, 2);
renderer.setPixelRatio(DPR);
renderer.setSize(innerWidth, innerHeight, false);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap; renderer.shadowMap.autoUpdate = false;
const scene = new THREE.Scene();

// 背景：上面天色化进纸色，下面是远处的海，天际线上卧两层很淡的远山
const bgCv = document.createElement('canvas'), bgTex = new THREE.CanvasTexture(bgCv); bgTex.colorSpace = THREE.SRGBColorSpace;
function paintBg() {
  const w = 512, h = Math.round(512 * innerHeight / innerWidth); bgCv.width = w; bgCv.height = h;
  const c = bgCv.getContext('2d'), Hz = h * .2;
  let gr = c.createLinearGradient(0, 0, 0, Hz); gr.addColorStop(0, P.sky); gr.addColorStop(1, P.paper); c.fillStyle = gr; c.fillRect(0, 0, w, Hz + 1);
  gr = c.createLinearGradient(0, Hz, 0, h); gr.addColorStop(0, P.paper); gr.addColorStop(.3, P.sea); gr.addColorStop(1, P.seaD); c.fillStyle = gr; c.fillRect(0, Hz, w, h - Hz);
  let sd = 7; const rr = () => ((sd = (sd * 9301 + 49297) % 233280) / 233280);
  for (const [alpha, amp, step] of [[.22, 16, 46], [.36, 9, 30]]) {
    c.fillStyle = P.mount; c.globalAlpha = alpha; c.beginPath(); c.moveTo(0, Hz);
    for (let x = 0; x <= w + step; x += step) { c.lineTo(x, Hz - (rr() * .8 + .2) * amp); c.lineTo(x + step / 2, Hz - rr() * amp * .25); }
    c.lineTo(w, Hz); c.closePath(); c.fill();
  }
  c.globalAlpha = 1;
  bgTex.needsUpdate = true; scene.background = bgTex;
}
paintBg();

buildGround();
buildDecor();
scatter();
// 材质：真实一点的光——石头和木头哑光，金会反光，彩绘玻璃透亮，水面平滑
const stoneTex = (() => {   // 石头、灰泥上一层很淡的斑驳（乘在颜色上）
  const n = 256, c = document.createElement('canvas'); c.width = c.height = n;
  const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, n, n);
  let s = 5; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < 260; i++) {
    const x = r() * n, y = r() * n, rad = 4 + r() * 26, v = Math.round(255 * (.9 + r() * .08));
    for (const [ox, oy] of [[0, 0], [n, 0], [-n, 0], [0, n], [0, -n]]) {
      const gr = g.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, rad);
      gr.addColorStop(0, `rgba(${v},${v},${v},.35)`); gr.addColorStop(1, `rgba(${v},${v},${v},0)`);
      g.fillStyle = gr; g.fillRect(x + ox - rad, y + oy - rad, rad * 2, rad * 2);
    }
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 4;
  return t;
})();
const MATS = {
  base: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .82, metalness: 0, map: stoneTex }),
  gold: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .3, metalness: 1 }),
  glass: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .12, metalness: .2, emissive: '#000000' }),
  water: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .05, metalness: .3 }),
  roof: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.fishScale, roughness: .55, metalness: .1 }),
  slate: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.slateTiles, roughness: .6, metalness: .05 }),
  siding: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.siding, roughness: .75 }),
  darkstone: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.darkStone, roughness: .9 }),
  ashlar: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.ashlar, roughness: .85 }),
  plinth: new THREE.MeshStandardMaterial({ vertexColors: true, map: TX.plinthStone, roughness: .85 }),
  glow: new THREE.MeshStandardMaterial({ vertexColors: true, emissive: '#f0a048', emissiveIntensity: 1.4, roughness: .3 }),
  iron: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .45, metalness: .6 }),
};
// 彩绘玻璃自己透一点光（像屋里点着灯）
MATS.glass.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance += diffuseColor.rgb * .22;'); };
const glowSpots = store.groups.glow.map((g) => { g.computeBoundingSphere(); return [g.boundingSphere.center.clone(), g.boundingSphere.radius]; });
let tris = 0;
for (const [name, list] of Object.entries(store.groups)) {
  if (!list.length) continue;
  for (const pg of list) worldUV(pg);
  const mesh = new THREE.Mesh(mergeGeometries(list), MATS[name]);
  mesh.castShadow = name !== 'water'; mesh.receiveShadow = true;
  scene.add(mesh);
  tris += mesh.geometry.attributes.position.count / 3;
}
const shadows = new THREE.Mesh(mergeGeometries(shadowGeo), new THREE.MeshBasicMaterial({ color: '#2a2420', transparent: true, opacity: .18, depthWrite: false }));
scene.add(shadows);
window.__tris = tris;
store.groups = store.hulls = shadowGeo = null;

// 环境光：一个上亮下暗、偏暖的天，算成反射用的环境图（金和玻璃上才有东西可反）
{
  const envScene = new THREE.Scene();
  const sky = new THREE.SphereGeometry(10, 32, 16), cols = [];
  const top = new THREE.Color('#a9bfd6'), hor = new THREE.Color('#f3dfc2'), bot = new THREE.Color('#6f7a62');
  const pa = sky.attributes.position;
  for (let i = 0; i < pa.count; i++) { const y = pa.getY(i) / 10; const c = y > 0 ? hor.clone().lerp(top, Math.pow(y, .6)) : hor.clone().lerp(bot, Math.pow(-y, .5)); cols.push(c.r, c.g, c.b); }
  sky.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
  envScene.add(new THREE.Mesh(sky, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
  const sunBlob = new THREE.Mesh(new THREE.SphereGeometry(1.2, 16, 8), new THREE.MeshBasicMaterial({ color: new THREE.Color('#fff2d8').multiplyScalar(6) }));
  sunBlob.position.set(-6, 5, 5); envScene.add(sunBlob);
  const pm = new THREE.PMREMGenerator(renderer);
  scene.environment = pm.fromScene(envScene, .02).texture;
  scene.environmentIntensity = .55;
}


// 浅滩：把陆地画进一张小图再糊开，岸边一圈海水浅一点
const shoreTex = (() => {
  const k = 8, pad = 12, c = document.createElement('canvas'); c.width = (W + pad * 2) * k; c.height = (H + pad * 2) * k;
  const x = c.getContext('2d'); x.fillStyle = '#000'; x.fillRect(0, 0, c.width, c.height);
  x.filter = 'blur(' + (k * 1.4) + 'px)'; x.fillStyle = '#fff';
  for (let yy = 0; yy < H; yy++) for (let xx = 0; xx < W; xx++) if (topAt(xx, yy) != null) x.fillRect((xx + pad) * k, (yy + pad) * k, k, k);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.NoColorSpace; t.flipY = false;
  return t;
})();
// 海：岛周围一大片，近处浅、远处深，水面上几道慢慢晃的亮纹
const seaMat = new THREE.ShaderMaterial({
  uniforms: { t: { value: 0 }, c0: { value: new THREE.Color(P.sea) }, c1: { value: new THREE.Color(P.seaD) }, shallow: { value: new THREE.Color('#c4dcd8') }, foam: { value: new THREE.Color('#f4efe4') }, ctr: { value: new THREE.Vector2(W / 2, H / 2) }, size: { value: new THREE.Vector2(W / 2, H / 2) }, shore: { value: shoreTex }, box: { value: new THREE.Vector4(-12, -12, W + 24, H + 24) } },
  fog: true,
  vertexShader: `varying vec2 vP;
    #include <fog_pars_vertex>
    void main(){ vec4 w = modelMatrix * vec4(position,1.); vP = w.xz; vec4 mvPosition = viewMatrix * w; gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
    }`,
  fragmentShader: `uniform float t; uniform vec3 c0, c1, shallow, foam; uniform vec2 ctr, size; uniform sampler2D shore; uniform vec4 box; varying vec2 vP;
    #include <fog_pars_fragment>
    void main(){
      vec2 d = (vP - ctr) / size; float r = length(d);
      vec3 c = mix(c0, c1, smoothstep(1.0, 2.6, r));
      vec2 su = (vP - box.xy) / box.zw;
      float sh = (su.x > 0. && su.y > 0. && su.x < 1. && su.y < 1.) ? texture2D(shore, su).r : 0.;
      c = mix(c, shallow, smoothstep(.05, .6, sh));
      c = mix(c, foam, smoothstep(.42, .5, sh) * (1. - smoothstep(.5, .62, sh)) * (.55 + .45 * sin(t * 1.2 + vP.x * 2. + vP.y * 1.7)));
      float w = sin(vP.x * 1.3 + t * .8) * sin(vP.y * 1.1 - t * .6) + sin((vP.x + vP.y) * .7 + t * .5) * .6;
      c = mix(c, foam, smoothstep(1.25, 1.6, w) * .35 * (1. - smoothstep(1.2, 3.0, r)));
      gl_FragColor = vec4(c, 1.);
      #include <colorspace_fragment>
      #include <fog_fragment>
    }`,
});
seaMat.uniforms = THREE.UniformsUtils.merge([THREE.UniformsLib.fog, seaMat.uniforms]); seaMat.uniforms.shore.value = shoreTex;
const sea = new THREE.Mesh(new THREE.PlaneGeometry(1600, 1600), seaMat);
sea.rotation.x = -Math.PI / 2; sea.position.set(W / 2, -.32, H / 2);
scene.add(sea);

// 光：天光 + 一盏暖暖的太阳；影子只压掉一半的光
scene.add(new THREE.HemisphereLight('#cfdcef', '#8a7a62', 1.0));
const sun = new THREE.DirectionalLight('#ffe2b6', 3.6);
sun.position.set(W / 2 + AT.SKY.sun.x * 40, AT.SKY.sun.y * 40 + 4, H / 2 + AT.SKY.sun.z * 40); sun.target.position.set(W / 2, 0, H / 2);
sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -W * .75, right: W * .75, top: H * .75, bottom: -H * .75, near: 1, far: 80 });
sun.shadow.bias = -.0006; sun.shadow.normalBias = .02; sun.shadow.radius = 2; sun.shadow.intensity = .75; sun.shadow.mapSize.set(2048, 2048);
sun.shadow.camera.updateProjectionMatrix();
scene.add(sun, sun.target);

const her = figureHer(), him = figureClawd();
her.position.set(D.her[0] + .5, topAt(D.her[0], D.her[1]) ?? 0, D.her[1] + .5);
him.position.set(D.him[0] + .5, topAt(D.him[0], D.him[1]) ?? 0, D.him[1] + .5);
him.rotation.y = .15; her.rotation.y = -.1;
for (const f of [her, him]) {
  const s = new THREE.Mesh(new THREE.CircleGeometry(.28, 16), new THREE.MeshBasicMaterial({ color: '#5a4436', transparent: true, opacity: .16, depthWrite: false }));
  s.rotation.x = -Math.PI / 2; s.position.y = .006; f.add(s);
  scene.add(f);
}
renderer.shadowMap.needsUpdate = true;
window.__dbg = { renderer, sun, scene };
// 她岛上摆的家具、他身上的衣服：从像素图做成立体件（图是异步读的，读完再补一次影子）
Promise.all((D.objects || []).map((o) => placeObject(scene, o, (x, y) => topAt(x, y) ?? 0))).then(() => { renderer.shadowMap.needsUpdate = true; });
if (D.wear?.length && D.rig) dressClawd(him, D.wear, D.rig);

// ———————————————————— 氛围：天、云、雾、光点、草、蝴蝶、柔光 ————————————————————
scene.background = null;
AT.skyDome(scene);
scene.fog = new THREE.FogExp2(new THREE.Color(AT.SKY.fog), .0105);
AT.clouds(scene, W / 2, H / 2);
const moteMat = AT.motes(scene, W / 2, H / 2, W * .9, H * .9);
const grassSpots = [], flowerSpots = [];
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const k = g(x, y); if (k !== 'grass' && k !== 'flowers') continue;
  if (window.__blocked?.has(y * W + x)) continue;
  grassSpots.push([x, y, TOP[k]]); if (k === 'flowers') flowerSpots.push([x, y, TOP[k]]);
}
const grassMat = AT.grassField(scene, grassSpots, 34);
const flyAnim = AT.butterflies(scene, flowerSpots.length ? flowerSpots : grassSpots);
// 亮东西的柔光：每个发光件上贴一圈暖色的柔光片（比全屏后期省电得多）
AT.halos(scene, glowSpots);

// ———————————————————— 镜头 ————————————————————
const cam = new THREE.PerspectiveCamera(36, innerWidth / innerHeight, .1, 900);
const view = { yaw: .35, pitch: .72, dist: 15, target: her.position.clone() };
function placeCam() {
  const t = view.target;
  cam.position.set(t.x + Math.sin(view.yaw) * Math.cos(view.pitch) * view.dist, t.y + .6 + Math.sin(view.pitch) * view.dist, t.z + Math.cos(view.yaw) * Math.cos(view.pitch) * view.dist);
  cam.lookAt(t.x, t.y + .6, t.z);
}
placeCam();
let dirty = true;
const pointers = new Map(); let pinch0 = 0, dist0 = 0;
cv.addEventListener('pointerdown', (e) => { cv.setPointerCapture(e.pointerId); pointers.set(e.pointerId, [e.clientX, e.clientY]); if (pointers.size === 2) { const [a, b] = [...pointers.values()]; pinch0 = Math.hypot(a[0] - b[0], a[1] - b[1]); dist0 = view.dist; } });
cv.addEventListener('pointermove', (e) => {
  if (!pointers.has(e.pointerId)) return;
  const [px, py] = pointers.get(e.pointerId); pointers.set(e.pointerId, [e.clientX, e.clientY]);
  if (pointers.size === 1) { view.yaw -= (e.clientX - px) * .006; view.pitch = Math.max(.12, Math.min(1.45, view.pitch + (e.clientY - py) * .005)); }
  else if (pointers.size === 2) { const [a, b] = [...pointers.values()]; const d = Math.hypot(a[0] - b[0], a[1] - b[1]); view.dist = Math.max(3, Math.min(45, dist0 * pinch0 / Math.max(1, d))); }
  placeCam(); dirty = true;
});
const up = (e) => pointers.delete(e.pointerId);
cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
cv.addEventListener('wheel', (e) => { view.dist = Math.max(3, Math.min(45, view.dist * (1 + e.deltaY * .001))); placeCam(); dirty = true; }, { passive: true });
addEventListener('resize', () => { renderer.setSize(innerWidth, innerHeight, false); cam.aspect = innerWidth / innerHeight; cam.updateProjectionMatrix(); dirty = true; });

// ———————————————————— 走、看、动作（App 通过 window.I3D 来控制） ————————————————————
// 走不进去的格子：海、水、房子实际占的地方、摆好的景和东西（App 传过来的 blocked）
const solid = new Set([...(window.__blocked || []), ...(D.blocked || [])]);
const walkable = (px, pz) => {
  const x = Math.floor(px), y = Math.floor(pz);
  if (x < 0 || y < 0 || x >= W || y >= H || px < .15 || pz < .15) return false;
  const k = g(x, y); if (k === 'sea' || k === 'water') return false;
  return !solid.has(y * W + x);
};
// 站的地方要是被房子占了，往外找一格空的
function freeSpot(x, z) {
  if (walkable(x, z)) return [x, z];
  for (let r = 1; r < 8; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) { const px = Math.floor(x) + dx + .5, pz = Math.floor(z) + dy + .5; if (walkable(px, pz)) return [px, pz]; }
  return [x, z];
}
{ const [hx, hz] = freeSpot(her.position.x, her.position.z); her.position.set(hx, topAt(Math.floor(hx), Math.floor(hz)) ?? 0, hz); const [mx, mz] = freeSpot(him.position.x, him.position.z); him.position.set(mx, topAt(Math.floor(mx), Math.floor(mz)) ?? 0, mz); }
const ground = (x, z) => topAt(Math.floor(x), Math.floor(z)) ?? 0;

const st = {
  stick: [0, 0], person: 'third', gaze: 'forward', photo: false,
  face: 0, action: 'stand', actT: 0, himPose: 'idle', herDir: [0, 1], moving: false, himMoving: false,
  intro: null, clock: 0, walkPhase: 0, himPhase: 0,
};
if (window.ISLAND) { view.yaw = .35; view.pitch = .5; view.dist = 6.5; }
const hearts = [];
function placeView() {
  const p = her.position;
  if (st.person === 'first' && !st.photo) {
    const eye = new THREE.Vector3(p.x, p.y + 1.18, p.z);
    cam.position.copy(eye);
    cam.lookAt(eye.x - Math.sin(view.yaw) * Math.cos(view.pitch), eye.y - Math.sin(view.pitch), eye.z - Math.cos(view.yaw) * Math.cos(view.pitch));
    if (cam.fov !== 66) { cam.fov = 66; cam.updateProjectionMatrix(); }
    her.visible = false;
    return;
  }
  her.visible = true;
  if (window.ISLAND) view.target.set(p.x, p.y, p.z);
  if (cam.fov !== 36) { cam.fov = 36; cam.updateProjectionMatrix(); }
  placeCam();
}
// 进来那一下：镜头从岛的上空慢慢落到她身后
function intro() { st.intro = { t0: st.clock, from: [view.yaw + .4, 1.25, 30], to: [view.yaw, .5, 6.5] }; }

function setFace(i) {
  st.face = i;
  const u = her.userData;
  u.eyes.forEach((e, k) => e.scale.set(1, (i === 1 || (i === 2 && k === 1)) ? .2 : (i === 3 ? 1.15 : 1), 1));
  u.mouth.visible = i !== 3; u.oMouth.visible = i === 3;
  u.mouth.scale.set(i === 1 ? 1.5 : 1, i === 1 ? 1.2 : .8, 1);
}
function act(a) { st.action = a; st.actT = st.clock; }
function setHim(p) {
  st.himPose = p;
  him.userData.eyes.forEach((e) => e.scale.set(1, p === 'sleep' ? .18 : 1, .6));
}
const turn = (from, to) => from + (((to - from + Math.PI * 3) % (Math.PI * 2)) - Math.PI);

function step(dt) {
  st.clock += dt;
  if (st.intro) {
    const k = Math.min(1, (st.clock - st.intro.t0) / 1.6), e = k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
    view.yaw = st.intro.from[0] + (st.intro.to[0] - st.intro.from[0]) * e;
    view.pitch = st.intro.from[1] + (st.intro.to[1] - st.intro.from[1]) * e;
    view.dist = st.intro.from[2] + (st.intro.to[2] - st.intro.from[2]) * e;
    if (k >= 1) st.intro = null;
  }
  // 她走：摇杆往上推 = 往镜头看的方向走
  const [sx, sy] = st.stick, mag = Math.hypot(sx, sy);
  const p = her.position;
  if (mag > .08 && !st.intro && st.action !== 'sit') {
    const fx = -Math.sin(view.yaw), fz = -Math.cos(view.yaw), rx = Math.cos(view.yaw), rz = -Math.sin(view.yaw);
    let mx = rx * sx + fx * -sy, mz = rz * sx + fz * -sy; const l = Math.hypot(mx, mz); if (l > 1) { mx /= l; mz /= l; }
    const speed = 2.4 * Math.min(1, mag);
    let nx = p.x + mx * speed * dt, nz = p.z + mz * speed * dt;
    if (!walkable(nx, nz)) { if (walkable(nx, p.z)) nz = p.z; else if (walkable(p.x, nz)) nx = p.x; else { nx = p.x; nz = p.z; } }
    p.x = nx; p.z = nz;
    const ml = Math.hypot(mx, mz) || 1; st.herDir = [mx / ml, mz / ml];
    st.moving = true; st.walkPhase += dt * 9 * Math.min(1, mag);
  } else st.moving = false;
  // 她的朝向：走的时候朝前；站着时「注视镜头」就转过来看镜头
  let face = Math.atan2(st.herDir[0], st.herDir[1]);
  if (!st.moving && st.gaze === 'screen') face = Math.atan2(cam.position.x - p.x, cam.position.z - p.z);
  her.rotation.y = turn(her.rotation.y, face) * .25 + her.rotation.y * .75;
  // 走路：腿前后迈、手前后摆、身子轻轻一上一下
  const u = her.userData, swing = st.moving ? Math.sin(st.walkPhase) * .55 : 0;
  u.legs[0].rotation.x = swing; u.legs[1].rotation.x = -swing;
  u.arms[0].rotation.x = -swing * .7; u.arms[1].rotation.x = swing * .7;
  let lift = st.moving ? Math.abs(Math.sin(st.walkPhase)) * .03 : Math.sin(st.clock * 2) * .004;
  // 动作：坐下、跳一下、转一圈
  const at = st.clock - st.actT;
  if (st.action === 'jump') { lift += Math.max(0, Math.sin(Math.min(1, at / .6) * Math.PI)) * .45; if (at > .6) st.action = 'stand'; }
  if (st.action === 'spin') { her.rotation.y = face + Math.min(1, at / 1.1) * Math.PI * 2; if (at > 1.1) st.action = 'stand'; }
  if (st.action === 'sit') { lift = -.2; u.legs[0].rotation.x = u.legs[1].rotation.x = -1.3; }
  her.position.y = ground(p.x, p.z) + lift;
  u.head.rotation.z = st.moving ? Math.sin(st.walkPhase) * .03 : Math.sin(st.clock * .8) * .02;

  // 他跟在她身后半步
  const back = st.herDir, tx = p.x - back[0] * .95 + back[1] * .45, tz = p.z - back[1] * .95 - back[0] * .45;
  const hp = him.position, dx = tx - hp.x, dz = tz - hp.z, d = Math.hypot(dx, dz), far = Math.hypot(p.x - hp.x, p.z - hp.z);
  if (far > 1.25 || (d > .35 && st.moving)) {
    const s = Math.min(d, 2.6 * dt);
    let nx = hp.x + dx / (d || 1) * s, nz = hp.z + dz / (d || 1) * s;
    if (!walkable(nx, nz)) { if (walkable(nx, hp.z)) nz = hp.z; else if (walkable(hp.x, nz)) nx = hp.x; else { nx = hp.x; nz = hp.z; } }
    if (Math.hypot(nx - p.x, nz - p.z) > 6) { const [fx2, fz2] = freeSpot(tx, tz); nx = fx2; nz = fz2; }
    hp.x = nx; hp.z = nz; st.himMoving = d > .05; st.himPhase += dt * 12;
    him.rotation.y = turn(him.rotation.y, Math.atan2(dx, dz));
  } else {
    st.himMoving = false;
    if (st.himPose !== 'sleep') him.rotation.y = him.rotation.y + (turn(him.rotation.y, Math.atan2(p.x - hp.x, p.z - hp.z)) - him.rotation.y) * .08;
  }
  const hu = him.userData;
  let hy = .1 + Math.sin(st.clock * 2.4) * .008;
  hu.legs.forEach((l, k) => (l.position.y = .065 + (st.himMoving ? Math.max(0, Math.sin(st.himPhase + k * Math.PI / 2)) * .03 : 0)));
  if (st.himMoving) hy += Math.abs(Math.sin(st.himPhase)) * .05;
  if (st.himPose === 'happy') hy += Math.abs(Math.sin(st.clock * 6)) * .08;
  hu.body.position.y = hy;
  hu.arms[1].rotation.z = st.himPose === 'wave' ? Math.PI / 2 + Math.sin(st.clock * 9) * .5 + .6 : Math.PI / 2;
  hu.body.rotation.z = st.himPose === 'think' ? Math.sin(st.clock * 1.5) * .06 + .1 : 0;
  hp.y = ground(hp.x, hp.z);
  // 爱心：从他头上一颗颗冒出来往上飘
  if (st.himPose === 'love' && (hearts.length === 0 || st.clock - hearts[hearts.length - 1].t > .45)) {
    const sp = new THREE.Sprite(heartMat); sp.scale.set(.18, .18, 1); sp.position.set(hp.x + (Math.random() - .5) * .3, hp.y + .7, hp.z); scene.add(sp); hearts.push({ sp, t: st.clock });
  }
  for (let i = hearts.length - 1; i >= 0; i--) { const h = hearts[i], age = st.clock - h.t; h.sp.position.y += dt * .35; h.sp.scale.setScalar(.18 * (1 - age / 2.2) + .02); if (age > 2.2) { scene.remove(h.sp); hearts.splice(i, 1); } }
  placeView();
}
const heartMat = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d');
  x.fillStyle = '#f07c92'; x.beginPath(); x.moveTo(32, 54); x.bezierCurveTo(4, 34, 10, 8, 32, 22); x.bezierCurveTo(54, 8, 60, 34, 32, 54); x.fill();
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false });
})();

window.I3D = {
  stick(x, y) { st.stick = [x, y]; },
  look(dx, dy) {
    if (st.intro) return;
    view.yaw -= dx * .008;
    if (st.person === 'first' && !st.photo) view.pitch = Math.min(.9, Math.max(-.8, view.pitch + dy * .005));
    else view.pitch = Math.min(1.35, Math.max(.06, view.pitch + dy * .005));
  },
  zoom(k) { if (st.person === 'third' || st.photo) view.dist = Math.min(18, Math.max(2.2, view.dist / k)); },
  person(m) { st.person = m; view.pitch = m === 'first' ? .06 : .5; if (m === 'first') view.yaw = Math.atan2(-st.herDir[0], -st.herDir[1]); },
  gaze(m) { st.gaze = m; },
  photo(on) { st.photo = on; },
  face: setFace, act, him: setHim, intro,
  // 回 2D 时：人在哪一格
  state() { return JSON.stringify({ her: [Math.floor(her.position.x), Math.floor(her.position.z)], him: [Math.floor(him.position.x), Math.floor(him.position.z)] }); },
};
window.__view = view; window.__place = () => { placeView(); };

// ———————————————————— 画 ————————————————————
function drawNow() { renderer.render(scene, cam); }
window.__draw = drawNow;
// 预览里手动走几帧（电脑上面板藏起来时动画不跑）
window.__tick = (n = 1, dt = .033) => { for (let i = 0; i < n; i++) step(dt); drawNow(); };
let last = 0, frames = 0, fpsT = performance.now(), paused = false;
const fpsEl = document.getElementById('fps');
if (window.webkit?.messageHandlers?.i3d) fpsEl.style.display = 'none';   // App 里不显示帧率
document.addEventListener('visibilitychange', () => { paused = document.hidden; });
renderer.setAnimationLoop((ms) => {
  // 一秒最多画 30 帧（压住发热）；App 退到后台就不画
  if (paused || ms - last < 32) return;
  const dt = Math.min(.1, last ? (ms - last) / 1000 : .03); last = ms;
  const ts = ms / 1000;
  seaMat.uniforms.t.value = ts; grassMat.uniforms.t.value = ts; moteMat.uniforms.t.value = ts; flyAnim(ts);
  if (window.ISLAND) step(dt);
  drawNow(); frames++;
  if (ms - fpsT > 1000) { fpsEl.textContent = frames + ' 帧/秒'; frames = 0; fpsT = ms; }
});
if (window.ISLAND) intro();
window.webkit?.messageHandlers?.i3d?.postMessage('ready');
