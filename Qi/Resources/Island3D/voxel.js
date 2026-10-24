// clawd 身上的衣服：在 3D 里是一层贴着身子的膜，不做体积。
// 衣服图跟身体用同一套 36 格图纸（rig：身子在第 left..right 列、第 top..legTop 行）：
// - 落在身子里的那块：做成一层贴膜包在身子上（衬衫、外套、围巾前后都包；眼镜、领结只贴正面；背包只贴背面）
// - 袖子那块（身子两边）：两只小手染成袖子的颜色
// - 裤腿、鞋（腿那几行）：腿染成那个颜色
// - 帽子（身子上面那几行）：照帽子图的轮廓转一圈，做成一顶戴在头顶的圆帽
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

function load(src) {
  return new Promise((ok) => { const im = new Image(); im.onload = () => ok(im); im.onerror = () => ok(null); im.src = src; });
}
// 缩成 grid 格（衣服图是 36 格放大 8 倍画的）
function pixels(im, grid) {
  const c = document.createElement('canvas'); c.width = grid; c.height = grid;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(im, 0, 0, grid, grid);
  return { w: grid, h: grid, d: x.getImageData(0, 0, grid, grid).data };
}
const at = (px, x, y) => { const i = (y * px.w + x) * 4; return [px.d[i], px.d[i + 1], px.d[i + 2], px.d[i + 3]]; };
// 一块里最多的那个颜色
function dominant(px, x0, y0, x1, y1) {
  const tally = new Map();
  for (let y = Math.max(0, y0); y <= Math.min(px.h - 1, y1); y++) for (let x = Math.max(0, x0); x <= Math.min(px.w - 1, x1); x++) {
    const [r, g, b, a] = at(px, x, y); if (a < 100) continue;
    const k = (r >> 4) + ',' + (g >> 4) + ',' + (b >> 4); const e = tally.get(k) || [0, 0, 0, 0];
    tally.set(k, [e[0] + 1, e[1] + r, e[2] + g, e[3] + b]);
  }
  let best = null; for (const v of tally.values()) if (!best || v[0] > best[0]) best = v;
  return best ? new THREE.Color().setRGB(best[1] / best[0] / 255, best[2] / best[0] / 255, best[3] / best[0] / 255, THREE.SRGBColorSpace) : null;
}
// 把图纸上一块（x0..x1, y0..y1）画成贴图。用衣服原图（一格 8 个像素，领口、扣子、口袋这些细节都在），不缩成格子：
// - 去掉衣服外沿那一圈深色描边（贴到圆润的身子上像一圈黑框），换成里面的布料色
// - 剪影边缘磨圆（像一块剪好的布），里面的花纹照原图清清楚楚
function regionTex(im, grid, px, x0, y0, x1, y1) {
  let any = false;
  for (let y = Math.max(0, y0); y <= Math.min(px.h - 1, y1) && !any; y++) for (let x = Math.max(0, x0); x <= Math.min(px.w - 1, x1); x++) if (at(px, x, y)[3] >= 100) { any = true; break; }
  if (!any) return null;
  const P = 2, k = Math.max(1, Math.round(im.width / grid));   // 四周留两格透明；k = 一格几个像素
  const W = x1 - x0 + 1 + P * 2, H = y1 - y0 + 1 + P * 2, w = W * k, h = H * k;
  const src = document.createElement('canvas'); src.width = w; src.height = h;
  const sg = src.getContext('2d'); sg.imageSmoothingEnabled = false;
  const cw = im.width / grid, ch = im.height / grid;
  sg.drawImage(im, (x0 - P) * cw, (y0 - P) * ch, W * cw, H * ch, 0, 0, w, h);
  const id = sg.getImageData(0, 0, w, h), d = id.data, n = w * h;
  const op = new Uint8Array(n); for (let i = 0; i < n; i++) op[i] = d[i * 4 + 3] >= 128 ? 1 : 0;
  const lum = (i) => d[i * 4] * .3 + d[i * 4 + 1] * .59 + d[i * 4 + 2] * .11;
  // 描边：挨着外面的那一两圈，比里面一格暗很多的 → 换成里面的颜色（剥两层，原图描边一般一两个像素宽）
  for (let pass = 0; pass < Math.max(2, k / 4); pass++) {
    const out = new Uint8Array(n); for (let i = 0; i < n; i++) out[i] = op[i] ? 0 : 1;
    const edge = [];
    for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
      const i = y * w + x; if (!op[i]) continue;
      if (!(out[i - 1] || out[i + 1] || out[i - w] || out[i + w])) continue;
      let best = -1, bl = -1;
      for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-2, 0], [2, 0], [0, -2], [0, 2]]) {
        const xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        const j = yy * w + xx; if (op[j] && lum(j) > bl) { bl = lum(j); best = j; }
      }
      if (best >= 0 && lum(i) < bl * .8) edge.push([i, best]);
    }
    for (const [i, j] of edge) { d[i * 4] = d[j * 4]; d[i * 4 + 1] = d[j * 4 + 1]; d[i * 4 + 2] = d[j * 4 + 2]; }
  }
  // 透明的地方也填上旁边的颜色（放大磨边时不会混进黑边）
  const has = op.slice();
  for (let pass = 0; pass < k * 2; pass++) {
    const add = [];
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x; if (has[i]) continue;
      for (const j of [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1]) if (j >= 0 && has[j]) { add.push([i, j]); break; }
    }
    if (!add.length) break;
    for (const [i, j] of add) { has[i] = 1; d[i * 4] = d[j * 4]; d[i * 4 + 1] = d[j * 4 + 1]; d[i * 4 + 2] = d[j * 4 + 2]; }
  }
  for (let i = 0; i < n; i++) d[i * 4 + 3] = 255;
  sg.putImageData(id, 0, 0);
  const mask = document.createElement('canvas'); mask.width = w; mask.height = h;
  const mg = mask.getContext('2d'), md = mg.createImageData(w, h);
  for (let i = 0; i < n; i++) md.data[i * 4 + 3] = op[i] ? 255 : 0;
  mg.putImageData(md, 0, 0);
  const S = Math.max(2, Math.round(24 / k)), big = document.createElement('canvas'); big.width = w * S; big.height = h * S;
  const g = big.getContext('2d'), cell = k * S;
  // 先画一张糊开的剪影，再把透明度拉陡 → 边缘是一条顺滑的线
  g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  g.filter = 'blur(' + (cell * .4) + 'px)'; g.drawImage(mask, 0, 0, w * S, h * S); g.filter = 'none';
  const im2 = g.getImageData(0, 0, w * S, h * S), dd = im2.data;
  for (let i = 3; i < dd.length; i += 4) dd[i] = Math.max(0, Math.min(255, (dd[i] - 118) * 9));
  g.putImageData(im2, 0, 0);
  // 布料颜色只画在剪影里：原图放大，稍微柔一点（不出锯齿，也不糊掉扣子）
  g.globalCompositeOperation = 'source-in';
  g.filter = 'blur(' + (S * .5) + 'px)'; g.drawImage(src, 0, 0, w * S, h * S); g.filter = 'none';
  g.globalCompositeOperation = 'source-over';
  const t = new THREE.CanvasTexture(big); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return { tex: t, w: W, h: H, pad: P };
}
// 一层膜：比身子大一丝的圆角盒子，贴图从正面投过去（侧面顺着边上那一格延伸，像布包过去）
function film(size, center, region, { front = true, back = false } = {}) {
  const [W, H, D] = size;
  const geo = new RoundedBoxGeometry(W * 1.012, H * 1.012, D * 1.02, 6, Math.min(.15, H * .33));
  const pa = geo.attributes.position, na = geo.attributes.normal, uv = geo.attributes.uv;
  const pxU = (region.pad || 1) / region.w, pxV = (region.pad || 1) / region.h;
  for (let i = 0; i < pa.count; i++) {
    const x = pa.getX(i), y = pa.getY(i), nz = na.getZ(i);
    let u = .5 + x / W * (1 - 2 * pxU), v = .5 + y / H * (1 - 2 * pxV);
    u = Math.min(1 - pxU * 1.01, Math.max(pxU * 1.01, u)); v = Math.min(1 - pxV * 1.01, Math.max(pxV * 1.01, v));
    if (nz < -.35) { if (!back) { u = pxU * .5; v = pxV * .5; } else u = 1 - u; }   // 背面：要包就镜像过去，不包就落在透明的那一圈
    else if (nz > .35 && !front) { u = pxU * .5; v = pxV * .5; }
    uv.setXY(i, u, v);
  }
  const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: region.tex, transparent: true, alphaTest: .45, roughness: .62 }));
  m.position.set(...center);
  return m;
}

// 帽子：帽子图在身子上面那几行。每一行量出宽度和颜色，顺着这条轮廓转一圈（前后压扁一点跟身子一样），
// 轮廓抹圆了再转，所以是一顶软软的圆帽（贝雷帽顶上那颗小揪、睡帽的尖都会自己长出来）
function hatMesh(px, L, R, T, B) {
  const rows = [];
  for (let y = 0; y < T; y++) {
    let x0 = 99, x1 = -1;
    for (let x = 0; x < px.w; x++) if (at(px, x, y)[3] >= 100) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); }
    if (x1 >= 0) rows.push({ y, hw: (x1 - x0 + 1) / 2, cx: (x0 + x1 + 1) / 2, col: dominant(px, x0, y, x1, y) });
  }
  if (!rows.length) return null;
  const ux = .62 / (R - L + 1), uy = .46 / (B - T + 1) * .9, mid = (L + R + 1) / 2;
  const top = rows[0].y, bot = rows[rows.length - 1].y, Hh = (bot - top + 1) * uy;
  // 轮廓（从下往上）：底边往里收一点贴住头顶，每行的半宽抹一遍让台阶变成弧线
  const hw = rows.map((r) => r.hw);
  const sm = hw.map((h, i) => (hw[Math.max(0, i - 1)] + h * 2 + hw[Math.min(hw.length - 1, i + 1)]) / 4);
  const pts = [new THREE.Vector2(0, 0), new THREE.Vector2(sm[sm.length - 1] * ux * .92, 0)];
  for (let i = rows.length - 1; i >= 0; i--) pts.push(new THREE.Vector2(Math.max(.012, sm[i] * ux), (bot - rows[i].y + .5) * uy));
  pts.push(new THREE.Vector2(0, Hh));
  const prof = new THREE.SplineCurve(pts).getPoints(60);
  prof[0].set(0, 0); prof[prof.length - 1].set(0, Hh);
  const geo = new THREE.LatheGeometry(prof, 40);
  // 颜色：按高度取那一行的颜色
  const cols = new Float32Array(geo.attributes.position.count * 3), pa = geo.attributes.position;
  const fall = dominant(px, 0, 0, px.w - 1, T - 1);
  for (let i = 0; i < pa.count; i++) {
    const ry = bot + .5 - pa.getY(i) / uy;
    let best = rows[0]; for (const r of rows) if (Math.abs(r.y - ry) < Math.abs(best.y - ry)) best = r;
    const c = best.col || fall; cols[i * 3] = c.r; cols[i * 3 + 1] = c.g; cols[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .7 }));
  // 戴在头顶：底边沉进头顶一点（身子顶上的圆角往下弯，帽沿要盖住），帽子偏左偏右照着图
  const cx = rows.reduce((s, r) => s + r.cx, 0) / rows.length;
  m.position.set((cx - mid) * ux, .425, 0);
  m.scale.set(1, 1, .44 / .62);
  m.castShadow = true;
  return m;
}

export async function dressClawd(him, wear, rig) {
  const u = him.userData, body = u.body, grid = rig.grid || 36;
  const L = rig.left, R = rig.right, T = rig.top, B = rig.legTop - 1;
  for (const w of wear) {
    const im = await load(w.png); if (!im) continue;
    const px = pixels(im, grid);
    if (w.slot === 'eyes') u.eyes.forEach((e) => (e.visible = false));
    // 身子那块：一层贴膜
    const reg = regionTex(im, grid, px, L, T, R, B);
    if (reg) {
      const wrap = w.slot === 'body' || w.slot === 'outer' || w.slot === 'scarf';
      body.add(film([.62, .46, .44], [0, .23, 0], reg, { front: w.slot !== 'back', back: wrap || w.slot === 'back' }));
    }
    // 袖子：两只小手染色
    const left = dominant(px, 0, T, L - 1, B), right = dominant(px, R + 1, T, grid - 1, B);
    if (left && u.arms[0]) u.arms[0].material = new THREE.MeshStandardMaterial({ color: left, roughness: .55 });
    if (right && u.arms[1]) u.arms[1].material = new THREE.MeshStandardMaterial({ color: right, roughness: .55 });
    // 裤腿、鞋：腿染色
    const feet = dominant(px, 0, rig.legTop, grid - 1, grid - 1);
    if (feet) for (const l of u.legs) l.material = new THREE.MeshStandardMaterial({ color: feet, roughness: .55 });
    // 帽子：按帽子图每一行的宽度转一圈做成一顶圆圆的帽子，戴在头顶（不盖住眼睛）
    if (w.slot === 'head') { const hat = hatMesh(px, L, R, T, B); if (hat) body.add(hat); }
  }
}
