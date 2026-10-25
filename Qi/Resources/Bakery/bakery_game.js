// 甜品屋：经营一家小甜品店。
// 一天：开门前去集市进货、在厨房自己设计甜点（坯底 → 奶油 → 搅拌 → 烘烤 → 随便装饰）、摆进展示柜定价；
// 开门后客人进来，说一句含含糊糊的想要什么，可以点她推荐，也可以让她自己挑；买完有的会坐下来吃。
// 名气涨了解锁新食材、新坯底、新家具；常客好感够了会讲自己的事、送东西；每七天一次甜品大赛。
'use strict';
(() => {
  const $ = (s) => document.querySelector(s);
  const TAU = Math.PI * 2;
  const R = Math.random;
  const pick = (a) => a[(R() * a.length) | 0];
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const fmtClock = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.floor(m % 60)).padStart(2, '0')}`;
  const OPEN = 9 * 60, CLOSE = 18 * 60;
  const MIN_PER_SEC = 3.6;   // 一秒走游戏里 3.6 分钟：一天营业两分半

  // ———————————————— 存档 ————————————————
  function newGame() {
    return {
      v: 1, day: 1, money: 200, fame: 0, phase: 'prep', clock: 8 * 60 + 30,
      inv: { flour: 8, butter: 5, egg: 12, sugar: 8, milk: 5, cream: 6, strawberry: 6, cocoa: 3, blueberry: 4 },
      recipes: [], stock: {}, display: [null, null, null, null, null, null],
      decor: [{ id: 1, kind: 'table', x: 250, z: .55 }, { id: 2, kind: 'plant', x: 140, z: .15 }, { id: 3, kind: 'frame', x: 380, y: 64 }],
      owned: { decor: {}, wallpapers: ['cream'], floors: ['oak'] }, wallpaper: 'cream', floor: 'oak',
      up: { oven: 0, mixer: 0, case: 0, sign: 0, fridge: 0 },
      regulars: {}, clawdJob: 'greet', clean: 100, reviews: [],
      stats: { sold: 0, earned: 0, customers: 0 }, weather: 'sunny', prices: {}, unlockCreams: [], discounts: {},
      oven: [], nextId: 10, tut: 0, contestDay: 0, lastLv: 1, seen: {}, style: 'story',
    };
  }
  let S;
  try { S = window.BAKERY_SAVE || JSON.parse(localStorage.getItem('qi-bakery') || 'null'); } catch (e) { S = null; }
  const fresh = !S || S.v !== 1;
  if (fresh) S = newGame();
  if (!S.style) S.style = 'story';
  INK.setStyle(S.style);
  let saveT = 0;
  function save() {
    const j = JSON.stringify(S);
    try { localStorage.setItem('qi-bakery', j); } catch (e) {}
    window.webkit?.messageHandlers?.bake?.postMessage({ save: j });
  }

  // ———————————————— 推出来的数 ————————————————
  const level = () => { let l = 1; LEVELS.forEach((f, i) => { if (S.fame >= f) l = i + 1; }); return l; };
  const lvProgress = () => { const l = level(); if (l >= LEVELS.length) return 1; return (S.fame - LEVELS[l - 1]) / (LEVELS[l] - LEVELS[l - 1]); };
  const season = () => SEASONS[Math.floor((S.day - 1) / 7) % 4];
  const slots = () => UPGRADES.case.levels[S.up.case].slots;
  const batch = () => UPGRADES.oven.levels[S.up.oven].batch;
  const creamOK = (c) => CREAMS[c].lv <= level() || S.unlockCreams.includes(c);
  const recipeById = (id) => S.recipes.find((r) => r.id === id);
  const cozy = () => S.decor.reduce((a, d) => a + (DECOR[d.kind]?.cozy || 0), 0) + (S.wallpaper !== 'cream' ? 6 : 0) + (S.floor !== 'oak' ? 6 : 0);
  const priceOf = (k) => S.prices[k] ?? INGREDIENTS[k].price;
  const avgStars = () => { const rs = S.reviews.slice(-30); return rs.length ? rs.reduce((a, r) => a + r.stars, 0) / rs.length : 3.5; };

  // 新的一天：天气、集市价格、隔夜的甜点
  function rollDay(first) {
    const se = season();
    const ws = { spring: ['sunny', 'sunny', 'cloudy', 'rain'], summer: ['sunny', 'hot', 'hot', 'rain', 'cloudy'], autumn: ['sunny', 'cloudy', 'cloudy', 'rain'], winter: ['cloudy', 'snow', 'snow', 'sunny'] }[se];
    S.weather = first ? 'sunny' : pick(ws);
    S.prices = {};
    for (const [k, ing] of Object.entries(INGREDIENTS)) {
      let p = ing.price * (.85 + R() * .35);
      if (ing.season) p *= ing.season === se ? .8 : 1.3;
      if (S.discounts[k]) p *= .9;
      S.prices[k] = Math.max(1, Math.round(p * 2) / 2);
    }
    if (!first) {
      const keep = S.up.fridge > 0;
      // 展示柜和库存里剩下的：有冷藏柜照旧，没有就变成「隔夜」，隔两夜的扔掉
      const age = (e) => { if (!e) return e; e.age = (e.age || 0) + (keep ? 0 : 1); return e.age >= 2 ? null : e; };
      S.display = S.display.map((s) => (s ? age(s) : s)).map((s) => (s && s.n > 0 ? s : null));
      for (const id of Object.keys(S.stock)) { S.stock[id] = S.stock[id].map(age).filter((e) => e && e.n > 0); if (!S.stock[id].length) delete S.stock[id]; }
    }
  }

  // ———————————————— 一款甜点：要多少料、多少钱、什么口味、好不好看 ————————————————
  function needs(r, n = 1) {
    const out = {};
    const add = (k, v) => { out[k] = (out[k] || 0) + v; };
    // 坯底和奶油：一份料做 4 个
    for (const [k, v] of Object.entries(BASES[r.base].need)) add(k, Math.ceil(v * n / 4));
    for (const [k, v] of Object.entries(CREAMS[r.cream].need)) add(k, Math.ceil(v * n / 4));
    const counts = {};
    for (const it of r.items) counts[it.t] = (counts[it.t] || 0) + 1;
    for (const [t, c] of Object.entries(counts)) { const tp = TOPPINGS[t]; add(tp.uses, Math.ceil(c * n / tp.per)); }
    const rosettes = r.pipes.reduce((a, p) => a + p.pts.length, 0);
    if (rosettes) add('cream', Math.ceil(n * Math.min(1, rosettes / 24) / 4));
    for (const d of r.drizzle) add(d.c === '#c7894a' ? 'caramel' : 'cocoa', Math.ceil(n / 6));
    if (r.dust) add('sugar', Math.ceil(n / 8));
    return out;
  }
  const canMake = (r) => { const one = needs(r, 1); let n = 99; for (const [k, v] of Object.entries(one)) n = Math.min(n, Math.floor((S.inv[k] || 0) / v)); for (let m = Math.min(n + 2, batch()); m > 0; m--) { if (Object.entries(needs(r, m)).every(([k, v]) => (S.inv[k] || 0) >= v)) return m; } return 0; };
  const unitCost = (r) => { let c = 0; for (const [k, v] of Object.entries(needs(r, 24))) c += v * INGREDIENTS[k].price; return Math.round(c / 24 * 10) / 10; };
  function tagsOf(r) {
    const t = {};
    const add = (tags, k = 1) => { for (const [a, v] of Object.entries(tags)) t[a] = (t[a] || 0) + v * k; };
    add(BASES[r.base].tags); add(CREAMS[r.cream].tags);
    const counts = {};
    for (const it of r.items) counts[it.t] = (counts[it.t] || 0) + 1;
    for (const [tp, c] of Object.entries(counts)) add(INGREDIENTS[TOPPINGS[tp].uses].tags, Math.min(1.2, c / 3));
    for (const d of r.drizzle) add(d.c === '#c7894a' ? INGREDIENTS.caramel.tags : INGREDIENTS.cocoa.tags, .5);
    if (r.dust) add({ sweet: .3, classic: .2 });
    const hues = new Set(r.items.map((it) => TOPPINGS[it.t].hue));
    if (hues.size >= 3) add({ cute: .5 });
    return t;
  }
  function beautyOf(r) {
    const pts = [...r.items.map((i) => [i.u, i.v])];
    let ros = 0; for (const p of r.pipes) for (const q of p.pts) { pts.push(q); ros++; }
    const n = r.items.length;
    const fn = n === 0 ? .15 : Math.min(1, n / 6) * (n > 16 ? Math.max(.5, 1 - (n - 16) * .04) : 1);
    const hues = new Set(r.items.map((it) => TOPPINGS[it.t].hue)); r.pipes.forEach((p) => hues.add(p.c)); hues.add(r.cream);
    const fc = [0, .5, .8, 1, .95, .85, .75][Math.min(hues.size, 6)];
    const fp = ros ? Math.min(1, ros / 10) * .8 + .2 : 0;
    let cx = 0, cy = 0; pts.forEach(([u, v]) => { cx += u; cy += v; }); if (pts.length) { cx /= pts.length; cy /= pts.length; }
    const fb = pts.length ? 1 - Math.min(1, Math.hypot(cx, cy) * 1.4) : .3;
    let sp = 0; pts.forEach(([u, v]) => { sp += Math.hypot(u - cx, v - cy); }); sp = pts.length ? sp / pts.length : 0;
    const fs = pts.length > 2 ? 1 - Math.min(1, Math.abs(sp - .45) * 1.6) : .3;
    let extra = (r.dust ? .04 : 0) + Math.min(.1, r.drizzle.length * .05) + (r.items.some((i) => i.t === 'gold') ? .06 : 0);
    extra += { macaron: .05, crepe: .05, cookie: -.05 }[r.base] || 0;
    return Math.round(100 * clamp(.16 + .22 * fn + .2 * fc + .14 * fp + .14 * fb + .12 * fs + extra, 0, 1));
  }
  function pairsOf(r) {
    const used = new Set([...Object.keys(BASES[r.base].need), ...Object.keys(CREAMS[r.cream].need), ...r.items.map((i) => TOPPINGS[i.t].uses)]);
    r.drizzle.forEach((d) => used.add(d.c === '#c7894a' ? 'caramel' : 'cocoa'));
    return PAIRS.filter(([a, b]) => used.has(a) && used.has(b));
  }
  function finishRecipe(r) {
    r.tags = tagsOf(r); r.beauty = beautyOf(r);
    const pair = Math.min(15, pairsOf(r).reduce((a, p) => a + p[2], 0));
    r.taste = Math.round(clamp(r.mix * .4 + r.bake * .45 + pair + 5, 5, 100));
    r.cost = unitCost(r);
    return r;
  }
  const topTags = (t, n = 3) => Object.entries(t || {}).sort((a, b) => b[1] - a[1]).filter((e) => e[1] >= .6).slice(0, n).map((e) => e[0]);
  const suggestPrice = (r) => Math.max(Math.ceil(r.cost * 1.6), Math.round(BASES[r.base].value * (.7 + (r.taste + r.beauty) / 200 * .9)));

  // ———————————————— 画面 ————————————————
  const cv = $('#scene'), g = cv.getContext('2d');
  let W = 0, H = 0, DPR = 1, SC = 1, OY = 0, camX = 300, T = 0;
  function resize() {
    DPR = Math.min(2, devicePixelRatio || 1); W = innerWidth; H = innerHeight;
    cv.width = W * DPR; cv.height = H * DPR;
    SC = Math.max(H / 740, W / SCENE.WW); OY = H - SCENE.WH * SC + 6;
    camX = clamp(camX, 0, Math.max(0, SCENE.WW - W / SC));
    if (typeof clearCaches === 'function') clearCaches();
  }
  addEventListener('resize', resize);
  const toWorld = (px, py) => [px / SC + camX, (py - OY) / SC];
  const toScreen = (x, y) => [(x - camX) * SC, y * SC + OY];

  // 画面分层缓存（新画法每一笔都有晕染和纸纹，每帧全画一遍手机会烫）：
  //   bg   墙、窗框窗帘、藤蔓、架子、地板地毯、墙上的家具、吊灯（窗玻璃是空的，后面每帧画天）
  //   mid  展示柜（里面的甜点）、柜台正面、黑板——卖掉一个才重画
  //   小图 人、clawd、她、地上的家具：按样子和动作帧各画一次，之后直接贴
  const layer = () => document.createElement('canvas');
  let bgCv = layer(), midCv = layer(), bgKey = '', midKey = '', bgDirty = true;
  const sprites = new Map();
  function clearCaches() { bgKey = ''; midKey = ''; sprites.clear(); }
  function sceneLayer(cv, draw) {
    const k = Math.min(3, SC * DPR);
    cv.width = Math.ceil(SCENE.WW * k); cv.height = Math.ceil(SCENE.WH * k);
    const x = cv.getContext('2d'); x.setTransform(k, 0, 0, k, 0, 0); x.clearRect(0, 0, SCENE.WW, SCENE.WH);
    draw(x);
  }
  // 一张小图：w×h 的范围，原点在 (ox, oy)（脚底那一点），画好以后贴到场景里
  function sprite(key, w, h, ox, oy, draw) {
    let c = sprites.get(key); if (c) return c;
    const k = Math.min(3, SC * DPR);
    c = layer(); c.width = Math.ceil(w * k); c.height = Math.ceil(h * k);
    const x = c.getContext('2d'); x.setTransform(k, 0, 0, k, ox * k, oy * k); draw(x);
    c.ow = w; c.oh = h; c.ox = ox; c.oy = oy;
    sprites.set(key, c); if (sprites.size > 500) sprites.delete(sprites.keys().next().value);
    return c;
  }
  const blit = (c, x, y) => g.drawImage(c, x - c.ox, y - c.oy, c.ow, c.oh);
  function drawLayers(clock) {
    const lit = Math.round(Math.max(.35, Math.min(1, (clock / 60 - 15) / 3)) * 10);
    const wallDecor = S.decor.filter((d) => DECOR[d.kind]?.place === 'wall').map((d) => d.kind + d.x.toFixed(0) + d.y.toFixed(0) + (decorSel === d ? '*' : '')).join(',');
    const bk = [S.style, S.wallpaper, S.floor, wallDecor, lit, SC, S.recipes[0]?.id, S.phase === 'closed'].join('|');
    if (bk !== bgKey || bgDirty) {
      bgKey = bk; bgDirty = false;
      sceneLayer(bgCv, (x) => {
        SCENE.background(x, S);
        SCENE.lights(x, clock);
        for (const d of S.decor) if (DECOR[d.kind]?.place === 'wall') SCENE.decorItem(x, d, 0, clock, decorSel === d);
        SCENE.counterBack(x);
      });
    }
    const menu = S.display.filter((s) => s && s.n > 0).map((s) => ({ name: recipeById(s.rid)?.name || '', price: s.price }));
    const mk = [S.style, SC, JSON.stringify(S.display), S.recipes.length, S.recipes[1]?.id].join('|');
    if (mk !== midKey) {
      midKey = mk;
      const byId = {}; S.recipes.forEach((r) => (byId[r.id] = r));
      sceneLayer(midCv, (x) => {
        SCENE.chalkboard(x, menu.filter((m, i) => menu.findIndex((q) => q.name === m.name) === i));
        SCENE.displayCase(x, S.display, byId);
        SCENE.counterFront(x, S.recipes);
      });
    }
  }
  // 人：动作切成 8 帧，每个人每帧画一次
  const PH = 8;
  function personSprite(look, type, k, mood, walk, phase, eating) {
    const kq = Math.round(k * 20) / 20;
    return sprite(['p', look.id, type, kq, mood, walk ? phase : '-', eating ? 1 : 0].join(':'), 90 * kq, 150 * kq, 45 * kq, 140 * kq, (x) => PEOPLE.person(x, look, 0, 0, kq, { t: walk ? phase / PH * TAU / 9 : 0, walk, mood, facing: 1, eating, type }));
  }
  // ———————————————— 店里的人 ————————————————
  const people = [];   // 客人
  const floats = [];   // 飘起来的字
  const crumbs = [];
  const clawd = { x: 160, z: .7, tx: 160, tz: .7, walk: false, facing: 1, say: null, sayT: 0, mood: 'idle' };
  let doorOpen = 0;
  const seatsTaken = new Set();

  let lookSeq = 1;
  function lookFor(type, reg) {
    const L = CUSTOMER_TYPES[type].look;
    const look = { hair: reg?.hair || pick(L.hair), top: reg?.top || pick(L.top), bottom: pick(L.bottom), skin: pick(['#f6dccd', '#f3d3c2', '#eac3ad']) };
    look.style = { student: pick(['pony', 'long', 'short']), office: pick(['short', 'short', 'long']), granny: 'bun', couple: 'long', kid: pick(['pony', 'short']), athlete: 'pony', critic: 'short' }[type];
    if (type === 'office' && R() < .4) look.glasses = true;
    if (type === 'granny' || type === 'critic') look.glasses = true;
    if (type === 'kid') look.bow = pick(['#f08ea0', '#a9c1d9', '#f1dca0']);
    if (type === 'athlete' && R() < .5) look.cap = '#a9c9b6';
    if (type === 'critic') look.beret = '#8a5a6a';
    if (['office', 'athlete', 'critic'].includes(type)) look.pants = true;
    if (type === 'kid' && R() < .5) look.style = 'bob';
    look.type = type; look.id = (lookSeq++).toString(36);
    return look;
  }
  function spawn() {
    const lv = level();
    const types = Object.keys(CUSTOMER_TYPES).filter((t) => (CUSTOMER_TYPES[t].minLv || 1) <= lv && (t !== 'critic' || R() < .25));
    // 家具会多招来喜欢它的那类客人
    const w = types.map((t) => 1 + S.decor.filter((d) => DECOR[d.kind]?.likes === t).length * .35);
    let x = R() * w.reduce((a, b) => a + b, 0), type = types[0];
    for (let i = 0; i < types.length; i++) { x -= w[i]; if (x <= 0) { type = types[i]; break; } }
    const ct = CUSTOMER_TYPES[type];
    // 常客
    let reg = null;
    const cand = REGULARS.filter((r) => r.type === type && !people.some((p) => p.reg?.id === r.id));
    if (cand.length && R() < .4) reg = pick(cand);
    const p = {
      id: Math.random(), type, reg, look: lookFor(type, reg), x: 68, z: .32, state: 'enter', t: 0,
      budget: ct.budget[0] + R() * (ct.budget[1] - ct.budget[0]), line: pick(ct.lines), mood: 'idle', facing: 1,
      tx: 470 + R() * 160, tz: .5 + R() * .14, browse: 4.5 + R() * 4 + (ct.patience - 20) * .08, recommended: false, kid: type === 'kid',
    };
    if (type === 'couple') p.partner = lookFor('couple');
    people.push(p);
    doorOpen = 1; S.stats.customers++;
  }
  // 她对一块甜点打几分
  function appraise(p, slot) {
    const r = recipeById(slot.rid); if (!r) return null;
    const ct = CUSTOMER_TYPES[p.type];
    let like = 0;
    for (const [t, w] of Object.entries(ct.likes)) like += (r.tags[t] || 0) * w;
    for (const [t, w] of Object.entries(ct.dislikes)) like -= (r.tags[t] || 0) * w;
    like = clamp(like / 2.2, -1.5, 1.6);
    let q = (r.taste * .6 + r.beauty * .4) / 100;
    if (ct.pretty) q = (r.taste * .4 + r.beauty * .6) / 100;
    if (ct.strict) q = Math.min(r.taste, r.beauty) / 100;
    if (slot.age) q -= .12;
    const value = BASES[r.base].value * (.6 + q * .9) * (1 + Math.max(0, like) * .2) + r.items.length * .5;
    const util = like * 10 + q * 20 + (value - slot.price) * .8;
    return { r, like, q, value, util, affordable: slot.price <= p.budget * (like > .8 ? 1.15 : 1) };
  }
  function bestFor(p) {
    let best = null, bi = -1;
    S.display.forEach((s, i) => { if (!s || s.n <= 0) return; const a = appraise(p, s); if (!a || !a.affordable) return; if (!best || a.util > best.util) { best = a; bi = i; } });
    return best && best.util > 4 ? { ...best, slot: bi } : null;
  }
  function buy(p, choice, recommended) {
    const s = S.display[choice.slot]; if (!s || s.n <= 0) return false;
    s.n--; p.bought = { slot: { ...s }, a: choice, price: s.price, recommended };
    if (s.n <= 0) S.display[choice.slot] = null;
    p.state = 'toCounter'; p.mood = 'happy';
    return true;
  }
  function settle(p) {
    const b = p.bought, a = b.a, ct = CUSTOMER_TYPES[p.type];
    let stars = 2.3 + a.like * .8 + a.q * 2 + clamp((a.value - b.price) / a.value, -1, .6) * 1.2;
    stars += Math.min(.4, cozy() / 120);
    if (S.clean < 55) stars -= .5;
    if (b.recommended) stars += .4;
    if (ct.strict) stars = 1 + a.q * 4.2 - Math.max(0, b.price - a.value) / 20;
    stars = clamp(Math.round(stars * 2) / 2, 1, 5);
    const tip = stars >= 4.5 ? Math.round(b.price * (b.recommended ? .3 : .15)) : 0;
    const earn = b.price + tip;
    S.money += earn; S.stats.sold++; S.stats.earned += earn; today.income += b.price; today.tips += tip; today.sold++;
    const r = recipeById(b.slot.rid); if (r) { r.sold = (r.sold || 0) + 1; r.starSum = (r.starSum || 0) + stars; }
    let fame = stars >= 3 ? (stars - 2.5) * 2 : -1;
    if (ct.strict) fame *= 4;
    if (S.decor.some((d) => DECOR[d.kind]?.likes === p.type)) fame += .5;
    gainFame(fame);
    S.clean = Math.max(0, S.clean - 1.6);
    const who = p.reg ? p.reg.name : ct.name;
    const text = reviewText(p, r, stars, b);
    S.reviews.push({ day: S.day, who, stars, text }); if (S.reviews.length > 60) S.reviews.shift();
    today.reviews.push({ who, stars, text }); today.starSum += stars;
    const [sx, sy] = [SCENE.COUNTER.x + 30, SCENE.floorY(.5) - 120];
    floats.push({ x: sx, y: sy, text: '+¥' + earn, col: '#c8504f', t: 0 });
    floats.push({ x: p.x, y: SCENE.floorY(p.z) - 120, text: '★'.repeat(Math.round(stars)), col: '#c8a96c', t: -.2 });
    // 常客好感
    if (p.reg && stars >= 4) {
      const st = S.regulars[p.reg.id] || (S.regulars[p.reg.id] = { aff: 0, story: 0 });
      st.aff += b.recommended ? 2 : 1;
      const th = [3, 7, 12];
      if (st.story < 3 && st.aff >= th[st.story]) { pendingStories.push(p.reg); }
    }
    if (!S.seen[p.type]) { S.seen[p.type] = 1; }
    // 吃完再走：有空座位一半的人坐下来
    const free = SCENE.seats(S.decor).filter((s) => !seatsTaken.has(s.decor.id + ':' + s.side));
    if (free.length && R() < .55) { const s = pick(free); seatsTaken.add(s.decor.id + ':' + s.side); p.seat = s; p.state = 'toSeat'; p.tx = s.x; p.tz = s.z + .02; }
    else { p.state = 'leave'; p.tx = 68; p.tz = .32; }
    if (S.tut === 3) setTut(4);
  }
  function reviewText(p, r, stars, b) {
    const name = r ? r.name : '甜点', tag = r ? topTags(r.tags, 1)[0] : null;
    if (stars >= 4.5) return pick([`「${name}」也太好吃了吧！` + (tag ? `${TAG_NAMES[tag]}得刚刚好。` : ''), `店里好温馨，${name}拍照超好看。`, b.recommended ? '老板推荐的果然没错！' : `下次还来买${name}。`]);
    if (stars >= 3.5) return pick([`${name}挺不错的。`, `味道可以，环境也舒服。`, `${name}好吃，就是想再多一点点${tag ? TAG_NAMES[tag] : '惊喜'}。`]);
    if (stars >= 2.5) return pick(['还行吧，普普通通。', `${name}有点贵了。`, '不太是我喜欢的口味。']);
    return pick(['不太合口味……', S.clean < 55 ? '店里有点乱。' : `${name}不值这个价。`, '有点失望。']);
  }
  function gainFame(f) {
    const before = level();
    S.fame = Math.max(0, S.fame + f);
    if (level() > before) levelUp(level());
  }

  // ———————————————— 一天在走 ————————————————
  let speed = 1, spawnAcc = 0, today = null, pendingStories = [];
  // 今天的流水跟存档一起存（中途退出、回来再结算也对）
  const resetToday = () => { today = S.today = { income: 0, tips: 0, sold: 0, starSum: 0, reviews: [], spent: 0, made: 0 }; };
  if (S.today) today = S.today; else resetToday();
  function rate() {
    const h = S.clock / 60;
    const curve = .55 + .55 * Math.exp(-((h - 10.5) ** 2) / 1.5) + .75 * Math.exp(-((h - 15) ** 2) / 2);
    const sign = [1, 1.1, 1.25][S.up.sign];
    return .05 * curve * (1 + .09 * (level() - 1)) * WEATHERS[S.weather].traffic * sign * (1 + cozy() / 140) * (S.clawdJob === 'greet' ? 1.2 : 1) * (.7 + avgStars() / 5 * .55);
  }
  function tick(dt) {
    const dm = dt * MIN_PER_SEC * speed;
    S.clock = Math.min(CLOSE, S.clock + dm);   // 到六点钟停住，等店里的客人走完再打烊
    // 烤箱
    for (const o of S.oven) if (!o.done && S.clock >= o.at) { o.done = true; addStock(o.rid, o.n, 0); toast(`「${recipeById(o.rid)?.name || '甜点'}」出炉了 ×${o.n}`); }
    S.oven = S.oven.filter((o) => !o.done);
    if (S.clock < CLOSE - 20) { spawnAcc += dm * rate(); while (spawnAcc >= 1 && people.length < 9) { spawnAcc -= 1; spawn(); } }
    if (S.clawdJob === 'clean') S.clean = Math.min(100, S.clean + dt * speed * .6);
    if (S.clock >= CLOSE && !people.length) closeShop();
  }
  // 人走路、做决定（真实时间，跟营业速度一起快）
  function moveTo(o, dt, v) {
    const dx = o.tx - o.x, dz = (o.tz - o.z) * 300, d = Math.hypot(dx, dz);
    if (d < 2) { o.x = o.tx; o.z = o.tz; o.walk = false; return true; }
    const s = Math.min(d, v * dt);
    o.x += dx / d * s; o.z += dz / d * s / 300; o.walk = true; if (Math.abs(dx) > 1) o.facing = dx > 0 ? 1 : -1;
    return false;
  }
  function updatePeople(dt) {
    const sp = dt * speed;
    const queue = people.filter((p) => p.state === 'toCounter' || p.state === 'pay');
    for (const p of people) {
      p.t += sp;
      if (p.state === 'enter') { if (moveTo(p, sp, 62)) { p.state = 'browse'; p.t = 0; p.mood = 'think'; p.facing = 1; } }
      else if (p.state === 'browse') {
        const lim = S.clock >= CLOSE ? 0 : p.browse * (S.clawdJob === 'cashier' ? 1.3 : 1);   // 打烊了：赶紧挑
        if (p.t > lim) {
          const c = bestFor(p);
          if (c) buy(p, c, false);
          else { p.mood = 'sad'; p.state = 'leave'; p.tx = 68; p.tz = .32; today.lost = (today.lost || 0) + 1; gainFame(-.5); floats.push({ x: p.x, y: SCENE.floorY(p.z) - 120, text: S.display.some((s) => s && s.n > 0) ? '没有想要的…' : '柜子空了…', col: '#8a7466', t: 0 }); if (!S.display.some((s) => s && s.n > 0) && !today.emptyTold) { today.emptyTold = true; toast('展示柜卖空了：去「配方簿」再做一炉吧'); } }
        }
      } else if (p.state === 'toCounter') {
        const i = queue.indexOf(p); p.tx = SCENE.COUNTER.x + 20 - i * 30; p.tz = .5 + i * .04;
        if (moveTo(p, sp, 62) && i === 0) { p.state = 'pay'; p.t = 0; p.facing = 1; }
      } else if (p.state === 'pay') { if (p.t > (S.clawdJob === 'cashier' ? .7 : 1.6)) settle(p); }
      else if (p.state === 'toSeat') { if (moveTo(p, sp, 62)) { p.state = 'sit'; p.t = 0; p.facing = -p.seat.side; } }
      else if (p.state === 'sit') { if (p.t > 7 + R() * .02) { seatsTaken.delete(p.seat.decor.id + ':' + p.seat.side); p.state = 'leave'; p.tx = 68; p.tz = .32; if (S.clean > 0 && R() < .6) crumbs.push({ x: p.x + (R() - .5) * 30, z: p.z + (R() - .3) * .1 }); } }
      else if (p.state === 'leave') { if (moveTo(p, sp, 70)) { p.gone = true; doorOpen = 1; } }
    }
    for (let i = people.length - 1; i >= 0; i--) if (people[i].gone) people.splice(i, 1);
    // clawd 按派的活走动
    clawd.sayT -= dt;
    const job = S.clawdJob;
    if (job === 'greet') { if (!clawd.walk && R() < .01) { clawd.tx = 120 + R() * 60; clawd.tz = .62 + R() * .2; } }
    else if (job === 'cashier') { clawd.tx = SCENE.COUNTER.x - 34; clawd.tz = .34; }
    else if (job === 'clean') { if (!clawd.walk && R() < .03) { const c = crumbs[0]; clawd.tx = c ? c.x : 140 + R() * 300; clawd.tz = c ? c.z : .4 + R() * .5; } if (crumbs.length && Math.hypot(crumbs[0].x - clawd.x, (crumbs[0].z - clawd.z) * 300) < 8) crumbs.shift(); }
    else if (job === 'taste') { clawd.tx = 600; clawd.tz = .28; }
    moveTo(clawd, sp, 50);
    if (!clawd.walk && job === 'cashier') clawd.facing = -1;
    if (S.clean < 60 && crumbs.length < 10 && R() < .002 * speed) crumbs.push({ x: 140 + R() * 420, z: .35 + R() * .6 });
    doorOpen = Math.max(0, doorOpen - dt * 1.4);
  }

  // ———————————————— 画店里 ————————————————
  function bubble(x, y, text, opts = {}) {
    g.font = '600 11.5px "PingFang SC", sans-serif';
    const lines = []; let line = '';
    for (const ch of text) { if (g.measureText(line + ch).width > 118) { lines.push(line); line = ch; } else line += ch; }
    if (line) lines.push(line);
    const w = Math.max(...lines.map((l) => g.measureText(l).width)) + 20, h = lines.length * 15 + 12;
    // 跟这一帧已经画了的气泡叠住就往上挪（尾巴拉长一点，还指着原来那个人）
    let by = y - h - 8; const tail = y;
    for (let k = 0; k < 6; k++) { const hit = bubbleRects.find((b) => x - w / 2 < b.x + b.w && x + w / 2 > b.x && by < b.y + b.h + 4 && by + h + 4 > b.y); if (!hit) break; by = hit.y - h - 6; }
    bubbleRects.push({ x: x - w / 2, y: by, w, h });
    if (tail - (by + h) > 12) { g.strokeStyle = opts.bg || '#fffdf9'; g.lineWidth = 2; g.beginPath(); g.moveTo(x, by + h); g.lineTo(x, tail - 6); g.stroke(); }
    y = by + h + 8;
    g.save(); g.translate(x - w / 2, y - h - 8);
    g.shadowColor = 'rgba(90,60,40,.15)'; g.shadowBlur = 8; g.shadowOffsetY = 2;
    g.fillStyle = opts.bg || '#fffdf9'; ART.rr(g, 0, 0, w, h, 12); g.fill(); g.shadowColor = 'transparent';
    g.beginPath(); g.moveTo(w / 2 - 6, h - 1); g.lineTo(w / 2, h + 7); g.lineTo(w / 2 + 6, h - 1); g.fill();
    g.fillStyle = opts.col || '#4a3a33'; g.textAlign = 'center';
    lines.forEach((l, i) => g.fillText(l, w / 2, 19 + i * 15));
    g.restore();
    return { x: x - w / 2, y: y - h - 8, w, h };
  }
  let hitBoxes = [], bubbleRects = [];
  function drawScene() {
    bubbleRects = [];
    const clock = S.phase === 'prep' ? 8 * 60 + 30 : S.clock;
    while (S.display.length < slots()) S.display.push(null);
    drawLayers(clock);
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    g.fillStyle = '#efe6da'; g.fillRect(0, 0, W, H);
    g.setTransform(DPR * SC, 0, 0, DPR * SC, -camX * SC * DPR, OY * DPR);
    // 屏幕比场景高的时候：上面是天花板，接一道石膏线
    if (OY > 0) { const cg = g.createLinearGradient(0, -OY / SC, 0, 0); cg.addColorStop(0, '#efe5d8'); cg.addColorStop(1, '#f6eee3'); g.fillStyle = cg; g.fillRect(0, -OY / SC - 2, SCENE.WW, OY / SC + 2); }
    SCENE.sky(g, clock, S.weather, T);   // 窗外的天在最底下，背景那一层窗玻璃是空的
    g.drawImage(bgCv, 0, 0, SCENE.WW, SCENE.WH);
    g.fillStyle = '#ece0cf'; g.fillRect(0, -10, SCENE.WW, 12); g.fillStyle = '#f8f1e7'; g.fillRect(0, -14, SCENE.WW, 5); g.fillStyle = 'rgba(120,90,60,.12)'; g.fillRect(0, 2, SCENE.WW, 4);
    blit(sprite('door:' + S.style + ':' + Math.round(doorOpen * 6), 140, 345, 0, 0, (x) => SCENE.door(x, Math.round(doorOpen * 6) / 6, 0)), 0, 0);
    // 她在柜台后面（忙的时候手一上一下：8 帧）
    const busy = S.oven.length > 0 || people.some((p) => p.state === 'pay');
    const bph = busy ? Math.floor(T * 10 / TAU * PH) % PH : 0;
    blit(sprite('baker:' + S.style + ':' + bph + ':' + busy, 80, 130, 40, 120, (x) => PEOPLE.baker(x, 0, 0, 1.05, busy ? bph / PH * TAU / 10 : 0, { busy })), SCENE.COUNTER.x + 52, SCENE.COUNTER.top + 6 - Math.sin(T * 2.2) * .8);
    g.drawImage(midCv, 0, 0, SCENE.WW, SCENE.WH);
    // 地上的面包屑
    g.fillStyle = 'rgba(200,160,110,.7)'; for (const c of crumbs) { ART.ellipse(g, c.x, SCENE.floorY(c.z), 2.2, 1.2); g.fill(); ART.ellipse(g, c.x + 4, SCENE.floorY(c.z) + 1, 1.5, .9); g.fill(); }
    // 地上的东西、人、clawd 按前后排
    const ents = [];
    for (const d of S.decor) if (DECOR[d.kind]?.place === 'floor') ents.push({ y: SCENE.floorY(d.z), f: () => drawFloorDecor(d, clock) });
    for (const p of people) ents.push({ y: SCENE.floorY(p.z) + (p.state === 'sit' ? -2 : 0), f: () => drawPerson(p) });
    ents.push({ y: SCENE.floorY(clawd.z), f: drawClawd });
    ents.sort((a, b) => a.y - b.y).forEach((e) => e.f());
    // 气泡和飘字（最上层）
    hitBoxes = [];
    for (const p of people) {
      const k = SCENE.depthK(p.z) * (p.kid ? .78 : 1), top = SCENE.floorY(p.z) - 108 * k;
      if (p.state === 'browse') {
        const b = bubble(p.x, top, p.line);
        // 等太久了：气泡边上一圈慢慢变短
        const left = 1 - p.t / (p.browse * (S.clawdJob === 'cashier' ? 1.3 : 1));
        g.strokeStyle = left < .35 ? '#d0606f' : '#c8a96c'; g.lineWidth = 2; g.beginPath(); g.arc(b.x + b.w - 2, b.y + 2, 6, -Math.PI / 2, -Math.PI / 2 + TAU * left); g.stroke();
        hitBoxes.push({ kind: 'cust', p, x: b.x, y: b.y, w: b.w, h: b.h + 110 * k });
      } else hitBoxes.push({ kind: 'cust', p, x: p.x - 20 * k, y: top + 10, w: 40 * k, h: 100 * k });
      if (p.state === 'sit') { g.font = '13px sans-serif'; g.textAlign = 'center'; g.fillStyle = '#c98b94'; g.fillText(Math.sin(T * 3 + p.id * 9) > 0 ? '♪' : '', p.x + 14, top + 6); }
    }
    hitBoxes.push({ kind: 'clawd', x: clawd.x - 26, y: SCENE.floorY(clawd.z) - 60, w: 52, h: 62 });
    if (clawd.say && clawd.sayT > 0) bubble(clawd.x, SCENE.floorY(clawd.z) - 66, clawd.say, { bg: '#fff4ee' });
    SCENE.caseSlots(slots()).forEach((sp, i) => hitBoxes.push({ kind: 'slot', i, x: sp.x - sp.w / 2, y: sp.y - 40, w: sp.w, h: 52 }));
    for (const f of floats) {
      if (f.t < 0) continue;
      // 飘起来的字垫一层底，压在气泡上也看得清
      g.globalAlpha = clamp(1 - f.t / 1.6, 0, 1); g.font = '700 12.5px "PingFang SC", sans-serif'; g.textAlign = 'center';
      const fw = g.measureText(f.text).width + 14, fy = f.y - f.t * 26;
      g.fillStyle = 'rgba(255,253,249,.92)'; ART.rr(g, f.x - fw / 2, fy - 13, fw, 19, 9.5); g.fill();
      g.fillStyle = f.col; g.fillText(f.text, f.x, fy + 1); g.globalAlpha = 1;
    }
    // 关门后一层暮色
    if (S.phase === 'closed') { g.fillStyle = 'rgba(60,40,70,.18)'; g.fillRect(0, -OY / SC - 2, SCENE.WW, SCENE.WH + OY / SC + 2); }
  }
  function drawFloorDecor(d, clock) {
    const def = DECOR[d.kind], k = SCENE.depthK(d.z), y = SCENE.floorY(d.z);
    if (decorSel === d || d.kind === 'garland') return SCENE.decorItem(g, d, T, clock, decorSel === d);   // 正在拖的那一件直接画
    const kq = Math.round(k * 20) / 20, w = def.w * 2.2 * kq, h = (SCENE.DECOR_H[d.kind] || 90) * 1.3 * kq;
    blit(sprite(['d', S.style, d.kind, kq, d.kind === 'flowerpot' ? Math.round(d.x) : 0].join(':'), w, h + 12, w / 2, h, (x) => { x.fillStyle = 'rgba(80,55,40,.2)'; x.beginPath(); x.ellipse(0, 0, def.w * .55 * kq, 7 * kq, 0, 0, TAU); x.fill(); SCENE.DRAW[d.kind](x, 0, 0, kq, clock); }), d.x, y);
  }
  function drawPerson(p) {
    const k = SCENE.depthK(p.z) * (p.kid ? .78 : 1), y = SCENE.floorY(p.z);
    const sitting = p.state === 'sit';
    const phase = p.walk ? Math.floor((T + p.id * 10) * 9 / TAU * PH) % PH : 0;
    const eating = sitting && Math.sin(T * 2 + p.id * 7) > .3;
    const bob = p.walk ? 0 : Math.sin((T + p.id * 10) * 2) * .6 * k;
    const draw = (look, x, yy, kk) => {
      const c = personSprite(look, p.type, kk, p.mood, p.walk, phase, eating);
      g.save(); g.translate(x, yy - bob); g.scale(p.facing, 1); blit(c, 0, 0); g.restore();
    };
    draw(p.look, p.x, y - (sitting ? 16 * k : 0), k);
    if (p.partner && !sitting) draw(p.partner, p.x - 24 * p.facing * k, y + 4, k * .97);
    if (p.reg && p.state !== 'leave') { g.fillStyle = '#d98a9a'; g.font = '600 10px "PingFang SC", sans-serif'; g.textAlign = 'center'; g.fillText('♥ ' + p.reg.name, p.x, y + 12); }
  }
  function drawClawd() {
    const k = Math.round(.95 * SCENE.depthK(clawd.z) * 20) / 20, y = SCENE.floorY(clawd.z);
    const job = S.clawdJob, anim = clawd.walk || job === 'greet' || job === 'clean';
    const ph = anim ? Math.floor(T * 10 / TAU * PH) % PH : 0;
    const c = sprite(['c', S.style, k, job, clawd.walk ? 1 : 0, ph, clawd.mood].join(':'), 80 * k, 80 * k, 40 * k, 70 * k, (x) => PEOPLE.clawd(x, 0, 0, k, ph / PH * TAU / 10 * (job === 'greet' && !clawd.walk ? 1.25 : 1), { job, walk: clawd.walk, mood: clawd.mood }));
    const bob = clawd.walk ? 0 : Math.sin(T * 2.6) * .7 * k;
    g.save(); g.translate(clawd.x, y - bob); g.scale(clawd.facing, 1); blit(c, 0, 0); g.restore();
  }

  // ———————————————— 摸店里 ————————————————
  let down = null, decorSel = null, decorMode = false;
  cv.addEventListener('pointerdown', (e) => { down = { x: e.clientX, y: e.clientY, cx: camX, moved: false, t: performance.now() }; hidePop();
    if (decorMode) { const [wx, wy] = toWorld(e.clientX, e.clientY); const hit = hitDecor(wx, wy); if (hit) { decorSel = hit; down.decor = hit; down.ox = wx - hit.x; down.oy = hit.z != null ? wy - SCENE.floorY(hit.z) : wy - hit.y; renderDecorTray(); } }
  });
  cv.addEventListener('pointermove', (e) => {
    if (!down) return;
    const dx = e.clientX - down.x, dy = e.clientY - down.y;
    if (Math.hypot(dx, dy) > 6) down.moved = true;
    if (down.decor) {
      const [wx, wy] = toWorld(e.clientX, e.clientY), d = down.decor;
      if (DECOR[d.kind].place === 'floor') { d.x = wx - down.ox; d.z = (wy - down.oy - SCENE.FLOOR - 22) / 228; } else { d.x = wx - down.ox; d.y = wy - down.oy; }
      SCENE.clampDecor(d);
    } else if (down.moved) camX = clamp(down.cx - dx / SC, 0, Math.max(0, SCENE.WW - W / SC));
  });
  cv.addEventListener('pointerup', (e) => {
    if (!down) return;
    const was = down; down = null;
    if (was.decor) { save(); return; }
    if (was.moved) return;
    const [wx, wy] = toWorld(e.clientX, e.clientY);
    for (let i = hitBoxes.length - 1; i >= 0; i--) {
      const h = hitBoxes[i];
      if (wx >= h.x && wx <= h.x + h.w && wy >= h.y && wy <= h.y + h.h) {
        if (h.kind === 'cust') return custPop(h.p, e.clientX, e.clientY);
        if (h.kind === 'clawd') return clawdPop(e.clientX, e.clientY);
        if (h.kind === 'slot') return openSheet('shop', 'case', h.i);
      }
    }
    if (decorMode) { decorSel = null; renderDecorTray(); }
  });
  function hitDecor(wx, wy) {
    for (let i = S.decor.length - 1; i >= 0; i--) {
      const d = S.decor[i], def = DECOR[d.kind];
      if (def.place === 'floor') { const y = SCENE.floorY(d.z), k = SCENE.depthK(d.z); if (Math.abs(wx - d.x) < def.w * .6 * k && wy < y + 8 && wy > y - 90 * k) return d; }
      else if (Math.abs(wx - d.x) < def.w * .6 && Math.abs(wy - d.y) < 34) return d;
    }
    return null;
  }

  // ———————————————— 小卡片：客人、clawd ————————————————
  const pop = $('#pop');
  function placePop(x, y) { pop.style.display = 'block'; const w = 250, h = pop.offsetHeight; pop.style.left = clamp(x - w / 2, 10, W - w - 10) + 'px'; pop.style.top = clamp(y - h - 16, 60, H - h - 100) + 'px'; }
  function hidePop() { pop.style.display = 'none'; }
  function custPop(p, x, y) {
    const ct = CUSTOMER_TYPES[p.type];
    const reg = p.reg ? S.regulars[p.reg.id] : null;
    let html = `<div class="row"><div class="grow"><div class="t1">${p.reg ? p.reg.name : ct.name}</div><div class="who">${p.reg ? ct.name + ' · 好感 ' + '♥'.repeat(Math.min(5, Math.ceil((reg?.aff || 0) / 2.5))) : '第一次来'}</div></div></div>`;
    if (p.state === 'browse') {
      html += `<div class="say">「${p.line}」</div><div class="t3" style="margin-bottom:6px">推荐一样给${p.type === 'couple' ? '他们' : 'Ta'}：</div><div class="list">`;
      S.display.forEach((s, i) => { if (!s || s.n <= 0) return; const r = recipeById(s.rid); html += `<button data-i="${i}"><canvas width="72" height="56" style="width:36px;height:28px" data-r="${r.id}"></canvas><span class="grow"><span class="t1" style="font-size:13px">${r.name}</span><br><span class="t3">${topTags(r.tags).map((t) => TAG_NAMES[t]).join(' · ')}</span></span><span class="price">¥${s.price}</span></button>`; });
      html += '</div>';
      if (!S.display.some((s) => s && s.n > 0)) html += '<div class="t2">展示柜是空的。</div>';
    } else if (p.state === 'sit') html += `<div class="say">正在慢慢吃，看起来很满足。</div>`;
    else if (p.bought) html += `<div class="say">买了「${recipeById(p.bought.slot.rid)?.name || ''}」。</div>`;
    else html += `<div class="say">${p.mood === 'sad' ? '没找到想要的，走了。' : '刚进门，在看展示柜。'}</div>`;
    pop.innerHTML = html;
    pop.querySelectorAll('canvas[data-r]').forEach(thumb);
    pop.querySelectorAll('button[data-i]').forEach((b) => b.onclick = () => {
      const i = +b.dataset.i, s = S.display[i]; if (!s || p.state !== 'browse') return hidePop();
      const a = appraise(p, s);
      hidePop();
      if (a && a.affordable && a.util > -2) { buy(p, { ...a, slot: i }, true); floats.push({ x: p.x, y: SCENE.floorY(p.z) - 120, text: '就要这个！', col: '#c8504f', t: 0 }); }
      else { p.browse = Math.max(p.t + 1.5, p.browse * .75); p.line = a && !a.affordable ? pick(['有点贵了……', '超预算了诶……', '再看看别的吧。']) : pick(['嗯……不太想要这个。', '不是我想要的味道。', '还有别的吗？']); p.mood = 'think'; }
    });
    placePop(x, y);
  }
  const JOBS = { greet: ['招呼客人', '站门口挥手，客人多两成'], cashier: ['收银打包', '结账快一倍，客人更有耐心'], clean: ['打扫', '捡面包屑、擦桌子，店里一直干净'], taste: ['试吃', '在厨房帮忙，批量做的口感 +3'] };
  function clawdPop(x, y) {
    let html = `<div class="row"><div class="grow"><div class="t1">clawd</div><div class="who">店里的小帮手 · 给他派个活</div></div></div><div class="list" style="margin-top:8px">`;
    for (const [k, [n, d]] of Object.entries(JOBS)) html += `<button data-j="${k}" style="${S.clawdJob === k ? 'border-color:var(--rose)' : ''}"><span class="grow"><span class="t1" style="font-size:13px">${n}</span><br><span class="t3">${d}</span></span>${S.clawdJob === k ? '<span class="tag rose">在做</span>' : ''}</button>`;
    html += '</div>';
    pop.innerHTML = html;
    pop.querySelectorAll('button[data-j]').forEach((b) => b.onclick = () => { S.clawdJob = b.dataset.j; hidePop(); clawdSay({ greet: '欢迎光临～', cashier: '收钱交给我！', clean: '我来扫扫地。', taste: '我去厨房帮忙（偷吃）。' }[S.clawdJob]); save(); });
    placePop(x, y);
  }
  function clawdSay(t) { clawd.say = t; clawd.sayT = 2.6; }

  // ———————————————— 小缩略图 ————————————————
  function thumb(c) {
    const r = recipeById(c.dataset.r) || window.__draft; if (!r) return;
    const x = c.getContext('2d'), w = c.width, h = c.height;
    x.clearRect(0, 0, w, h);
    INK.dessert(x, r, w / 2, h * .82, Math.min(w * .78, h * 1.25));
  }

  // ———————————————— 顶上、底下 ————————————————
  const icons = { sunny: '☀', cloudy: '☁', rain: '☂', snow: '❄', hot: '☀' };
  function hud() {
    $('#dayChip').innerHTML = `<b>第 ${S.day} 天</b><span>${SEASON_NAMES[season()]} · ${icons[S.weather]} ${WEATHERS[S.weather].name}</span><span id="clock">${S.phase === 'prep' ? '开门前' : (S.phase === 'closed' ? '已打烊' : fmtClock(S.clock))}</span>`;
    $('#money').innerHTML = `<span class="y">¥</span>${Math.floor(S.money)}`;
    const lv = level(); $('#lvText').textContent = 'Lv' + lv;
    const rc = $('#lvRing').getContext('2d'); rc.clearRect(0, 0, 52, 52);
    rc.lineWidth = 5; rc.strokeStyle = 'rgba(120,90,70,.15)'; rc.beginPath(); rc.arc(26, 26, 20, 0, TAU); rc.stroke();
    rc.strokeStyle = '#d98a9a'; rc.lineCap = 'round'; rc.beginPath(); rc.arc(26, 26, 20, -Math.PI / 2, -Math.PI / 2 + TAU * lvProgress()); rc.stroke();
    rc.fillStyle = '#c8a96c'; rc.font = '600 15px sans-serif'; rc.textAlign = 'center'; rc.fillText('★', 26, 31);
  }
  let phaseKey = '';
  function phaseBar() {
    const key = S.phase + speed + (S.day % 7 === 0 && S.contestDay !== S.day) + (S.phase === 'prep' && S.display.some((s) => s && s.n > 0));
    if (key === phaseKey) return; phaseKey = key;
    const el = $('#phase');
    if (S.phase === 'prep') {
      el.innerHTML = (S.day % 7 === 0 && S.contestDay !== S.day ? '<button class="cta rose" id="pContest">甜品大赛</button>' : '') + '<button class="cta" id="pOpen">开门营业</button>';
      $('#pOpen').onclick = openShop;
      if ($('#pContest')) $('#pContest').onclick = () => openSheet('contest');
    } else if (S.phase === 'open') {
      el.innerHTML = `<button class="cta ghost" id="pSpeed">${speed === 1 ? '营业中 · 1 倍速' : '营业中 · 2 倍速'}</button>`;
      $('#pSpeed').onclick = () => { speed = speed === 1 ? 2 : 1; };
    } else el.innerHTML = '<button class="cta" id="pSum">今日结算</button>', $('#pSum').onclick = () => openSheet('summary');
  }
  async function openShop() {
    if (!S.display.some((s) => s && s.n > 0) && !(await ask('展示柜还是空的，客人进来什么也买不到。还是开门吗？', '开门'))) return;
    S.phase = 'open'; S.clock = OPEN; spawnAcc = .6; phaseKey = '';
    clawdSay('开门啦！'); if (S.tut === 2) setTut(3);
    save();
  }
  function closeShop() {
    S.phase = 'closed'; phaseKey = ''; seatsTaken.clear();
    save(); openSheet('summary');
  }
  // 确认框：App 里的网页不弹系统的 confirm，自己画一个
  function ask(text, yes = '确定', no = '取消') {
    return new Promise((ok) => {
      const m = document.createElement('div');
      m.style.cssText = 'position:fixed;inset:0;z-index:60;background:rgba(60,40,30,.25);display:grid;place-items:center;padding:30px';
      m.innerHTML = `<div class="card" style="max-width:300px;width:100%;margin:0;padding:18px;box-shadow:0 12px 40px rgba(90,60,40,.2)"><div class="t2" style="font-size:14px;color:var(--ink);line-height:1.6">${text}</div><div class="row" style="justify-content:flex-end;margin-top:14px;gap:8px"><button class="btn" data-a="0">${no}</button><button class="btn dark" data-a="1">${yes}</button></div></div>`;
      m.querySelectorAll('[data-a]').forEach((b) => b.onclick = () => { m.remove(); ok(b.dataset.a === '1'); });
      document.body.appendChild(m);
    });
  }
  let toastT;
  function toast(t) { const el = $('#toast'); el.textContent = t; el.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove('on'), 2200); }
  const TUTS = ['新店开张！先点下面的「厨房」，设计你的第一款甜点。', '做好了！点「店面」，把它摆进展示柜、定个价钱。', '展示柜有货了。准备好就点上面的「开门营业」。', '客人头上冒出要求时，点一下 Ta 可以推荐甜点；点 clawd 能给他派活。', ''];
  function setTut(n) { S.tut = n; showTut(); save(); }
  function showTut() { const t = TUTS[S.tut] || ''; $('#tip').style.display = t ? 'block' : 'none'; $('#tipText').textContent = t; }
  $('#tip').onclick = () => { if (S.tut >= 3) setTut(4); };

  document.querySelectorAll('#nav button').forEach((b) => b.onclick = () => {
    const tab = b.dataset.tab;
    if (tab === 'shop') { closeSheet(); setDecorMode(false); }
    else if (tab === 'kitchen') openKitchen();
    else openSheet(tab);
    navOn(tab);
  });
  function navOn(tab) { document.querySelectorAll('#nav button').forEach((x) => x.classList.toggle('on', x.dataset.tab === tab)); }
  $('#exit').onclick = () => { save(); window.webkit?.messageHandlers?.bake?.postMessage({ exit: true }); };
  $('#lvChip').onclick = () => openSheet('fame');

  // ———————————————— 面板 ————————————————
  const sheet = $('#sheet'), mask = $('#mask');
  let sheetKind = null, sheetTab = null, sheetArg = null;
  function openSheet(kind, tab, arg) {
    sheetKind = kind; sheetTab = tab || null; sheetArg = arg;
    renderSheet(); sheet.classList.add('open'); mask.classList.add('on'); hidePop();
    if (kind === 'decor') setDecorMode(true);
  }
  function closeSheet() {
    sheet.classList.remove('open'); mask.classList.remove('on'); sheetKind = null; navOn('shop');
    if (decorMode) setDecorMode(false);
    if (pendingStories.length) setTimeout(() => openSheet('story'), 300);
  }
  mask.onclick = closeSheet; $('#sClose').onclick = closeSheet;
  let camGoal = null;   // 镜头慢慢移过去
  function setDecorMode(on) { decorMode = on; if (!on) decorSel = null; if (on) camGoal = 40; mask.style.background = on ? 'transparent' : ''; mask.style.pointerEvents = on ? 'none' : ''; sheet.style.maxHeight = on ? '46%' : ''; }
  function tabs(list, cur, onPick) {
    const el = $('#sTabs'); el.innerHTML = list.map(([k, n]) => `<button data-k="${k}" class="${k === cur ? 'on' : ''}">${n}</button>`).join('');
    el.style.display = list.length ? 'flex' : 'none';
    el.querySelectorAll('button').forEach((b) => b.onclick = () => onPick(b.dataset.k));
  }
  function renderSheet() {
    const body = $('#sBody'); body.innerHTML = '';
    $('#sTabs').style.display = 'none';
    const f = { shop: sheetShop, market: sheetMarket, book: sheetBook, decor: sheetDecor, summary: sheetSummary, contest: sheetContest, fame: sheetFame, story: sheetStory, levelup: sheetLevelUp }[sheetKind];
    if (f) f(body);
    body.querySelectorAll('canvas[data-r]').forEach(thumb);
  }
  const H2 = (t, s = '') => { $('#sTitle').textContent = t; $('#sSub').textContent = s; };

  // 店面：展示柜、库存、烤箱、升级
  function sheetShop(body) {
    H2('展示柜', `${slots()} 格 · 点一格换甜点、改价钱`);
    tabs([['case', '展示柜'], ['stock', '库存'], ['up', '升级']], sheetTab || 'case', (k) => { sheetTab = k; renderSheet(); });
    const tab = sheetTab || 'case';
    if (tab === 'case') {
      if (sheetArg != null) return slotEditor(body, sheetArg);
      let html = '<div class="grid3">';
      for (let i = 0; i < slots(); i++) {
        const s = S.display[i], r = s ? recipeById(s.rid) : null;
        html += `<button class="pick" data-s="${i}">${r ? `<canvas width="140" height="100" style="width:70px;height:50px" data-r="${r.id}"></canvas><div class="t2" style="font-size:11px;color:var(--ink)">${r.name}</div><div class="t3">¥${s.price} · 剩 ${s.n}${s.age ? ' · 隔夜' : ''}</div>` : '<div style="height:50px;display:grid;place-items:center;color:var(--mute);font-size:22px">＋</div><div class="t3">空着</div>'}</button>`;
      }
      html += '</div>';
      if (!Object.keys(S.stock).length && !S.display.some((s) => s)) html += '<div class="empty">还没有做好的甜点。<br>去「厨房」设计一款，或者在「配方簿」里做一炉。</div>';
      body.innerHTML = html;
      body.querySelectorAll('[data-s]').forEach((b) => b.onclick = () => { sheetArg = +b.dataset.s; renderSheet(); });
    } else if (tab === 'stock') {
      const ids = Object.keys(S.stock);
      let html = S.oven.length ? `<div class="card"><div class="t1">烤箱里</div>${S.oven.map((o) => `<div class="t2">「${recipeById(o.rid)?.name}」×${o.n} · ${fmtClock(o.at)} 出炉</div>`).join('')}</div>` : '';
      if (!ids.length) html += '<div class="empty">库存是空的。</div>';
      for (const id of ids) { const r = recipeById(id); if (!r) continue; for (const e of S.stock[id]) html += `<div class="card row"><canvas width="120" height="90" style="width:60px;height:45px" data-r="${id}"></canvas><div class="grow"><div class="t1">${r.name}${e.age ? ' <span class="tag gold">隔夜</span>' : ''}</div><div class="t3">×${e.n} · 成本 ¥${r.cost}</div></div><button class="btn dark" data-put="${id}" data-age="${e.age || 0}">上架</button></div>`; }
      body.innerHTML = html;
      body.querySelectorAll('[data-put]').forEach((b) => b.onclick = () => { const i = S.display.findIndex((s) => !s); if (i < 0) return toast('展示柜满了，先撤下一格'); putOnShelf(b.dataset.put, i, +b.dataset.age); renderSheet(); });
    } else {
      let html = '';
      for (const [k, u] of Object.entries(UPGRADES)) {
        const cur = S.up[k], next = u.levels[cur + 1];
        html += `<div class="card"><div class="row"><div class="grow"><div class="t1">${u.name}</div><div class="t2">现在：${u.levels[cur].desc}</div>${next ? `<div class="t3">下一级：${next.desc}${next.lv > level() ? ` · Lv${next.lv} 解锁` : ''}</div>` : '<div class="t3">已经是最好的了</div>'}</div>${next ? `<button class="btn dark" data-up="${k}" ${next.lv > level() || S.money < next.price ? 'disabled' : ''}>¥${next.price}</button>` : ''}</div></div>`;
      }
      body.innerHTML = html;
      body.querySelectorAll('[data-up]').forEach((b) => b.onclick = () => { const k = b.dataset.up, nx = UPGRADES[k].levels[S.up[k] + 1]; S.money -= nx.price; S.up[k]++; toast(`${UPGRADES[k].name}升级了：${nx.desc}`); save(); renderSheet(); });
    }
  }
  function addStock(rid, n, age) { const l = S.stock[rid] || (S.stock[rid] = []); const e = l.find((x) => (x.age || 0) === age); if (e) e.n += n; else l.push({ n, age }); }
  function takeStock(rid, age) { const l = S.stock[rid]; if (!l) return 0; const i = l.findIndex((x) => (x.age || 0) === age); if (i < 0) return 0; const n = l[i].n; l.splice(i, 1); if (!l.length) delete S.stock[rid]; return n; }
  function putOnShelf(rid, i, age) {
    const r = recipeById(rid), cur = S.display[i];
    if (cur) addStock(cur.rid, cur.n, cur.age || 0);
    const n = takeStock(rid, age);
    const prev = S.display.find((s) => s && s.rid === rid);
    S.display[i] = { rid, n, price: r.price || suggestPrice(r), age };
    if (age) S.display[i].price = Math.max(1, Math.round((r.price || suggestPrice(r)) * .7));
    if (S.tut === 1) setTut(2);
    save();
  }
  function slotEditor(body, i) {
    const s = S.display[i];
    let html = `<button class="btn" id="back" style="margin-bottom:10px">‹ 全部格子</button>`;
    if (s) {
      const r = recipeById(s.rid);
      html += `<div class="card"><div class="row"><canvas width="160" height="120" style="width:80px;height:60px" data-r="${r.id}"></canvas><div class="grow"><div class="t1">${r.name}${s.age ? ' <span class="tag gold">隔夜</span>' : ''}</div><div class="t3">剩 ${s.n} 个 · 成本 ¥${r.cost} · 建议 ¥${suggestPrice(r)}</div><div>${topTags(r.tags).map((t) => `<span class="tag">${TAG_NAMES[t]}</span>`).join('')}</div></div></div><hr class="soft"><div class="row"><div class="grow t2">价钱</div><div class="step"><button data-d="-5">−5</button><button data-d="-1">−</button><span>¥${s.price}</span><button data-d="1">＋</button><button data-d="5">+5</button></div></div><div class="t3" style="margin-top:6px">${s.price > suggestPrice(r) * 1.4 ? '有点贵，挑剔的客人会犹豫。' : s.price < r.cost ? '比成本还便宜，卖一个亏一个。' : '价钱合适。'}</div><div class="row" style="margin-top:10px"><button class="btn" id="off">撤下来</button></div></div>`;
    }
    const ids = Object.keys(S.stock);
    html += `<div class="t1" style="margin:12px 2px 8px">${s ? '换成' : '摆上'}</div>`;
    if (!ids.length) html += '<div class="empty" style="padding:14px">库存里没有做好的甜点。</div>';
    for (const id of ids) { const r = recipeById(id); if (!r) continue; for (const e of S.stock[id]) html += `<div class="card row"><canvas width="120" height="90" style="width:60px;height:45px" data-r="${id}"></canvas><div class="grow"><div class="t1">${r.name}${e.age ? ' <span class="tag gold">隔夜</span>' : ''}</div><div class="t3">×${e.n}</div></div><button class="btn dark" data-put="${id}" data-age="${e.age || 0}">摆这里</button></div>`; }
    body.innerHTML = html;
    $('#back').onclick = () => { sheetArg = null; renderSheet(); };
    body.querySelectorAll('[data-d]').forEach((b) => b.onclick = () => { s.price = Math.max(1, s.price + +b.dataset.d); const r = recipeById(s.rid); r.price = s.price; save(); renderSheet(); });
    if ($('#off')) $('#off').onclick = () => { addStock(s.rid, s.n, s.age || 0); S.display[i] = null; save(); renderSheet(); };
    body.querySelectorAll('[data-put]').forEach((b) => b.onclick = () => { putOnShelf(b.dataset.put, i, +b.dataset.age); renderSheet(); });
  }

  // 集市
  let cart = {};
  function sheetMarket(body) {
    const se = season();
    H2('集市', `${SEASON_NAMES[se]}天 · 当季的便宜`);
    const lv = level();
    let html = '<div class="grid2">';
    for (const [k, ing] of Object.entries(INGREDIENTS)) {
      const locked = ing.lv > lv, p = priceOf(k), n = cart[k] || 0;
      html += `<div class="card" style="margin:0;padding:10px;${locked ? 'opacity:.45' : ''}"><div class="row"><canvas width="72" height="72" style="width:36px;height:36px;flex:none" data-ing="${k}"></canvas><div class="grow"><div class="t1" style="font-size:13px">${ing.name}${ing.season === se ? ' <span class="tag">当季</span>' : ''}</div><div class="t3">有 ${S.inv[k] || 0} · <span class="price" style="color:${p < ing.price ? '#5f7656' : p > ing.price ? '#a8505f' : 'inherit'}">¥${p}</span></div></div></div>${locked ? `<div class="t3" style="margin-top:6px">Lv${ing.lv} 解锁</div>` : `<div class="row" style="margin-top:8px;justify-content:flex-end"><div class="step"><button data-m="${k}" data-d="-1">−</button><span>${n}</span><button data-m="${k}" data-d="1">＋</button><button data-m="${k}" data-d="5" style="font-size:11px;width:34px">+5</button></div></div>`}</div>`;
    }
    html += '</div>';
    const total = Object.entries(cart).reduce((a, [k, n]) => a + n * priceOf(k), 0);
    html += `<div style="position:sticky;bottom:0;background:var(--paper);padding:10px 0 2px"><button class="cta" id="buy" style="width:100%" ${!total || total > S.money ? 'disabled' : ''}>${total ? `买下 · ¥${Math.round(total * 10) / 10}` : '挑点食材'}${total > S.money ? '（钱不够）' : ''}</button></div>`;
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-ing]').forEach((c) => ART.ingredient(c.getContext('2d'), c.dataset.ing, 36, 38, 52));
    body.querySelectorAll('[data-m]').forEach((b) => b.onclick = () => { const k = b.dataset.m; cart[k] = Math.max(0, (cart[k] || 0) + +b.dataset.d); renderSheet(); });
    $('#buy').onclick = () => {
      for (const [k, n] of Object.entries(cart)) { S.inv[k] = (S.inv[k] || 0) + n; S.money -= n * priceOf(k); today.spent += n * priceOf(k); }
      S.money = Math.round(S.money * 10) / 10; cart = {}; toast('买好了'); save(); renderSheet();
    };
  }

  // 配方簿
  function sheetBook(body) {
    H2('配方簿', `${S.recipes.length} 款 · 一炉最多 ${batch()} 个`);
    if (!S.recipes.length) { body.innerHTML = '<div class="empty">还没有配方。<br>去「厨房」设计第一款吧。</div>'; return; }
    let html = '';
    for (const r of S.recipes) {
      const n = canMake(r), rating = r.sold ? (r.starSum / r.sold).toFixed(1) : '—';
      html += `<div class="card"><div class="row"><canvas width="180" height="130" style="width:90px;height:65px" data-r="${r.id}"></canvas><div class="grow"><div class="t1">${r.name}</div><div>${topTags(r.tags).map((t) => `<span class="tag">${TAG_NAMES[t]}</span>`).join('')}</div><div class="t3" style="margin-top:4px">口感 ${r.taste} · 颜值 ${r.beauty} · 成本 ¥${r.cost}</div><div class="t3">卖出 ${r.sold || 0} · 评分 ${rating}</div></div></div><div class="row" style="margin-top:8px;justify-content:flex-end;gap:6px"><button class="btn" data-del="${r.id}">删掉</button><button class="btn" data-share="${r.id}">分享</button><button class="btn" data-edit="${r.id}">改装饰</button><button class="btn dark" data-make="${r.id}" ${n ? '' : 'disabled'}>${n ? `做一炉 ×${n}` : '料不够'}</button></div></div>`;
    }
    body.innerHTML = html;
    body.querySelectorAll('[data-make]').forEach((b) => b.onclick = () => makeBatch(recipeById(b.dataset.make)));
    body.querySelectorAll('[data-edit]').forEach((b) => b.onclick = () => { closeSheet(); openKitchen(recipeById(b.dataset.edit)); });
    body.querySelectorAll('[data-share]').forEach((b) => b.onclick = () => openPoster(recipeById(b.dataset.share)));
    body.querySelectorAll('[data-del]').forEach((b) => b.onclick = async () => { if (!(await ask('删掉这个配方？库存和展示柜里的也会一起清掉。', '删掉'))) return; const id = b.dataset.del; S.recipes = S.recipes.filter((r) => r.id !== id); delete S.stock[id]; S.display = S.display.map((s) => (s && s.rid === id ? null : s)); save(); renderSheet(); });
  }
  function makeBatch(r) {
    const n = canMake(r); if (!n) return;
    for (const [k, v] of Object.entries(needs(r, n))) S.inv[k] -= v;
    if (S.phase === 'open') { S.oven.push({ rid: r.id, n, at: S.clock + (S.up.oven >= 2 ? 22 : 32) }); toast(`进烤箱了，大约 ${S.up.oven >= 2 ? 22 : 32} 分钟后出炉`); }
    else { addStock(r.id, n, 0); toast(`做好了 ${n} 个「${r.name}」`); }
    today.made += n; save(); renderSheet();
  }

  // 装修
  function sheetDecor(body) {
    H2('装修', `氛围 ${cozy()} · 拖动店里的家具换位置`);
    tabs([['mine', '我的家具'], ['buy', '家具店'], ['wall', '墙纸'], ['floor', '地板'], ['style', '画风']], sheetTab || 'mine', (k) => { sheetTab = k; renderSheet(); });
    const tab = sheetTab || 'mine';
    const lv = level();
    if (tab === 'mine') return renderDecorTray();
    if (tab === 'style') return styleTab(body);
    let html = '';
    if (tab === 'buy') {
      html += '<div class="grid2">';
      for (const [k, d] of Object.entries(DECOR)) {
        if (d.gift) continue;
        html += `<div class="card" style="margin:0;padding:10px;${d.lv > lv ? 'opacity:.45' : ''}"><canvas width="160" height="120" style="width:80px;height:60px;display:block;margin:0 auto" data-decor="${k}"></canvas><div class="t1" style="font-size:13px;text-align:center">${d.name}</div><div class="t3" style="text-align:center">氛围 +${d.cozy} · ${d.place === 'floor' ? '放地上' : '挂墙上'} · 招${CUSTOMER_TYPES[d.likes]?.name || ''}</div><div style="text-align:center;margin-top:6px">${d.lv > lv ? `<span class="t3">Lv${d.lv} 解锁</span>` : `<button class="btn dark" data-buy="${k}" ${S.money < d.price ? 'disabled' : ''}>¥${d.price}</button>`}</div></div>`;
      }
      html += '</div>';
    } else {
      const src = tab === 'wall' ? WALLPAPERS : FLOORS, own = tab === 'wall' ? S.owned.wallpapers : S.owned.floors, cur = tab === 'wall' ? S.wallpaper : S.floor;
      html += '<div class="grid2">';
      for (const [k, w] of Object.entries(src)) html += `<div class="card" style="margin:0;padding:10px;${w.lv > lv ? 'opacity:.45' : ''}"><div style="height:46px;border-radius:10px;background:${w.kind === 'stripe' ? `repeating-linear-gradient(90deg,${w.a} 0 10px,${w.b} 10px 16px)` : w.kind === 'checker' ? `repeating-conic-gradient(${w.a} 0 25%, ${w.b} 0 50%) 0 0/16px 16px` : `radial-gradient(${w.b} 2px, ${w.a} 3px) 0 0/12px 12px`}"></div><div class="t1" style="font-size:13px;margin-top:6px">${w.name}</div><div style="margin-top:6px">${cur === k ? '<span class="tag rose">在用</span>' : own.includes(k) ? `<button class="btn" data-use="${k}">换上</button>` : w.lv > lv ? `<span class="t3">Lv${w.lv} 解锁</span>` : `<button class="btn dark" data-own="${k}" ${S.money < w.price ? 'disabled' : ''}>¥${w.price}</button>`}</div></div>`;
      html += '</div>';
    }
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-decor]').forEach((c) => { const x = c.getContext('2d'); x.scale(2, 2); const d = DECOR[c.dataset.decor]; SCENE.DRAW[c.dataset.decor](x, 40, d.place === 'floor' ? 56 : 30, d.place === 'floor' ? .6 : .7, 600); });
    body.querySelectorAll('[data-buy]').forEach((b) => b.onclick = () => { const k = b.dataset.buy, d = DECOR[k]; S.money -= d.price; S.owned.decor[k] = (S.owned.decor[k] || 0) + 1; toast(`买了${d.name}，在「我的家具」里摆出来`); save(); renderSheet(); });
    body.querySelectorAll('[data-own]').forEach((b) => b.onclick = () => { const k = b.dataset.own, src = tab === 'wall' ? WALLPAPERS : FLOORS; S.money -= src[k].price; (tab === 'wall' ? S.owned.wallpapers : S.owned.floors).push(k); if (tab === 'wall') S.wallpaper = k; else S.floor = k; bgDirty = true; save(); renderSheet(); });
    body.querySelectorAll('[data-use]').forEach((b) => b.onclick = () => { if (tab === 'wall') S.wallpaper = b.dataset.use; else S.floor = b.dataset.use; bgDirty = true; save(); renderSheet(); });
  }
  // 画风：整间店、人、甜点一起换
  const STYLE_LIST = [['story', '绘本水彩', '手绘线稿、水彩晕染、纸纹和闪光'], ['candy', '糖果厚描边', '粗描边、明亮色块、硬边阴影'], ['paper', '剪纸扁平', '几何色块、错开的纸片阴影、碎纸屑']];
  function styleTab(body) {
    body.innerHTML = '<div class="grid3">' + STYLE_LIST.map(([k, n, d]) => `<button class="pick ${S.style === k ? 'on' : ''}" data-style="${k}"><canvas width="180" height="150" style="width:90px;height:75px" data-sty="${k}"></canvas><div class="t1" style="font-size:12.5px">${n}</div><div class="t3" style="margin-top:2px;line-height:1.4">${d}</div></button>`).join('') + '</div>';
    const sample = S.recipes[0] || { base: 'sponge', cream: 'strawberry', seed: 4, dust: false, drizzle: [], pipes: [{ c: '#fbf5ea', pts: Array.from({ length: 30 }, (_, i) => [Math.cos(i / 30 * TAU) * .9, Math.sin(i / 30 * TAU) * .86]) }], items: [{ t: 'strawberry', u: 0, v: 0 }, { t: 'strawberry', u: .4, v: .1 }, { t: 'blueberry', u: -.35, v: .1 }, { t: 'mint', u: .1, v: -.5 }] };
    body.querySelectorAll('canvas[data-sty]').forEach((c) => { const keep = INK.style(); INK.setStyle(c.dataset.sty); INK.dessert(c.getContext('2d'), sample, 90, 128, 140); INK.setStyle(keep); });
    body.querySelectorAll('[data-style]').forEach((b) => b.onclick = () => { S.style = b.dataset.style; INK.setStyle(S.style); clearCaches(); save(); renderSheet(); });
  }
  function renderDecorTray() {
    if (sheetKind !== 'decor' || (sheetTab && sheetTab !== 'mine')) return;
    const body = $('#sBody');
    let html = '';
    if (decorSel) html += `<div class="card row"><div class="grow"><div class="t1">${DECOR[decorSel.kind].name}</div><div class="t3">在店里按住拖动换位置</div></div><button class="btn" id="stow">收起来</button></div>`;
    const spare = Object.entries(S.owned.decor).filter(([, n]) => n > 0);
    html += `<div class="t2" style="margin:2px 2px 8px">${spare.length ? '没摆出来的：' : '家具都摆出来了。去「家具店」买新的，或者在店里按住一件拖动它。'}</div><div class="grid3">`;
    for (const [k, n] of spare) html += `<button class="pick" data-place="${k}"><canvas width="120" height="90" style="width:60px;height:45px" data-decor="${k}"></canvas><div class="t3">${DECOR[k].name} ×${n}</div></button>`;
    html += '</div>';
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-decor]').forEach((c) => { const x = c.getContext('2d'); x.scale(2, 2); const d = DECOR[c.dataset.decor]; SCENE.DRAW[c.dataset.decor](x, 30, d.place === 'floor' ? 42 : 22, d.place === 'floor' ? .45 : .55, 600); });
    body.querySelectorAll('[data-place]').forEach((b) => b.onclick = () => {
      const k = b.dataset.place, def = DECOR[k];
      const d = SCENE.clampDecor({ id: S.nextId++, kind: k, x: camX + W / SC / 2, z: .5, y: 140 });
      if (def.place === 'wall') delete d.z;
      S.decor.push(d); S.owned.decor[k]--; decorSel = d; save(); renderDecorTray();
    });
    if ($('#stow')) $('#stow').onclick = () => { S.owned.decor[decorSel.kind] = (S.owned.decor[decorSel.kind] || 0) + 1; S.decor = S.decor.filter((d) => d !== decorSel); decorSel = null; save(); renderDecorTray(); };
  }

  // 结算
  function sheetSummary(body) {
    H2(`第 ${S.day} 天 · 打烊了`, `卖出 ${today.sold} 个甜点`);
    const avg = today.sold ? (today.starSum / today.sold).toFixed(1) : '—';
    const left = S.display.reduce((a, s) => a + (s ? s.n : 0), 0) + Object.values(S.stock).flat().reduce((a, e) => a + e.n, 0);
    let html = `<div class="card"><div class="grid2"><div><div class="t3">营业额</div><div class="t1" style="font-size:20px">¥${Math.round(today.income)}</div></div><div><div class="t3">小费</div><div class="t1" style="font-size:20px">¥${Math.round(today.tips)}</div></div><div><div class="t3">进货花了</div><div class="t1">¥${Math.round(today.spent)}</div></div><div><div class="t3">平均评分</div><div class="t1">${avg} <span class="stars">★</span></div></div></div>${today.lost ? `<div class="t3" style="margin-top:8px">${today.lost} 位客人没买到想要的就走了。</div>` : ''}</div>`;
    if (today.reviews.length) { html += '<div class="t1" style="margin:12px 2px 8px">今天的评价</div>'; for (const r of today.reviews.slice(-4).reverse()) html += `<div class="card"><div class="row"><div class="t1 grow" style="font-size:13px">${r.who}</div><span class="stars">${'★'.repeat(Math.round(r.stars))}</span></div><div class="t2">${r.text}</div></div>`; }
    if (left) html += `<div class="card"><div class="t1">还剩 ${left} 个没卖完</div><div class="t2">${S.up.fridge ? '放进冷藏柜，明天照常卖。' : '没有冷藏柜，明天会变成「隔夜」，便宜三成卖；再放一天就只能扔了。'}</div><div class="row" style="margin-top:8px"><button class="btn rose" id="gift">送给邻居（名气 +${Math.ceil(left / 2)}）</button></div></div>`;
    html += '<button class="cta" id="next" style="width:100%;margin-top:6px">下一天</button>';
    body.innerHTML = html;
    if ($('#gift')) $('#gift').onclick = () => { gainFame(Math.ceil(left / 2)); S.display = S.display.map(() => null); S.stock = {}; toast('邻居们很开心'); save(); renderSheet(); };
    $('#next').onclick = nextDay;
  }
  function nextDay() {
    S.day++; S.phase = 'prep'; S.clock = 8 * 60 + 30; rollDay(false); resetToday(); phaseKey = '';
    people.length = 0; crumbs.length = 0;
    if (S.day % 7 === 0) toast(`今天是甜品大赛日：「${CONTESTS[Math.floor(S.day / 7 - 1) % CONTESTS.length].name}」`);
    save(); closeSheet();
  }

  // 甜品大赛
  function sheetContest(body) {
    const c = CONTESTS[Math.floor(S.day / 7 - 1) % CONTESTS.length];
    H2(`甜品大赛 · ${c.name}`, c.note);
    if (sheetArg) { body.innerHTML = sheetArg; $('#done').onclick = closeSheet; return; }
    let html = '<div class="t2" style="margin:0 2px 10px">挑一款配方参赛（评委看口味对不对题、口感和颜值）。第一名奖金 ¥300 和一座奖杯。</div>';
    if (!S.recipes.length) html += '<div class="empty">还没有配方。</div>';
    for (const r of S.recipes) html += `<div class="card row"><canvas width="140" height="100" style="width:70px;height:50px" data-r="${r.id}"></canvas><div class="grow"><div class="t1">${r.name}</div><div>${topTags(r.tags).map((t) => `<span class="tag">${TAG_NAMES[t]}</span>`).join('')}</div></div><button class="btn dark" data-go="${r.id}">参赛</button></div>`;
    body.innerHTML = html;
    body.querySelectorAll('[data-go]').forEach((b) => b.onclick = () => {
      const r = recipeById(b.dataset.go);
      let fit = 0, wsum = 0; for (const [t, w] of Object.entries(c.want)) { fit += Math.min(1.5, r.tags[t] || 0) / 1.5 * w; wsum += w; }
      const score = Math.round(fit / wsum * 45 + r.taste * .3 + r.beauty * .3);
      const rivals = [55, 62, 70].map((v) => v + level() * 2 + (R() - .5) * 14).sort((a, b) => b - a);
      const rank = 1 + rivals.filter((v) => v > score).length;
      const prize = [300, 150, 60, 0][rank - 1], fame = [60, 30, 12, 4][rank - 1];
      S.money += prize; gainFame(fame); S.contestDay = S.day; phaseKey = '';
      if (rank === 1) S.owned.decor.trophy = (S.owned.decor.trophy || 0) + 1;
      sheetArg = `<div class="card" style="text-align:center"><canvas width="240" height="170" style="width:120px;height:85px" data-r="${r.id}"></canvas><div class="t1" style="font-size:18px;margin-top:6px">${rank === 1 ? '冠军！' : `第 ${rank} 名`}</div><div class="t2">「${r.name}」得了 ${score} 分${rank === 1 ? '，评委说它把「' + c.name + '」做到了心里。' : '。'}</div><div class="t2" style="margin-top:6px">${prize ? `奖金 ¥${prize} · ` : ''}名气 +${fame}${rank === 1 ? ' · 奖杯已放进「我的家具」' : ''}</div></div><button class="cta" id="done" style="width:100%">好</button>`;
      save(); renderSheet();
    });
  }
  // 名气、评价、解锁
  function sheetFame(body) {
    const lv = level();
    H2(`Lv${lv} · 名气 ${Math.floor(S.fame)}`, lv < LEVELS.length ? `再 ${Math.ceil(LEVELS[lv] - S.fame)} 升级` : '满级了');
    let html = `<div class="card"><div class="bar"><i style="width:${lvProgress() * 100}%"></i></div><div class="t3" style="margin-top:8px">平均评分 ${avgStars().toFixed(1)} · 卖出 ${S.stats.sold} 个 · 来过 ${S.stats.customers} 位客人 · 氛围 ${cozy()}</div></div>`;
    const nx = unlocksAt(lv + 1);
    if (nx.length) html += `<div class="card"><div class="t1">Lv${lv + 1} 解锁</div><div class="t2">${nx.join('、')}</div></div>`;
    const regs = REGULARS.filter((r) => S.regulars[r.id]);
    if (regs.length) { html += '<div class="t1" style="margin:12px 2px 8px">常客</div>'; for (const r of regs) { const st = S.regulars[r.id]; html += `<div class="card"><div class="row"><div class="t1 grow">${r.name}</div><span class="stars" style="color:#d98a9a">${'♥'.repeat(Math.min(5, Math.ceil(st.aff / 2.5)))}</span></div>${r.story.slice(0, st.story).map((s) => `<div class="t2">· ${s}</div>`).join('')}</div>`; } }
    html += '<div class="t1" style="margin:12px 2px 8px">最近的评价</div>' + (S.reviews.slice(-8).reverse().map((r) => `<div class="card"><div class="row"><div class="t1 grow" style="font-size:13px">${r.who} · 第 ${r.day} 天</div><span class="stars">${'★'.repeat(Math.round(r.stars))}</span></div><div class="t2">${r.text}</div></div>`).join('') || '<div class="empty">还没有评价。</div>');
    body.innerHTML = html;
  }
  function unlocksAt(lv) {
    const out = [];
    for (const [k, v] of Object.entries(INGREDIENTS)) if (v.lv === lv) out.push(v.name);
    for (const [k, v] of Object.entries(BASES)) if (v.lv === lv) out.push(v.name);
    for (const [k, v] of Object.entries(CREAMS)) if (v.lv === lv) out.push(v.name);
    for (const [k, v] of Object.entries(DECOR)) if (v.lv === lv) out.push(v.name);
    if (lv === 3) out.push('美食评论家会来店里');
    return out;
  }
  let lvUpQueue = [];
  function levelUp(lv) { lvUpQueue.push(lv); if (!sheetKind) openSheet('levelup'); }
  function sheetLevelUp(body) {
    const lv = lvUpQueue.shift() || level();
    H2(`升到 Lv${lv} 了！`, '店的名气越来越大');
    body.innerHTML = `<div class="card"><div class="t1">新解锁</div><div class="t2">${unlocksAt(lv).join('、') || '更多客人会慕名而来'}</div></div><button class="cta" id="ok" style="width:100%">好</button>`;
    $('#ok').onclick = () => (lvUpQueue.length ? renderSheet() : closeSheet());
  }
  // 常客的故事
  function sheetStory(body) {
    const reg = pendingStories.shift(); if (!reg) return closeSheet();
    const st = S.regulars[reg.id], i = st.story; st.story++;
    const gift = reg.gifts[i];
    let g2 = '';
    if (gift) {
      if (gift.money) { S.money += gift.money; g2 = `收到 ¥${gift.money}`; }
      if (gift.ingredient) { S.inv[gift.ingredient] = (S.inv[gift.ingredient] || 0) + gift.n; g2 = `收到${INGREDIENTS[gift.ingredient].name} ×${gift.n}`; }
      if (gift.unlockCream) { S.unlockCreams.push(gift.unlockCream); g2 = `学会了「${CREAMS[gift.unlockCream].name}」`; }
      if (gift.decor) { S.owned.decor[gift.decor] = (S.owned.decor[gift.decor] || 0) + 1; g2 = `收到「${DECOR[gift.decor].name}」，在「装修」里摆出来`; }
      if (gift.discount) { S.discounts[gift.discount] = true; g2 = `${INGREDIENTS[gift.discount].name}以后便宜一成`; }
      if (gift.fame) { gainFame(gift.fame); g2 = `名气 +${gift.fame}`; }
    }
    H2(reg.name, '常客的小故事');
    body.innerHTML = `<div class="card"><div class="t2" style="font-size:14px;line-height:1.8;color:var(--ink)">${reg.story[i]}</div>${g2 ? `<div style="margin-top:8px"><span class="tag rose">${g2}</span></div>` : ''}</div><button class="cta" id="ok" style="width:100%">好</button>`;
    $('#ok').onclick = () => (pendingStories.length ? renderSheet() : closeSheet());
    save();
  }

  // ———————————————— 厨房：设计一款甜点 ————————————————
  const kEl = $('#kitchen'), kBody = $('#kBody');
  let K = null;
  const STEPS = ['base', 'cream', 'mix', 'bake', 'deco', 'done'];
  function openKitchen(edit) {
    if (!edit && S.phase === 'open') { /* 营业时也能设计：时间会停 */ }
    K = edit ? { edit, step: 'deco', r: JSON.parse(JSON.stringify(edit)), undo: [] } : { step: 'base', r: { base: null, cream: null, items: [], pipes: [], drizzle: [], dust: false, seed: (R() * 9999) | 0, mix: 0, bake: 0 }, undo: [] };
    kEl.classList.add('open'); closeSheet(); navOn('kitchen');
    renderKitchen();
  }
  function closeKitchen() { kEl.classList.remove('open'); K = null; navOn('shop'); }
  $('#kBack').onclick = async () => {
    if (!K) return;
    const i = STEPS.indexOf(K.step);
    if (K.edit || i <= 0 || K.step === 'done') return closeKitchen();
    if (K.step === 'deco' || K.step === 'bake' || K.step === 'mix') { if (!(await ask('退出的话这一份就不做了，确定吗？', '退出', '接着做'))) return; return closeKitchen(); }
    K.step = STEPS[i - 1]; renderKitchen();
  };
  function renderKitchen() {
    cancelAnimationFrame(kAnim);
    const i = STEPS.indexOf(K.step);
    $('#kSteps').innerHTML = STEPS.slice(0, 5).map((s, j) => `<i class="${j <= i ? 'on' : ''}"></i>`).join('');
    $('#kTitle').textContent = { base: '选一种坯底', cream: '选奶油口味', mix: '搅拌面糊', bake: '烘烤', deco: K.edit ? '改装饰' : '自由装饰', done: '完成' }[K.step];
    $('#kSub').textContent = K.step === 'deco' ? '' : '';
    ({ base: kBase, cream: kCream, mix: kMix, bake: kBake, deco: kDeco, done: kDone })[K.step]();
  }
  const have = (need) => Object.entries(need).every(([k, v]) => (S.inv[k] || 0) >= v);
  const needText = (need) => Object.entries(need).map(([k, v]) => `<span style="color:${(S.inv[k] || 0) >= v ? 'inherit' : '#c0505f'}">${INGREDIENTS[k].name}${v > 1 ? '×' + v : ''}</span>`).join(' · ');
  function kBase() {
    const lv = level();
    let html = '<div class="grid2">';
    for (const [k, b] of Object.entries(BASES)) {
      const locked = b.lv > lv;
      html += `<button class="pick" data-b="${k}" ${locked ? 'disabled' : ''}><canvas width="200" height="150" style="width:100px;height:75px" data-prev="${k}"></canvas><div class="t1" style="font-size:13.5px">${b.name}</div><div class="t3" style="margin-top:3px;line-height:1.5">${needText(b.need)}</div>${locked ? `<div class="lock">Lv${b.lv} 解锁</div>` : ''}</button>`;
    }
    html += '</div><div class="t3" style="margin:10px 2px">一份料做 4 个。红字的食材不够，可以先去集市买。</div>';
    kBody.innerHTML = html;
    kBody.querySelectorAll('canvas[data-prev]').forEach((c) => { const x = c.getContext('2d'); INK.dessert(x, { base: c.dataset.prev, cream: 'plain', items: [], pipes: [], drizzle: [], seed: 3 }, 100, 118, 120); });
    kBody.querySelectorAll('[data-b]').forEach((b) => b.onclick = () => { if (!have(BASES[b.dataset.b].need)) return toast('食材不够，先去集市买一点'); K.r.base = b.dataset.b; K.step = 'cream'; renderKitchen(); });
  }
  function kCream() {
    let html = '<div class="grid2">';
    for (const [k, c] of Object.entries(CREAMS)) {
      const locked = !creamOK(k);
      html += `<button class="pick" data-c="${k}" ${locked ? 'disabled' : ''}><canvas width="200" height="150" style="width:100px;height:75px" data-prev="${k}"></canvas><div class="t1" style="font-size:13.5px">${c.name}</div><div class="t3" style="margin-top:3px">${needText(c.need)}</div>${locked ? `<div class="lock">Lv${c.lv} 解锁</div>` : ''}</button>`;
    }
    html += '</div>';
    kBody.innerHTML = html;
    kBody.querySelectorAll('canvas[data-prev]').forEach((c) => { const x = c.getContext('2d'); INK.dessert(x, { base: K.r.base, cream: c.dataset.prev, items: [], pipes: [], drizzle: [], seed: 3 }, 100, 118, 120); });
    kBody.querySelectorAll('[data-c]').forEach((b) => b.onclick = () => {
      const all = {}; for (const need of [BASES[K.r.base].need, CREAMS[b.dataset.c].need]) for (const [k, v] of Object.entries(need)) all[k] = (all[k] || 0) + v;
      if (!have(all)) return toast('食材不够，先去集市买一点');
      K.r.cream = b.dataset.c;
      if (S.up.mixer >= 1) { K.r.mix = S.up.mixer >= 2 ? 98 : 92; K.step = 'bake'; toast('搅拌机打好了面糊'); } else K.step = 'mix';
      renderKitchen();
    });
  }
  // —— 搅拌：手指在碗里画圈 ——
  let kAnim = 0;
  function kitchenCanvas(h) {
    kBody.innerHTML = `<canvas id="kc"></canvas><div id="kUnder"></div>`;
    const c = $('#kc'), w = kBody.clientWidth - 32 || 340; c.style.height = h + 'px';
    c.width = w * DPR; c.height = h * DPR; const x = c.getContext('2d'); x.scale(DPR, DPR);
    return { c, x, w, h };
  }
  function kMix() {
    const { c, x, w, h } = kitchenCanvas(Math.min(360, innerHeight * .45));
    $('#kUnder').innerHTML = `<div class="meter">顺滑度<div class="bar sage"><i id="mixBar" style="width:0"></i></div><span id="mixTxt">0%</span></div><div class="t3" style="margin:4px 2px 12px">用手指在碗里画圈。到绿色那一段刚好，搅过头会起筋。</div><button class="cta" id="mixOk" style="width:100%">好了</button>`;
    let p = 0, last = null, wx = w / 2, wy = h / 2;
    const cx = w / 2, cy = h / 2 + 6, rad = Math.min(w, h) * .36;
    const lumps = Array.from({ length: 16 }, () => [R() * TAU, Math.sqrt(R()) * .8, .5 + R() * .5]);
    const col = CREAMS[K.r.cream].color;
    c.onpointermove = (e) => {
      const b = c.getBoundingClientRect(); wx = e.clientX - b.left; wy = e.clientY - b.top;
      if (e.buttons || e.pointerType === 'touch') {
        const a = Math.atan2(wy - cy, wx - cx);
        if (last != null) { let d = a - last; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; if (Math.hypot(wx - cx, wy - cy) < rad * 1.2) p += Math.abs(d) / TAU * 12; }
        last = a;
      }
    };
    c.onpointerup = () => { last = null; };
    const loop = () => {
      x.clearRect(0, 0, w, h);
      ART.softShadow(x, cx, cy + rad * .9, rad * 1.2, rad * .25, .25);
      // 碗
      const bg = x.createRadialGradient(cx - rad * .3, cy - rad * .3, rad * .2, cx, cy, rad * 1.25); bg.addColorStop(0, '#ffffff'); bg.addColorStop(1, '#d9cfc2');
      x.fillStyle = bg; x.beginPath(); x.arc(cx, cy, rad * 1.18, 0, TAU); x.fill();
      x.strokeStyle = '#c8a96c'; x.lineWidth = 2; x.beginPath(); x.arc(cx, cy, rad * 1.12, 0, TAU); x.stroke();
      // 面糊：越搅越顺，疙瘩越来越少
      const smooth = clamp(p / 85, 0, 1);
      const fg = x.createRadialGradient(cx - rad * .2, cy - rad * .25, rad * .1, cx, cy, rad);
      fg.addColorStop(0, ART.shade('#f3e3c4', .3)); fg.addColorStop(1, ART.shade('#e9d2a8', -.05 * smooth));
      x.fillStyle = fg; x.beginPath(); x.arc(cx, cy, rad, 0, TAU); x.fill();
      x.strokeStyle = `rgba(200,170,120,${.25 + .3 * smooth})`; x.lineWidth = 2;
      for (let i = 0; i < 4; i++) { x.beginPath(); x.arc(cx, cy, rad * (.25 + i * .18), T * 2 + i, T * 2 + i + 2.2 * smooth + .4); x.stroke(); }
      for (const [a, d, s] of lumps) { if (s < smooth) continue; x.fillStyle = 'rgba(240,230,210,.95)'; ART.ellipse(x, cx + Math.cos(a + p * .05) * d * rad, cy + Math.sin(a + p * .05) * d * rad, 7 * (s - smooth + .3), 5 * (s - smooth + .3)); x.fill(); }
      if (p > 100) { x.strokeStyle = 'rgba(160,120,80,.35)'; for (let i = 0; i < (p - 100) / 3; i++) { x.beginPath(); x.arc(cx, cy, rad * (.3 + i * .05), 0, TAU); x.stroke(); } }
      // 打蛋器
      x.save(); x.translate(wx, wy); x.rotate(-.5);
      x.strokeStyle = '#b9b2a8'; x.lineWidth = 2; for (const s of [-1, 0, 1]) { x.beginPath(); x.ellipse(s * 4, -18, 8, 22, 0, 0, TAU); x.stroke(); }
      x.fillStyle = '#c9a27c'; ART.rr(x, -5, -70, 10, 34, 4); x.fill();
      x.restore();
      $('#mixBar').style.width = Math.min(100, p) + '%'; $('#mixBar').style.background = p >= 70 && p <= 95 ? 'var(--sage)' : p > 100 ? '#d0606f' : '#c8a96c';
      $('#mixTxt').textContent = Math.round(p) + '%';
      kAnim = requestAnimationFrame(loop);
    };
    loop();
    $('#mixOk').onclick = () => { if (p < 20) return toast('再多搅一会儿'); K.r.mix = Math.round(clamp(100 - Math.abs(p - 85) * 2.2, 20, 100)); K.step = 'bake'; renderKitchen(); };
  }
  // —— 烘烤：看颜色，金黄的那一刻取出来 ——
  function kBake() {
    const { c, x, w, h } = kitchenCanvas(Math.min(360, innerHeight * .45));
    $('#kUnder').innerHTML = `<div class="meter">火候<div class="bar" style="position:relative"><i id="bakeBar" style="width:0;background:#d9a865"></i></div></div><div class="t3" style="margin:4px 2px 12px">看着烤箱里的颜色，变成金黄的时候点「出炉」。早了会塌，晚了会焦。</div><button class="cta" id="bakeOk" style="width:100%">出炉</button>`;
    let heat = 0, done = false, lastT = performance.now();
    const rateK = S.up.oven >= 2 ? .12 : .16;   // 每秒涨多少（好烤箱慢一点，好掌握）
    const lerp3 = (a, b, t) => { const A = ART.hex(a), B = ART.hex(b); return A.map((v, i) => v + (B[i] - v) * t); };
    const crust = (h) => h < 1 ? lerp3('#f3e6c8', '#d99a50', clamp(h, 0, 1)) : lerp3('#d99a50', '#5e3420', clamp((h - 1) * 2.2, 0, 1));
    const loop = () => {
      const now = performance.now(), dt = Math.min(.4, (now - lastT) / 1000); lastT = now;
      if (!done) heat += rateK * dt;
      x.clearRect(0, 0, w, h);
      // 烤箱
      const ox = w * .1, oy = h * .08, ow = w * .8, oh = h * .82;
      const og = x.createLinearGradient(0, oy, 0, oy + oh); og.addColorStop(0, '#e9e2d8'); og.addColorStop(1, '#cfc4b4');
      x.fillStyle = og; ART.rr(x, ox, oy, ow, oh, 18); x.fill();
      x.fillStyle = '#5a4a44'; ART.rr(x, ox + ow * .1, oy + oh * .18, ow * .8, oh * .62, 12); x.fill();
      // 里面亮着橘色的光
      const glow = x.createRadialGradient(w / 2, oy + oh * .5, 10, w / 2, oy + oh * .5, ow * .5); glow.addColorStop(0, `rgba(255,170,90,${.35 + .2 * Math.sin(T * 4)})`); glow.addColorStop(1, 'rgba(255,170,90,.05)');
      x.fillStyle = glow; ART.rr(x, ox + ow * .1, oy + oh * .18, ow * .8, oh * .62, 12); x.fill();
      x.save(); x.beginPath(); ART.rr(x, ox + ow * .1, oy + oh * .18, ow * .8, oh * .62, 12); x.clip();
      // 烤盘上的模具，面糊慢慢鼓起来、上色：生的浅黄 → 金黄 → 焦
      const rise = clamp(heat, 0, 1.1), px = w / 2, py = oy + oh * .7, pr = ow * .26;
      x.fillStyle = '#8a7a6a'; x.fillRect(ox + ow * .14, py + 10, ow * .72, 4);
      const mould = K.r.base === 'cupcake' ? '#f2c9c6' : K.r.base === 'tart' ? '#d9a865' : '#b9b2a8';
      x.fillStyle = mould; ART.rr(x, px - pr, py - pr * .32, pr * 2, pr * .42, 6); x.fill();
      const top = py - pr * .32 - pr * (.08 + .32 * rise);
      const cg = x.createRadialGradient(px - pr * .3, top, pr * .1, px, py - pr * .2, pr * 1.1);
      const cc = crust(heat);
      cg.addColorStop(0, ART.rgb(cc.map((v) => v + (255 - v) * .3))); cg.addColorStop(1, ART.rgb(cc));
      x.fillStyle = cg; x.beginPath(); x.moveTo(px - pr * .98, py - pr * .3); x.bezierCurveTo(px - pr * .95, top - pr * .05, px + pr * .95, top - pr * .05, px + pr * .98, py - pr * .3); x.closePath(); x.fill();
      if (heat > .6) { x.strokeStyle = `rgba(120,70,30,${clamp((heat - .6) * .8, 0, .5)})`; x.lineWidth = 1.5; x.beginPath(); x.moveTo(px - pr * .4, top + pr * .12); x.quadraticCurveTo(px, top + pr * .04, px + pr * .35, top + pr * .14); x.stroke(); }   // 顶上裂开一道
      if (heat > 1.15) { x.fillStyle = `rgba(90,80,80,${clamp((heat - 1.15) * .8, 0, .35)})`; for (let i = 0; i < 4; i++) { x.beginPath(); x.arc(px + (i - 1.5) * 18 + Math.sin(T * 2 + i) * 6, top - 20 - ((T * 30 + i * 13) % 40), 8 + i, 0, TAU); x.fill(); } }   // 冒烟了
      x.restore();
      x.strokeStyle = 'rgba(255,255,255,.35)'; x.lineWidth = 3; x.beginPath(); x.moveTo(ox + ow * .18, oy + oh * .24); x.lineTo(ox + ow * .3, oy + oh * .24); x.stroke();
      x.fillStyle = '#b9b2a8'; ART.rr(x, ox + ow * .25, oy + oh * .08, ow * .5, 8, 4); x.fill();
      for (let i = 0; i < 3; i++) { x.fillStyle = '#8a7a6a'; x.beginPath(); x.arc(ox + ow * (.3 + i * .2), oy + oh * .9, 7, 0, TAU); x.fill(); }
      const bar = $('#bakeBar'); if (bar) { bar.style.width = clamp(heat / 1.4, 0, 1) * 100 + '%'; bar.style.background = heat > .9 && heat < 1.1 ? 'var(--sage)' : heat >= 1.1 ? '#8a5a3c' : '#d9a865'; }
      if (heat > 1.45 && !done) finish();
      kAnim = requestAnimationFrame(loop);
    };
    const finish = () => { done = true; K.r.bake = Math.round(clamp(100 - Math.abs(heat - 1) * 220, 15, 100)); toast(K.r.bake > 85 ? '烤得刚刚好！' : K.r.bake > 55 ? '还不错' : heat > 1 ? '有点焦了……' : '有点没熟……'); setTimeout(() => { K.step = 'deco'; renderKitchen(); }, 600); };
    loop();
    $('#bakeOk').onclick = () => { if (!done) finish(); };
  }
  // —— 装饰：随便摆、随便画 ——
  function availToppings() { return Object.entries(TOPPINGS).filter(([k, t]) => INGREDIENTS[t.uses].lv <= level() && (S.inv[t.uses] || 0) > 0); }
  function kDeco() {
    const { c, x, w, h } = kitchenCanvas(Math.min(330, innerHeight * .42));
    const tops = availToppings();
    if (!K.tool) K.tool = tops.length ? 'item' : 'pipe';
    if (!K.top && tops.length) K.top = tops[0][0];
    if (!K.pc) K.pc = CREAMS[K.r.cream].color;
    // 裱花能用的奶油：这款的口味排第一，再加上解锁了的
    const pipeCols = [];
    for (const k of [K.r.cream, 'plain', ...Object.keys(CREAMS).filter(creamOK)]) { const c = CREAMS[k]; if (!pipeCols.some((p) => p[0] === c.color)) pipeCols.push([c.color, c.name.replace(/奶油|甘纳许|凝乳/g, '') || '原味']); }
    const ui = $('#kUnder');
    const drawUI = () => {
      ui.innerHTML = `<div class="tools">
        <button data-tool="item" class="${K.tool === 'item' ? 'on' : ''}"><svg class="i" viewBox="0 0 24 24"><path d="M12 20c-4-3-7-6-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 4-3 7-7 10z"/></svg>放装饰</button>
        <button data-tool="pipe" class="${K.tool === 'pipe' ? 'on' : ''}"><svg class="i" viewBox="0 0 24 24"><path d="M7 3l10 10-3 3L4 6zM14 16l4 5M6 18c2 0 3-1 4-2"/></svg>裱花</button>
        <button data-tool="drizzle" class="${K.tool === 'drizzle' ? 'on' : ''}" ${(S.inv.cocoa || 0) + (S.inv.caramel || 0) ? '' : 'disabled'}><svg class="i" viewBox="0 0 24 24"><path d="M4 8c3 0 3 4 6 4s3-4 6-4 3 4 4 4M7 12v5M13 12v7M18 12v3"/></svg>淋酱</button>
        <button data-tool="dust" class="${K.r.dust ? 'on' : ''}" ${(S.inv.sugar || 0) ? '' : 'disabled'}><svg class="i" viewBox="0 0 24 24"><path d="M5 4h14l-2 6H7zM8 14h.01M12 16h.01M16 14h.01M10 19h.01M14 20h.01"/></svg>糖粉</button>
        <button data-tool="undo"><svg class="i" viewBox="0 0 24 24"><path d="M9 14L4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3"/></svg>撤销</button>
        <button data-tool="clear"><svg class="i" viewBox="0 0 24 24"><path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13"/></svg>清空</button></div>
        <div class="palette" id="pal"></div>
        <div class="t3" style="margin:0 2px 4px">${K.tool === 'item' ? '点一下放上去 · 按住拖动挪位置 · 长按拿掉' : K.tool === 'pipe' ? '在蛋糕顶上画线，沿线挤出奶油花' : K.tool === 'drizzle' ? '在顶上画线淋酱' : ''}</div>
        <div class="meter">颜值<div class="bar"><i style="width:${beautyOf(K.r)}%"></i></div><span>${beautyOf(K.r)}</span></div>
        <div style="margin:4px 2px 10px">${topTags(tagsOf(K.r), 4).map((t) => `<span class="tag">${TAG_NAMES[t]}</span>`).join('')}${S.clawdJob === 'taste' ? ' <span class="t3">clawd 尝了尝：' + (pairsOf(K.r).length ? '这几样很搭！' : '再加点别的试试？') + '</span>' : ''}</div>
        <button class="cta" id="decoOk" style="width:100%">${K.edit ? '保存装饰' : '装饰好了'}</button>`;
      const pal = $('#pal');
      if (K.tool === 'item') pal.innerHTML = tops.length ? tops.map(([k, t]) => `<button data-top="${k}" class="${K.top === k ? 'on' : ''}"><canvas width="64" height="64" style="width:32px;height:32px" data-t="${k}"></canvas>${t.name}</button>`).join('') : '<div class="t3" style="padding:8px">没有能做装饰的水果、坚果、花了，去集市买一点吧。</div>';
      else if (K.tool === 'pipe') pal.innerHTML = pipeCols.map(([col, n]) => `<button data-pc="${col}" class="${K.pc === col ? 'on' : ''}"><span class="swatch" style="background:${col}"></span>${n}</button>`).join('');
      else if (K.tool === 'drizzle') pal.innerHTML = [['#6b4a3a', '巧克力', 'cocoa'], ['#c7894a', '焦糖', 'caramel']].filter(([, , k]) => (S.inv[k] || 0) > 0).map(([col, n]) => `<button data-dc="${col}" class="${(K.dc || '#6b4a3a') === col ? 'on' : ''}"><span class="swatch" style="background:${col}"></span>${n}</button>`).join('');
      else pal.innerHTML = '';
      pal.querySelectorAll('canvas[data-t]').forEach((cc) => { const xx = cc.getContext('2d'); INK.topping(xx, cc.dataset.t, 32, 34, 44, 0); });
      pal.querySelectorAll('[data-top]').forEach((b) => b.onclick = () => { K.top = b.dataset.top; drawUI(); });
      pal.querySelectorAll('[data-pc]').forEach((b) => b.onclick = () => { K.pc = b.dataset.pc; drawUI(); });
      pal.querySelectorAll('[data-dc]').forEach((b) => b.onclick = () => { K.dc = b.dataset.dc; drawUI(); });
      ui.querySelectorAll('[data-tool]').forEach((b) => b.onclick = () => {
        const t = b.dataset.tool;
        if (t === 'undo') { const u = K.undo.pop(); if (u) K.r = { ...K.r, ...JSON.parse(u) }; }
        else if (t === 'clear') { snap(); K.r.items = []; K.r.pipes = []; K.r.drizzle = []; K.r.dust = false; }
        else if (t === 'dust') { snap(); K.r.dust = !K.r.dust; }
        else K.tool = t;
        drawUI();
      });
      $('#decoOk').onclick = () => {
        if (K.edit) { const r = recipeById(K.edit.id); Object.assign(r, { items: K.r.items, pipes: K.r.pipes, drizzle: K.r.drizzle, dust: K.r.dust }); finishRecipe(r); save(); toast('装饰改好了'); closeKitchen(); return; }
        K.step = 'done'; renderKitchen();
      };
    };
    const snap = () => { K.undo.push(JSON.stringify({ items: K.r.items, pipes: K.r.pipes, drizzle: K.r.drizzle, dust: K.r.dust })); if (K.undo.length > 40) K.undo.shift(); };
    drawUI();
    const DW = Math.min(w * .78, h * 1.25), dx = w / 2, dy = h * .8;
    const s = INK.SHAPE[K.r.base];
    const toUV = (px, py) => [(px - dx) / (s.rx * DW), (py - (dy + s.top * DW)) / (s.ry * DW)];
    let drag = null, stroke = null;
    c.onpointerdown = (e) => {
      const b = c.getBoundingClientRect(), px = e.clientX - b.left, py = e.clientY - b.top, [u, v] = toUV(px, py);
      try { c.setPointerCapture(e.pointerId); } catch (err) {}
      if (K.tool === 'item') {
        // 按在已有的装饰上：拖就是挪它，长按不动是拿掉，轻点一下还是照样再放一个（挨着放、叠着放都行）
        let hit = null;
        for (let i = K.r.items.length - 1; i >= 0; i--) { const it = K.r.items[i]; const [ix, iy] = INK.topPoint(K.r.base, dx, dy, DW, it.u, it.v); if (Math.hypot(ix - px, iy - DW * .03 - py) < DW * .055) { hit = it; break; } }
        drag = { it: hit, t0: performance.now(), moved: false, u, v };
        if (hit) { snap(); drag.hold = setTimeout(() => { if (drag && !drag.moved) { K.r.items = K.r.items.filter((x2) => x2 !== hit); drag.removed = true; toast('拿掉了'); drawUI(); } }, 480); }
      } else if (K.tool === 'pipe' || K.tool === 'drizzle') {
        if (u * u + v * v > 1.1) return;
        snap(); stroke = { c: K.tool === 'pipe' ? K.pc : (K.dc || '#6b4a3a'), pts: [[u, v]] };
        (K.tool === 'pipe' ? K.r.pipes : K.r.drizzle).push(stroke);
      }
    };
    c.onpointermove = (e) => {
      const b = c.getBoundingClientRect(), [u, v] = toUV(e.clientX - b.left, e.clientY - b.top);
      if (drag && drag.it && !drag.removed && (drag.moved || Math.hypot(u - drag.u, v - drag.v) > .08)) { const k = Math.hypot(u, v); drag.it.u = k > 1 ? u / k : u; drag.it.v = k > 1 ? v / k : v; drag.moved = true; }
      if (stroke) { const k = Math.hypot(u, v); const q = k > 1 ? [u / k, v / k] : [u, v]; const l = stroke.pts[stroke.pts.length - 1]; if (Math.hypot(q[0] - l[0], q[1] - l[1]) > .05) stroke.pts.push(q); }
    };
    c.onpointerup = () => {
      if (drag) { clearTimeout(drag.hold); if (!drag.moved && !drag.removed && drag.u * drag.u + drag.v * drag.v <= 1.05 && K.top) { if (!drag.it) snap(); K.r.items.push({ t: K.top, u: drag.u, v: drag.v, a: (R() - .5) * 1.2, s: .9 + R() * .2 }); } }
      if (stroke && K.tool === 'drizzle' && stroke.pts.length < 2) K.r.drizzle.pop();
      drag = null; stroke = null; drawUI();
    };
    const loop = () => {
      x.clearRect(0, 0, w, h);
      INK.dessert(x, K.r, dx, dy, DW);
      // 能放东西的那一圈：淡淡的虚线
      x.strokeStyle = 'rgba(217,138,154,.35)'; x.setLineDash([4, 5]); x.lineWidth = 1.2; ART.ellipse(x, dx, dy + s.top * DW, s.rx * DW * 1.02, s.ry * DW * 1.02); x.stroke(); x.setLineDash([]);
      kAnim = requestAnimationFrame(loop);
    };
    loop();
  }
  // ———————————————— 分享海报 ————————————————
  // 剪纸风的海报：一句英文一句中文、整块底色、底下格纹 / 波点；能换一句、换底纹，保存时交给 App 选存进哪个相册
  let PV = null;
  function openPoster(r) {
    const tags = Object.entries(r.tags || {}).sort((a, b) => b[1] - a[1]).map((e) => e[0]).filter((t) => INK.LINES[t]);
    PV = { r, tags: tags.length ? tags : ['sweet'], ti: 0, pat: (r.seed || 0) % 2 };
    $('#poster').classList.add('open'); drawPoster();
  }
  function drawPoster() {
    const c = $('#pc'), W = 1080, H = 1920;
    c.width = W; c.height = H;
    const x = c.getContext('2d');
    INK.poster(x, { ...PV.r, name: PV.r.name }, W, H, { tag: PV.tags[PV.ti % PV.tags.length], pattern: PV.pat });
  }
  $('#pLine').onclick = () => { PV.ti++; if (PV.ti >= PV.tags.length) { PV.tags = [...PV.tags, ...Object.keys(INK.LINES).filter((t) => !PV.tags.includes(t))]; } drawPoster(); };
  $('#pPat').onclick = () => { PV.pat++; drawPoster(); };
  $('#pClose').onclick = () => { $('#poster').classList.remove('open'); PV = null; };
  $('#pSave').onclick = () => {
    const url = $('#pc').toDataURL('image/png');
    if (window.webkit?.messageHandlers?.bake) window.webkit.messageHandlers.bake.postMessage({ poster: url, title: PV.r.name || '甜点' });
    else { const a = document.createElement('a'); a.href = url; a.download = (PV.r.name || 'dessert') + '.png'; a.click(); }
  };
  // App 存好了回一句
  window.__posterSaved = (where) => { toast(where ? '已保存到「' + where + '」' : '已保存'); };

  function kDone() {
    const r = finishRecipe(K.r);
    const cr = CREAMS[r.cream].name.replace('奶油', '').replace('甘纳许', '').replace('凝乳', '').replace('原味', '');
    if (!r.name) r.name = (cr ? cr : '') + BASES[r.base].name;
    window.__draft = r;
    const n = Math.min(batch(), (() => { const tmp = { ...r }; let m = 0; for (let i = 1; i <= batch(); i++) if (Object.entries(needs(tmp, i)).every(([k, v]) => (S.inv[k] || 0) >= v)) m = i; return m; })());
    const pairs = pairsOf(r);
    kBody.innerHTML = `<div class="card" style="text-align:center"><canvas width="440" height="300" style="width:220px;height:150px" id="finalC"></canvas>
      <input id="rName" value="${r.name}" maxlength="10" style="display:block;margin:6px auto 4px;text-align:center;font-size:18px;font-weight:600;border:0;border-bottom:1.5px dashed var(--line);background:none;width:70%;padding:4px">
      <div>${topTags(r.tags, 4).map((t) => `<span class="tag">${TAG_NAMES[t]}</span>`).join('')}</div>
      <div class="meter" style="margin-top:10px">口感<div class="bar sage"><i style="width:${r.taste}%"></i></div><span>${r.taste}</span></div>
      <div class="meter">颜值<div class="bar"><i style="width:${r.beauty}%"></i></div><span>${r.beauty}</span></div>
      <div class="t3" style="margin-top:6px">搅拌 ${r.mix} · 火候 ${r.bake}${pairs.length ? ' · 绝配：' + pairs.map(([a, b]) => INGREDIENTS[a].name + '×' + INGREDIENTS[b].name).join('、') : ''}</div>
      <div class="t3">一个成本 ¥${r.cost} · 建议卖 ¥${suggestPrice(r)}</div></div>
      <button class="cta rose" id="share" style="width:100%;margin-bottom:8px">做一张分享海报</button>
      <button class="cta" id="keep" style="width:100%;margin-top:4px">${n ? `收进配方簿，做一炉（${n} 个）` : '收进配方簿（料不够做一炉）'}</button>`;
    const fc = $('#finalC').getContext('2d'); INK.dessert(fc, r, 220, 250, 300);
    $('#share').onclick = () => { r.name = ($('#rName').value || r.name).trim().slice(0, 10); openPoster(r); };
    $('#keep').onclick = () => {
      r.name = ($('#rName').value || r.name).trim().slice(0, 10);
      r.id = 'r' + (S.nextId++); r.price = suggestPrice(r); r.sold = 0; r.starSum = 0;
      S.recipes.unshift(r); window.__draft = null;
      if (n) { for (const [k, v] of Object.entries(needs(r, n))) S.inv[k] -= v; addStock(r.id, n, 0); today.made += n; }
      // 第一次：直接帮她摆进展示柜
      if (S.tut === 0) { const i = S.display.findIndex((s) => !s); if (i >= 0 && n) putOnShelf(r.id, i, 0); setTut(S.display.some((s) => s && s.n > 0) ? 2 : 1); }
      save(); closeKitchen();
      toast(n ? `「${r.name}」做好了 ${n} 个，放在库存里` : `「${r.name}」收进了配方簿`);
    };
  }

  // ———————————————— 跑起来 ————————————————
  let last = performance.now();
  function frame(now) {
    // 一秒最多画 30 帧（省电、不发烫）；退到后台不画
    if (now - last < 31 || document.hidden) { requestAnimationFrame(frame); return; }
    const dt = Math.min(.08, (now - last) / 1000); last = now; T += dt;
    const paused = !!K || (sheetKind && sheetKind !== 'decor' && sheetKind !== 'shop' && sheetKind !== 'book' && sheetKind !== 'market');
    if (S.phase === 'open' && !paused) { tick(dt); updatePeople(dt); }
    else if (S.phase !== 'open') updatePeople(dt * .0);
    for (const f of floats) f.t += dt; for (let i = floats.length - 1; i >= 0; i--) if (floats[i].t > 1.8) floats.splice(i, 1);
    if (camGoal != null) { camX += (clamp(camGoal, 0, Math.max(0, SCENE.WW - W / SC)) - camX) * Math.min(1, dt * 6); if (Math.abs(camX - camGoal) < 1 || down) camGoal = null; }
    if (!K) drawScene();
    hud(); phaseBar();
    saveT += dt; if (saveT > 10 && S.phase === 'open') { saveT = 0; save(); }
    requestAnimationFrame(frame);
  }
  if (fresh) rollDay(true);
  resize(); showTut(); camX = SCENE.WW - W / SC;
  if (S.phase === 'open') { S.phase = 'prep'; S.clock = 8 * 60 + 30; }   // 中途退出的那天：重新从开门前开始
  requestAnimationFrame(frame);
  if (S.tut === 0) setTimeout(() => clawdSay('今天开张！先做点甜点吧～'), 800);
  window.__bake = { S: () => S, K: () => K, spawn, openKitchen, save, draw: () => drawScene(), step: (dt) => { if (S.phase === "open") { tick(dt); updatePeople(dt); } T += dt; } };
})();
