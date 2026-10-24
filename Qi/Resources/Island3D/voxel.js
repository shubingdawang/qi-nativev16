// 像素图 → 立体件：她岛上摆的家具（像素画）、clawd 身上的衣服，一个像素一颗小方块拼起来，
// 所以不管哪一件、她自己导入的也一样，都能在 3D 里出现。
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

function load(src) {
  return new Promise((ok) => { const im = new Image(); im.onload = () => ok(im); im.onerror = () => ok(null); im.src = src; });
}
// grid：先缩成这么多格（衣服图是 36 格放大 8 倍画的）；不给就按原图
function pixels(im, grid = 0) {
  const w = grid || im.width, h = grid || im.height;
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(im, 0, 0, w, h);
  return { w, h, d: x.getImageData(0, 0, w, h).data };
}
const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .6 });
const cube = new THREE.BoxGeometry(1, 1, 1);

// 一张像素图里有东西的那几格（透明的不算）
function opaque(px, rect = null) {
  const out = [];
  const x0 = rect ? rect[0] : 0, y0 = rect ? rect[1] : 0, x1 = rect ? rect[2] : px.w - 1, y1 = rect ? rect[3] : px.h - 1;
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = (y * px.w + x) * 4; if (px.d[i + 3] < 100) continue;
    out.push([x, y, px.d[i] / 255, px.d[i + 1] / 255, px.d[i + 2] / 255]);
  }
  return out;
}
// 一堆格子 → 一个网格：每格一颗方块（颜色写在顶点上，整件一次绘制）
function build(cells, size, depth, place) {
  const list = [];
  const col = new THREE.Color();
  for (const [x, y, r, g, b] of cells) {
    const geo = cube.clone(); geo.scale(size * 1.02, size * 1.02, depth);
    const [px, py, pz] = place(x, y); geo.translate(px, py, pz);
    col.setRGB(r, g, b, THREE.SRGBColorSpace);
    const n = geo.attributes.position.count, ca = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) { ca[i * 3] = col.r; ca[i * 3 + 1] = col.g; ca[i * 3 + 2] = col.b; }
    geo.setAttribute('color', new THREE.BufferAttribute(ca, 3)); geo.deleteAttribute('uv');
    list.push(geo);
  }
  if (!list.length) return null;
  const m = new THREE.Mesh(mergeGeometries(list), mat); m.castShadow = true; m.receiveShadow = true;
  return m;
}

// 岛上摆的一件家具：底边中点放在那一格，宽 w 格
export async function placeObject(scene, o, groundAt) {
  const im = await load(o.png); if (!im) return;
  const px = pixels(im), cells = opaque(px);
  if (!cells.length) return;
  let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
  for (const [x, y] of cells) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  const bw = maxX - minX + 1, size = Math.min((o.w || 1) * .9 / bw, .06), depth = Math.min(.5, bw * size * .45);
  const cx = o.x + (o.w || 1) / 2, cz = o.y + .5, t = groundAt(o.x, o.y);
  const mesh = build(cells, size, depth, (x, y) => [cx + (x - (minX + maxX) / 2) * size, t + (maxY - y + .5) * size, cz]);
  if (mesh) scene.add(mesh);
}

// clawd 身上的衣服：图纸跟身体同一套格子（rig：身子在第 left..right 列、第 top..legTop 行）。
// 落在身子里的像素印在身子正面（像潮玩的涂装），伸出身子的（帽子、包、鞋）做成小方块挂上去。
export async function dressClawd(him, wear, rig) {
  const u = him.userData, body = u.body;
  const cols = rig.right - rig.left + 1, rows = rig.legTop - rig.top;
  const size = .62 / cols;
  const X = (x) => (x + .5 - (rig.left + rig.right + 1) / 2) * size;
  const Y = (y) => .46 * (rig.legTop - (y + .5)) / rows;   // 身子底边 = 0（在 body 组里）
  for (const w of wear) {
    const im = await load(w.png); if (!im) continue;
    const px = pixels(im, rig.grid || 36);
    if (w.slot === 'eyes') u.eyes.forEach((e) => (e.visible = false));
    // 身子范围里：画成一张贴图，贴在正面
    const inside = opaque(px, [rig.left, rig.top, rig.right, rig.legTop - 1]);
    if (inside.length) {
      const c = document.createElement('canvas'); c.width = cols; c.height = rows;
      const x = c.getContext('2d'), id = x.createImageData(cols, rows);
      for (const [cx, cy] of inside) { const si = (cy * px.w + cx) * 4, di = ((cy - rig.top) * cols + (cx - rig.left)) * 4; for (let k = 0; k < 4; k++) id.data[di + k] = px.d[si + k]; }
      x.putImageData(id, 0, 0);
      const tex = new THREE.CanvasTexture(c); tex.magFilter = THREE.NearestFilter; tex.colorSpace = THREE.SRGBColorSpace;
      const plane = new THREE.Mesh(new THREE.PlaneGeometry(.6, .44), new THREE.MeshStandardMaterial({ map: tex, transparent: true, alphaTest: .4, roughness: .6 }));
      plane.position.set(0, .23, .223); body.add(plane);
      // 贴身穿的（衬衫、外套）：身子侧面和背面也染成衣服的主色
      if (w.slot === 'body' || w.slot === 'outer') {
        const tally = new Map(); for (const [, , r, g, b] of inside) { const k = ((r * 15) | 0) + ',' + ((g * 15) | 0) + ',' + ((b * 15) | 0); tally.set(k, (tally.get(k) || 0) + 1); }
        const top = [...tally.entries()].sort((a, b) => b[1] - a[1])[0][0].split(',').map((v) => (+v + .5) / 15);
        const shell = new THREE.Mesh(new RoundedBoxGeometry(.635, .3, .455, 6, .15), new THREE.MeshStandardMaterial({ color: new THREE.Color().setRGB(top[0], top[1], top[2], THREE.SRGBColorSpace), roughness: .6 }));
        shell.position.set(0, .15, 0); body.add(shell);
      }
    }
    // 身子外面：一颗颗小方块（头上的厚一点，旁边的薄一点）
    const outside = opaque(px).filter(([x, y]) => x < rig.left || x > rig.right || y < rig.top || y >= rig.legTop);
    const head = outside.filter(([, y]) => y < rig.top), side = outside.filter(([x, y]) => y >= rig.top && y < rig.legTop), feet = outside.filter(([, y]) => y >= rig.legTop);
    const mh = build(head, size, .34, (x, y) => [X(x), Y(y), 0]); if (mh) body.add(mh);
    const ms = build(side, size, .2, (x, y) => [X(x), Y(y), w.slot === 'back' ? -.15 : 0]); if (ms) body.add(ms);
    const mf = build(feet, size, .12, (x, y) => [X(x), .1 + Y(y) - .02, .1]); if (mf) him.add(mf);
  }
}
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
