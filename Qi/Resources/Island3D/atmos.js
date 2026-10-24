// 光遇那种氛围：渐变的天、柔软的云、太阳光晕、远处的雾、亮东西的柔光（自己写的轻量光晕）、飘着的光点、
// 随风摆的草（一次绘制画成千上万根）、空地上自动长出来的野花和蝴蝶（只是装饰，不改她岛上的布局）。
import * as THREE from 'three';

// 夜里：深蓝的天、冷冷的月光、天边一点紫，星星和萤火虫
export const NIGHT = { top: '#0b1634', mid: '#1f3566', horizon: '#56578a', glow: '#d6defc', fog: '#33395f', sun: new THREE.Vector3(.5, .45, -.74).normalize() };
export const SKY = { top: '#2f5f9e', mid: '#6f9fd2', horizon: '#ecc9a4', glow: '#ffd9a6', fog: '#ecc9a4', sun: new THREE.Vector3(-.55, .32, .77).normalize() };

// ———— 天：一个大球，竖着从深蓝到地平线暖金，太阳那边亮一片 ————
export function skyDome(scene) {
  const g = new THREE.SphereGeometry(400, 48, 24);
  const m = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color(SKY.top) }, mid: { value: new THREE.Color(SKY.mid) }, hor: { value: new THREE.Color(SKY.horizon) }, glow: { value: new THREE.Color(SKY.glow) }, sun: { value: SKY.sun } },
    vertexShader: `varying vec3 vD; void main(){ vD = normalize(position); vec4 p = projectionMatrix * modelViewMatrix * vec4(position,1.); gl_Position = p.xyww; }`,
    fragmentShader: `uniform vec3 top, mid, hor, glow, sun; varying vec3 vD;
      void main(){
        float y = vD.y;
        vec3 c = mix(hor, mid, smoothstep(0., .25, y));
        c = mix(c, top, smoothstep(.25, .9, y));
        c = mix(c, hor * .95, smoothstep(0., -.2, y));
        float s = max(dot(vD, sun), 0.);
        c += glow * (pow(s, 6.) * .35 + pow(s, 60.) * .6 + pow(s, 900.) * 2.);
        gl_FragColor = vec4(c, 1.);
        #include <colorspace_fragment>
      }`,
  });
  const mesh = new THREE.Mesh(g, m); mesh.renderOrder = -10; mesh.frustumCulled = false;
  scene.add(mesh);
  return mesh;
}

// 星星：天上一层一闪一闪的小点（只在夜里加）
export function stars(scene) {
  const n = 900, pos = new Float32Array(n * 3), seed = new Float32Array(n);
  let s = 5; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < n; i++) {
    const th = r() * Math.PI * 2, y = .08 + r() * .92, rr = Math.sqrt(1 - y * y);
    pos[i * 3] = Math.cos(th) * rr * 380; pos[i * 3 + 1] = y * 380; pos[i * 3 + 2] = Math.sin(th) * rr * 380; seed[i] = r() * 100;
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('seed', new THREE.BufferAttribute(seed, 1));
  const m = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, fog: false, blending: THREE.AdditiveBlending, uniforms: { t: { value: 0 }, px: { value: Math.min(devicePixelRatio, 2) } },
    vertexShader: `uniform float t, px; attribute float seed; varying float vA; void main(){ vec4 mv = modelViewMatrix * vec4(position, 1.); gl_Position = projectionMatrix * mv; gl_Position.z = gl_Position.w; vA = .45 + .55 * sin(t * (1. + fract(seed)) + seed * 9.); gl_PointSize = (1.2 + fract(seed * 7.) * 2.2) * px; }`,
    fragmentShader: `varying float vA; void main(){ float d = length(gl_PointCoord - .5); gl_FragColor = vec4(.92, .94, 1., smoothstep(.5, 0., d) * vA); }`,
  });
  const p = new THREE.Points(g, m); p.frustumCulled = false; p.renderOrder = -9; scene.add(p);
  return m;
}

// ———— 云：一张张柔软的云贴片，围着岛一圈，远的大近的小，跟着镜头转（永远朝着你） ————
function cloudTex() {
  const n = 256, c = document.createElement('canvas'); c.width = c.height = n;
  const g = c.getContext('2d');
  let s = 3; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < 26; i++) {
    const x = n * (.2 + r() * .6), y = n * (.45 + (r() - .5) * .3), rad = n * (.1 + r() * .16);
    const gr = g.createRadialGradient(x, y, 0, x, y, rad);
    gr.addColorStop(0, 'rgba(255,255,255,.5)'); gr.addColorStop(.6, 'rgba(255,250,245,.25)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, n, n);
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
export function clouds(scene, cx, cz) {
  const tex = cloudTex(), grp = new THREE.Group();
  let s = 9; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < 26; i++) {
    const a = i / 26 * Math.PI * 2 + r() * .2, d = 70 + r() * 90, sc = 30 + r() * 40;
    const m = new THREE.SpriteMaterial({ map: tex, color: new THREE.Color(r() < .5 ? '#fff6ec' : '#f8e7dc'), transparent: true, opacity: .55 + r() * .3, depthWrite: false, fog: false });
    const sp = new THREE.Sprite(m); sp.scale.set(sc * 1.8, sc * .7, 1);
    sp.position.set(cx + Math.cos(a) * d, 6 + r() * 28, cz + Math.sin(a) * d); grp.add(sp);
  }
  // 海面上低低的一层云雾，把海平线化开
  for (let i = 0; i < 18; i++) {
    const a = i / 18 * Math.PI * 2, d = 55 + r() * 30, sc = 40 + r() * 20;
    const m = new THREE.SpriteMaterial({ map: tex, color: new THREE.Color('#fbefe2'), transparent: true, opacity: .16 + r() * .1, depthWrite: false, fog: false });
    const sp = new THREE.Sprite(m); sp.scale.set(sc * 1.6, sc * .55, 1); sp.position.set(cx + Math.cos(a) * d, 1 + r() * 6, cz + Math.sin(a) * d); grp.add(sp);
  }
  scene.add(grp); return grp;
}

// ———— 光点：慢慢往上飘、一闪一闪的小亮点（一次绘制） ————
export function motes(scene, cx, cz, w, h) {
  const n = 260, pos = new Float32Array(n * 3), seed = new Float32Array(n);
  let s = 21; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < n; i++) { pos[i * 3] = cx + (r() - .5) * w; pos[i * 3 + 1] = r() * 4; pos[i * 3 + 2] = cz + (r() - .5) * h; seed[i] = r() * 100; }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('seed', new THREE.BufferAttribute(seed, 1));
  const m = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    uniforms: { t: { value: 0 }, px: { value: Math.min(devicePixelRatio, 2) }, col: { value: new THREE.Color(1, .92, .72) } },
    vertexShader: `uniform float t, px; attribute float seed; varying float vA;
      void main(){ vec3 p = position; p.y = mod(p.y + t * (.08 + fract(seed) * .1), 4.) + .2; p.x += sin(t * .3 + seed) * .4; p.z += cos(t * .25 + seed * 1.3) * .4;
        vec4 mv = modelViewMatrix * vec4(p, 1.); gl_Position = projectionMatrix * mv;
        vA = (.5 + .5 * sin(t * 1.5 + seed * 7.)) * smoothstep(4.2, 2.5, p.y) * smoothstep(.2, .8, p.y);
        gl_PointSize = (6. + fract(seed * 3.) * 6.) * px * (8. / -mv.z); }`,
    fragmentShader: `uniform vec3 col; varying float vA; void main(){ float d = length(gl_PointCoord - .5); float a = smoothstep(.5, 0., d) * vA; gl_FragColor = vec4(col, a * .85); }`,
  });
  const pts = new THREE.Points(g, m); pts.frustumCulled = false; scene.add(pts);
  return m;
}

// ———— 随风摆的草：一根根细细的草叶，按格子撒在草地上，底下深上面亮，顶端被风吹得来回摆 ————
export function grassField(scene, spots, density = 34) {
  const blade = new THREE.BufferGeometry();
  blade.setAttribute('position', new THREE.Float32BufferAttribute([-.012, 0, 0, .012, 0, 0, -.008, .5, 0, .008, .5, 0, 0, 1, 0], 3));
  blade.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 1, 0, 0, .5, 1, .5, .5, 1], 2));
  blade.setIndex([0, 1, 2, 2, 1, 3, 2, 3, 4]); blade.computeVertexNormals();
  const count = spots.length * density;
  const inst = new THREE.InstancedBufferGeometry(); inst.index = blade.index; inst.attributes.position = blade.attributes.position; inst.attributes.uv = blade.attributes.uv;
  const off = new Float32Array(count * 4), tint = new Float32Array(count);
  let s = 77; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  let k = 0;
  for (const [x, y, top] of spots) for (let i = 0; i < density; i++) {
    off[k * 4] = x + r(); off[k * 4 + 1] = top; off[k * 4 + 2] = y + r(); off[k * 4 + 3] = .12 + r() * .16;   // 高度
    tint[k] = r(); k++;
  }
  inst.setAttribute('offset', new THREE.InstancedBufferAttribute(off, 4)); inst.setAttribute('tint', new THREE.InstancedBufferAttribute(tint, 1));
  inst.instanceCount = count;
  const m = new THREE.ShaderMaterial({
    side: THREE.DoubleSide, fog: true,
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { t: { value: 0 }, base: { value: new THREE.Color('#6f8a4e') }, tipA: { value: new THREE.Color('#b8c98a') }, tipB: { value: new THREE.Color('#d9d39a') }, sun: { value: new THREE.Color('#fff0d8') } }]),
    vertexShader: `uniform float t; attribute vec4 offset; attribute float tint; varying vec2 vUv; varying float vT;
      #include <fog_pars_vertex>
      void main(){
        vUv = uv; vT = tint;
        float ang = tint * 6.283;
        vec3 p = position; p.y *= offset.w;
        vec3 q = vec3(p.x * cos(ang), p.y, p.x * sin(ang));
        float wind = sin(t * 1.6 + offset.x * .6 + offset.z * .4) * .5 + sin(t * 2.7 + offset.x * 1.7) * .2;
        q.x += wind * .06 * uv.y * uv.y; q.z += wind * .03 * uv.y * uv.y;
        vec4 mvPosition = modelViewMatrix * vec4(q + offset.xyz, 1.);
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 base, tipA, tipB, sun; varying vec2 vUv; varying float vT;
      #include <fog_pars_fragment>
      void main(){
        vec3 tip = mix(tipA, tipB, vT);
        vec3 c = mix(base, tip, smoothstep(0., 1., vUv.y));
        c *= .78 + .3 * vUv.y;
        gl_FragColor = vec4(c, 1.);
        #include <colorspace_fragment>
        #include <fog_fragment>
      }`,
  });
  const mesh = new THREE.Mesh(inst, m); mesh.frustumCulled = false; scene.add(mesh);
  return m;
}

// ———— 蝴蝶：几只在花丛上飞来飞去，翅膀一扇一扇 ————
export function butterflies(scene, spots) {
  const grp = new THREE.Group(), list = [];
  const wing = new THREE.CircleGeometry(.05, 10); wing.scale(1, .75, 1);
  const cols = ['#f7d7e4', '#fff3c9', '#d7e7ff', '#ffffff'];
  for (let i = 0; i < Math.min(10, spots.length); i++) {
    const b = new THREE.Group(), mat = new THREE.MeshBasicMaterial({ color: cols[i % 4], side: THREE.DoubleSide, transparent: true, opacity: .95 });
    const L = new THREE.Mesh(wing, mat), Rw = new THREE.Mesh(wing, mat);
    L.position.x = -.04; Rw.position.x = .04; b.add(L, Rw);
    const [x, y, top] = spots[(i * 37) % spots.length];
    b.userData = { L, Rw, x: x + .5, z: y + .5, y: top + .4, ph: i * 1.7 };
    grp.add(b); list.push(b);
  }
  scene.add(grp);
  return (t) => { for (const b of list) { const u = b.userData, a = t * .5 + u.ph; b.position.set(u.x + Math.sin(a) * .8, u.y + Math.sin(a * 2.3) * .15, u.z + Math.cos(a * .8) * .8); b.rotation.y = -a; const f = Math.sin(t * 14 + u.ph) * .9; u.L.rotation.y = f; u.Rw.rotation.y = -f; } };
}

// ———— 柔光（光晕）：把画面里亮的地方挑出来、缩小、模糊两遍，再加回去（亮窗、灯、篝火、太阳边会晕开） ————
export function makeBloom(renderer) {
  const size = new THREE.Vector2(); renderer.getDrawingBufferSize(size);
  const mk = (w, h) => new THREE.WebGLRenderTarget(w, h, { type: THREE.HalfFloatType });
  let full = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: 4 });
  let a = mk(size.x >> 2, size.y >> 2), b = mk(size.x >> 2, size.y >> 2);
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
  const sc = new THREE.Scene(); sc.add(quad); const oc = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const vs = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }`;
  const bright = new THREE.ShaderMaterial({ uniforms: { tex: { value: null }, th: { value: 3.2 } }, vertexShader: vs,
    fragmentShader: `uniform sampler2D tex; uniform float th; varying vec2 vUv; void main(){ vec3 c = texture2D(tex, vUv).rgb; float l = max(c.r, max(c.g, c.b)); gl_FragColor = vec4(c * smoothstep(th, th * 1.6, l) * .5, 1.); }` });
  const blur = new THREE.ShaderMaterial({ uniforms: { tex: { value: null }, dir: { value: new THREE.Vector2() } }, vertexShader: vs,
    fragmentShader: `uniform sampler2D tex; uniform vec2 dir; varying vec2 vUv; void main(){ vec3 c = texture2D(tex, vUv).rgb * .227;
      c += (texture2D(tex, vUv + dir * 1.38).rgb + texture2D(tex, vUv - dir * 1.38).rgb) * .316;
      c += (texture2D(tex, vUv + dir * 3.23).rgb + texture2D(tex, vUv - dir * 3.23).rgb) * .07; gl_FragColor = vec4(c, 1.); }` });
  const comp = new THREE.ShaderMaterial({ uniforms: { base: { value: null }, glow: { value: null }, k: { value: .4 } }, vertexShader: vs,
    fragmentShader: `uniform sampler2D base, glow; uniform float k; varying vec2 vUv;
      void main(){ vec3 c = texture2D(base, vUv).rgb + texture2D(glow, vUv).rgb * k;
        vec2 d = vUv - .5; c *= 1. - dot(d, d) * .35;
        gl_FragColor = vec4(c, 1.);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`, toneMapped: true });
  const pass = (mat, target) => { quad.material = mat; renderer.setRenderTarget(target); renderer.render(sc, oc); };
  return {
    render(scene, camera) {
      const tm = renderer.toneMapping; renderer.toneMapping = THREE.NoToneMapping;
      renderer.setRenderTarget(full); renderer.render(scene, camera);
      bright.uniforms.tex.value = full.texture; pass(bright, a);
      for (let i = 0; i < 2; i++) {
        blur.uniforms.tex.value = a.texture; blur.uniforms.dir.value.set(1 / a.width, 0); pass(blur, b);
        blur.uniforms.tex.value = b.texture; blur.uniforms.dir.value.set(0, 1 / a.height); pass(blur, a);
      }
      renderer.toneMapping = tm;
      comp.uniforms.base.value = full.texture; comp.uniforms.glow.value = a.texture; pass(comp, null);
    },
    resize() { renderer.getDrawingBufferSize(size); full.setSize(size.x, size.y); a.setSize(size.x >> 2, size.y >> 2); b.setSize(size.x >> 2, size.y >> 2); },
  };
}

// ———— 柔光片：一张中间亮、往外化开的圆，叠加着画，永远朝着镜头 ————
export function halos(scene, spots) {
  const n = 128, c = document.createElement('canvas'); c.width = c.height = n;
  const g = c.getContext('2d'), gr = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2);
  gr.addColorStop(0, 'rgba(255,214,150,.9)'); gr.addColorStop(.25, 'rgba(255,190,120,.35)'); gr.addColorStop(1, 'rgba(255,180,110,0)');
  g.fillStyle = gr; g.fillRect(0, 0, n, n);
  const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: .55 });
  const grp = new THREE.Group();
  for (const [p, r] of spots) { if (r > .6) continue; const s = new THREE.Sprite(mat); s.position.copy(p); const k = Math.max(.35, r * 5); s.scale.set(k, k, 1); grp.add(s); }
  scene.add(grp); return grp;
}
