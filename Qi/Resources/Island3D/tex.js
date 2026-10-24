// 细密的贴图：鱼鳞石板瓦、护墙板、深灰石块墙、米色方石。画在小画布上，四边接得上，按世界坐标铺
import * as THREE from 'three';

function canvasTex(n, draw, repeat) {
  const c = document.createElement('canvas'); c.width = c.height = n;
  draw(c.getContext('2d'), n);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  t.repeat.set(repeat, repeat);
  return t;
}
let s = 11; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);

// 鱼鳞瓦：一排排半圆，下一排错开半个，每片上亮下暗，偶尔一片深一点
export const fishScale = canvasTex(256, (g, n) => {
  const rows = 8, cols = 8, w = n / cols, h = n / rows;
  g.fillStyle = '#20293a'; g.fillRect(0, 0, n, n);
  for (let row = rows; row >= -1; row--) for (let col = -1; col <= cols; col++) {
    const x = col * w + (row % 2 ? w / 2 : 0), y = row * h;
    const k = .86 + r() * .22;
    const gr = g.createLinearGradient(0, y - h * .2, 0, y + h * 1.1);
    gr.addColorStop(0, `rgb(${70 * k | 0},${86 * k | 0},${112 * k | 0})`); gr.addColorStop(1, `rgb(${40 * k | 0},${50 * k | 0},${70 * k | 0})`);
    g.fillStyle = gr;
    g.beginPath(); g.moveTo(x, y - h * .1); g.lineTo(x + w, y - h * .1); g.lineTo(x + w, y + h * .45);
    g.arc(x + w / 2, y + h * .45, w / 2, 0, Math.PI, false); g.closePath(); g.fill();
    g.strokeStyle = 'rgba(15,20,30,.55)'; g.lineWidth = 1.2; g.beginPath(); g.arc(x + w / 2, y + h * .45, w / 2 - .5, 0, Math.PI, false); g.stroke();
    g.strokeStyle = 'rgba(190,205,225,.18)'; g.beginPath(); g.arc(x + w / 2, y + h * .4, w / 2 - 3, Math.PI * .15, Math.PI * .85, false); g.stroke();
  }
}, 7);

// 方形石板瓦（哥特那栋的尖顶用）
export const slateTiles = canvasTex(256, (g, n) => {
  const rows = 10, cols = 8, w = n / cols, h = n / rows;
  g.fillStyle = '#4a5466'; g.fillRect(0, 0, n, n);
  for (let row = 0; row < rows; row++) for (let col = -1; col <= cols; col++) {
    const x = col * w + (row % 2 ? w / 2 : 0) + 1, y = row * h + 1, k = .8 + r() * .35;
    g.fillStyle = `rgb(${108 * k | 0},${120 * k | 0},${142 * k | 0})`; g.fillRect(x, y, w - 2, h - 2);
    g.fillStyle = 'rgba(255,255,255,.07)'; g.fillRect(x, y, w - 2, 2);
  }
}, 7);

// 护墙板：一道道横板，每道上沿一线影子
export const siding = canvasTex(256, (g, n) => {
  g.fillStyle = '#f2ece0'; g.fillRect(0, 0, n, n);
  const rows = 12, h = n / rows;
  for (let i = 0; i < rows; i++) {
    const y = i * h;
    const gr = g.createLinearGradient(0, y, 0, y + h); gr.addColorStop(0, 'rgba(120,105,85,.28)'); gr.addColorStop(.18, 'rgba(120,105,85,0)'); gr.addColorStop(1, 'rgba(255,255,255,.05)');
    g.fillStyle = gr; g.fillRect(0, y, n, h);
  }
}, 5);

// 深灰石块墙：大小不一的石块、浅色灰缝、每块深浅不一
export const darkStone = canvasTex(512, (g, n) => {
  g.fillStyle = '#d9d4cb'; g.fillRect(0, 0, n, n);
  let y = 0;
  while (y < n) {
    const h = 22 + (r() * 14 | 0); let x = -r() * 40;
    while (x < n) {
      const w = 34 + r() * 46, k = .75 + r() * .4;
      const base = [168, 164, 160].map((v) => Math.min(255, v * k | 0));
      const gr = g.createLinearGradient(x, y, x, y + h);
      gr.addColorStop(0, `rgb(${base[0] + 18},${base[1] + 18},${base[2] + 20})`); gr.addColorStop(1, `rgb(${base[0]},${base[1]},${base[2]})`);
      g.fillStyle = gr; g.fillRect(x + 2, y + 2, w - 3, h - 3);
      for (const xx of [x - n, x + n]) { g.fillRect(xx + 2, y + 2, w - 3, h - 3); }
      x += w;
    }
    y += h;
  }
}, 4);

// 米色方石（窗套、隅石、台阶用）
export const ashlar = canvasTex(256, (g, n) => {
  g.fillStyle = '#cbbd9f'; g.fillRect(0, 0, n, n);
  const rows = 6, h = n / rows;
  for (let i = 0; i < rows; i++) for (let x = (i % 2) * -32; x < n; x += 64) {
    const k = .94 + r() * .1;
    g.fillStyle = `rgb(${232 * k | 0},${221 * k | 0},${196 * k | 0})`; g.fillRect(x + 1.5, i * h + 1.5, 61, h - 3);
  }
}, 6);

// 灰蓝粗面石（宅邸的勒脚）
export const plinthStone = canvasTex(256, (g, n) => {
  g.fillStyle = '#6f7887'; g.fillRect(0, 0, n, n);
  const rows = 4, h = n / rows;
  for (let i = 0; i < rows; i++) for (let x = (i % 2) * -48; x < n; x += 96) {
    const k = .9 + r() * .15;
    g.fillStyle = `rgb(${128 * k | 0},${138 * k | 0},${152 * k | 0})`; g.fillRect(x + 3, i * h + 3, 90, h - 6);
  }
}, 6);
