/*
 * 把电脑上的 Claude Code 包成一个 /v1/chat/completions 接口，
 * 手机上的栖当成一个普通供应商用（同一个 WiFi 下直接连）。
 *
 * 跑起来：node bridge.js        （或者双击同目录的「启动桥.bat」）
 * 手机那边：设置 → 供应商 → 新增，接口地址填屏幕上打出来的那个
 *          http://192.168.x.x:8787/v1 ，密钥留空（或者填下面的 BRIDGE_TOKEN）。
 *
 * 零依赖，只用 Node 自带的东西。Node 版本 18 以上。
 *
 * ── 这个桥能做什么、不能做什么 ──
 *
 * 能：正常聊天（逐字出字）、带图（他会去读那张图）、**用工具**。
 * 不能：Claude Code 那边不认「函数调用」这套协议——它只会说话。
 *       所以工具是**用文字约定**转的：把工具清单写进系统提示，
 *       让他要用工具的时候只输出一段 ```tool_call 的 JSON，
 *       这边再翻译回 OpenAI 那套 tool_calls 交给 App。
 *       他偶尔会不照格式写，那一轮就当普通说话处理——不会崩，只是没调成。
 *
 * ── 开工前先确认一件事 ──
 *
 * 在这台电脑上单独跑一次：  claude -p "说一个字：好"
 * 打出「Not logged in」的话，先 claude 登录（**要挂着你平时用的梯子**），
 * 登好了这个桥才有用。桥本身不管登录。
 */

'use strict';

const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PORT = parseInt(process.env.BRIDGE_PORT || '8787', 10);
/* 留空就是不校验。同一个 WiFi 下没别人的话不填也行；
   填了的话手机那边的「密钥」栏填一样的。 */
const TOKEN = process.env.BRIDGE_TOKEN || '';
/* 同时最多跑几个 claude。她可能一边聊天一边后台起个小活儿，
   给到 3；再多就排队，免得把电脑跑满。 */
const MAX_CONCURRENT = parseInt(process.env.BRIDGE_CONCURRENCY || '3', 10);
/* 一轮最多等多久（毫秒）。App 那边的超时是 300 秒，这里留一点余量。 */
const TIMEOUT_MS = parseInt(process.env.BRIDGE_TIMEOUT || '280000', 10);

const TMP = path.join(os.tmpdir(), 'qi-claude-bridge');
fs.mkdirSync(TMP, { recursive: true });

/* 工坐区那一档在哪个目录里干活。
 *
 * 她定的：「工作区不是阿晏，工作区就是 claude 本身，
 * 跟阿晏没关系。所以可以带上上下文。」
 *
 * 默认是这个仓库根（桥自己往上两层）。
 * 要换到别的项目，启动前设 `BRIDGE_WORKSPACE`。 */
const WORKSPACE = process.env.BRIDGE_WORKSPACE
  || path.resolve(__dirname, '..', '..');

const IS_WIN = process.platform === 'win32';

/**
 * 找到 claude 本体。
 *
 * **要的是那个 .exe，不是 PATH 里那个 claude.cmd**——
 * 走 .cmd 就得开 shell，而开了 shell 之后 Node 是把参数**直接拼成一行**的，
 * 不加引号：系统提示里那些空格、引号会把命令行拆得七零八落。
 * npm 装的话本体在 %APPDATA%/npm/node_modules/@anthropic-ai/claude-code/bin/ 里。
 */
function resolveClaude() {
  if (process.env.BRIDGE_CLAUDE) return { cmd: process.env.BRIDGE_CLAUDE, shell: false };
  const guesses = [];
  if (IS_WIN && process.env.APPDATA) {
    guesses.push(path.join(process.env.APPDATA, 'npm', 'node_modules',
                           '@anthropic-ai', 'claude-code', 'bin', 'claude.exe'));
  }
  guesses.push(path.join(os.homedir(), '.local', 'bin', IS_WIN ? 'claude.exe' : 'claude'));
  const exts = IS_WIN ? ['.exe'] : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const e of exts) guesses.push(path.join(dir, 'claude' + e));
  }
  for (const g of guesses) {
    try { if (fs.statSync(g).isFile()) return { cmd: g, shell: false }; } catch (e) {}
  }
  // 实在找不着，退回去让 shell 自己找（参数拼接的风险自负）
  return { cmd: 'claude', shell: true };
}

const CLAUDE = resolveClaude();

// ────────────────────────────── 提示词

const FENCE = '```';

/** 工具那一段的说明。**这是整座桥最脆的地方**，写得越死越好。 */
function toolProtocol(tools) {
  if (!tools || !tools.length) return '';
  const list = tools.map(t => {
    const f = t.function || t;
    return `### ${f.name}\n${f.description || ''}\n参数（JSON Schema）：\n${JSON.stringify(f.parameters || {})}`;
  }).join('\n\n');

  return [
    '',
    '# 你手上的工具',
    '',
    list,
    '',
    '## 怎么用',
    '',
    '要用工具的时候，**这一轮只输出下面这一段**，前后不要有别的话：',
    '',
    FENCE + 'tool_call',
    '{"name": "工具名", "arguments": {…}}',
    FENCE,
    '',
    '一次要调好几个就写好几段，一段一个。',
    '结果会以「工具结果」的形式回到对话里，然后你接着往下说。',
    '不用工具就正常说话，别提这段格式，也别跟她解释你有哪些工具。'
  ].join('\n');
}

/** OpenAI 的 content 可能是字符串，也可能是一串 part（带图、带 cache_control） */
function partsOf(content) {
  if (content == null) return { text: '', images: [] };
  if (typeof content === 'string') return { text: content, images: [] };
  if (!Array.isArray(content)) return { text: String(content), images: [] };
  let text = '';
  const images = [];
  for (const p of content) {
    if (!p) continue;
    if (p.type === 'text' && typeof p.text === 'string') text += (text ? '\n' : '') + p.text;
    else if (p.type === 'image_url' && p.image_url && p.image_url.url) images.push(p.image_url.url);
  }
  return { text, images };
}

/** data:image/…;base64,… → 落成一个临时文件，把路径给他，让他自己去 Read */
function dumpImage(url, bag) {
  const m = /^data:image\/([a-zA-Z0-9.+-]+);base64,(.*)$/.exec(url || '');
  if (!m) return null;
  const ext = m[1].toLowerCase() === 'jpeg' ? 'jpg' : m[1].toLowerCase();
  const file = path.join(TMP, `img-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`);
  try {
    fs.writeFileSync(file, Buffer.from(m[2], 'base64'));
    bag.push(file);
    return file;
  } catch (e) {
    return null;
  }
}

/**
 * 把 OpenAI 那串 messages 摊成一段给 claude -p 的正文。
 *
 * system 单独拎出来（走 --system-prompt-file，太长了塞不进命令行参数）。
 * assistant 的 tool_calls、role=tool 的结果都转成看得懂的文字，
 * 不然他接不上自己上一轮干了什么。
 */
function render(messages, imgBag) {
  const systemParts = [];
  const lines = [];

  for (const m of messages || []) {
    const { text, images } = partsOf(m.content);
    const role = m.role;

    if (role === 'system') {
      if (text) systemParts.push(text);
      continue;
    }

    if (role === 'tool') {
      lines.push('<工具结果>');
      lines.push(text || '(空)');
      lines.push('</工具结果>');
      continue;
    }

    if (role === 'assistant') {
      const calls = Array.isArray(m.tool_calls) ? m.tool_calls : [];
      lines.push('<你>');
      if (text) lines.push(text);
      for (const c of calls) {
        const f = c.function || {};
        lines.push(`（你调用了工具 ${f.name}，参数 ${f.arguments || '{}'}）`);
      }
      lines.push('</你>');
      continue;
    }

    // user
    lines.push('<她>');
    if (text) lines.push(text);
    for (const u of images) {
      const file = dumpImage(u, imgBag);
      if (file) lines.push(`（她发了一张图，在这个路径：${file} —— 用 Read 工具看一眼再回。）`);
      else lines.push('（她发了一张图，但这边没接住。）');
    }
    lines.push('</她>');
  }

  lines.push('');
  lines.push('现在轮到你说话。**只说你这一轮要说的话**，不要带 <你> 这种标签，也不要复述上面的记录。');

  return { system: systemParts.join('\n\n'), prompt: lines.join('\n') };
}

// ────────────────────────────── 挑模型

/**
 * 把她选的那个名字归成 claude 认得的档位。
 *
 * ⚠️ **`-code` 后缀要原样带回去。**
 * 上一版这儿把 `opus-code` 直接归成了 `opus`——
 * 后缀在走到分流那一步之前就没了，
 * 于是工坐区那一档**永远走不到**，而且不报错、很难查。
 */
function pickModel(name) {
  const raw = String(name || '').toLowerCase();
  const code = /-code$/.test(raw) ? '-code' : '';
  const s = raw.replace(/-code$/, '');
  if (s.includes('fable')) return 'fable' + code;
  if (s.includes('opus')) return 'opus' + code;
  if (s.includes('sonnet')) return 'sonnet' + code;
  if (s.includes('haiku')) return 'haiku' + code;
  // 认不出型号但带了 `-code`：档位交给 claude 自己默认，
  // 但**那一档还是要走工坐区**。
  return code ? code : null;
}

// ────────────────────────────── 跑一次 claude

let running = 0;
const queue = [];

function slot() {
  return new Promise(resolve => {
    if (running < MAX_CONCURRENT) { running++; resolve(); }
    else queue.push(resolve);
  });
}

function freeSlot() {
  const next = queue.shift();
  if (next) next();
  else running--;
}

/**
 * @param onText 每收到一小段正文就回调一次
 * @returns {Promise<{text:string, usage:object|null, error:string|null,
 *                    limit:object|null, cost:number|null}>}
 */
function runClaude({ system, prompt, model, needsRead }, onText) {
  return new Promise(resolve => {
    const sysFile = path.join(TMP, `sys-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.txt`);
    fs.writeFileSync(sysFile, system, 'utf8');

    // 这一轮是谁？**模型名带 `-code` 后缀 = 工坐区，不带 = 阿晏。**
    //
    // 她定的：「工作区不是阿晏，工作区就是 claude 本身，
    // 跟阿晏没关系。所以可以带上上下文。」
    //
    // 两边要的东西正好相反：
    // ・絮语（阿晏）—— 不要这台电脑的 CLAUDE.md、不要工具。
    //   带上了的话，她在手机上等来的是一个跟她讨论 Swift 编译错误的人。
    // ・工坐（Claude Code）—— 全部都要：项目目录、CLAUDE.md、技能、工具。
    //   没有这些它就只是个会聊天的，帮不上忙。
    const isCode = /-code$/i.test(model || '');
    // 只剩一个 `-code` 的话（型号没认出来）就不传 --model，
    // 交给 claude 自己的默认——传个空字串过去它会报错。
    const realModel = (model || '').replace(/-code$/i, '');

    const args = [
      '-p',
      '--output-format', 'stream-json',
      '--include-partial-messages',
      '--verbose',
      '--no-session-persistence'
    ];
    if (realModel) args.push('--model', realModel);

    if (isCode) {
      // 工坐区：就是平时那个 Claude Code。
      //
      // ⚠️ **不加 `--safe-mode`、不加 `--system-prompt-file`。**
      // 加了就把仓库里那份 CLAUDE.md 和它自己的人格盖掉了，
      // 而那正是她要的东西。
      //
      // ⚠️ 权限给的是 `acceptEdits`，不是全放开：
      // 能读能写能改代码，**但跑命令还是要问**。
      // 她人在手机上，看不见终端里弹的确认——
      // 全放开的话等于没人看着的时候什么都能跑。
      args.push('--permission-mode', 'acceptEdits');
      args.push('--add-dir', TMP);      // 她发的图也得能看
      // ⚠️ App 那边传来的系统提示（`system`）**在这一档是故意不用的**。
      // 不是漏了：用了就把仓库里那份 CLAUDE.md 盖掉了。
      // 工坐区要的就是它在终端里本来的样子。
    } else {
      // 阿晏：只是他，不是这台电脑上的编码助手
      args.push('--safe-mode');
      args.push('--system-prompt-file', sysFile);
      if (needsRead) {
        // 只为了看那张图。**变长参数要放在最后一个位置之前**，
        // 后面再跟别的 flag，不然它会把后面的东西当成工具名吃掉。
        args.push('--add-dir', TMP);
        args.push('--allowedTools', 'Read');
        args.push('--tools', 'Read');
      } else {
        args.push('--tools', '');
      }
    }

    // 指到一个 .js 上的话，用当前这个 node 去跑它
    // （有的装法给的是 cli.js 而不是可执行文件；测试的时候也走这条）
    const isJS = CLAUDE.cmd.toLowerCase().endsWith('.js');
    const child = spawn(isJS ? process.execPath : CLAUDE.cmd,
                        isJS ? [CLAUDE.cmd].concat(args) : args, {
      // 工坐区在项目目录里跑（不然它看不见任何代码），
      // 阿晏那边继续关在临时目录里。
      cwd: isCode ? WORKSPACE : TMP,
      shell: CLAUDE.shell,
      windowsHide: true,
      env: process.env
    });

    // 正文走 stdin。**不当命令行参数传**——
    // 一整段对话史几万字，Windows 的命令行放不下（上限三万多字符）。
    try {
      child.stdin.write(prompt, 'utf8');
      child.stdin.end();
    } catch (e) {
      error = '写不进去：' + e.message;
    }
    child.stdin.on('error', () => {});

    let text = '';
    let usage = null;
    let limit = null;      // 额度（rate_limit_event）
    let cost = null;       // 这一轮折合多少美金（claude 自己算的）
    let error = null;
    let buf = '';
    let done = false;

    const timer = setTimeout(() => {
      error = error || '等太久了，这一轮掐掉了。';
      try { child.kill(); } catch (e) {}
    }, TIMEOUT_MS);

    function finish() {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { fs.unlinkSync(sysFile); } catch (e) {}
      resolve({ text, usage, error, limit, cost });
    }

    child.stdout.on('data', chunk => {
      buf += chunk.toString('utf8');
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        let ev;
        try { ev = JSON.parse(line); } catch (e) { continue; }

        // 逐字：partial 事件里带 text_delta
        if (ev.type === 'stream_event' && ev.event && ev.event.type === 'content_block_delta') {
          const d = ev.event.delta || {};
          if (d.type === 'text_delta' && d.text) { text += d.text; onText(d.text); }
          continue;
        }

        // 整块：没开 partial 或者中途丢了的时候兜底。
        // **只在这一块的内容还没逐字收到过的时候才补**，不然会重一遍。
        if (ev.type === 'assistant' && ev.message) {
          if (ev.error) error = error || String(ev.error);
          for (const b of ev.message.content || []) {
            if (b.type === 'text' && b.text && !text.includes(b.text)) {
              text += b.text;
              onText(b.text);
            }
          }
          continue;
        }

        // 额度。**claude 自己会报，不用另外去查。**
        //
        // 她问「五小时额度周额度能不能搬过来」，
        // 我一开始说搬不过来——**那是错的**。
        // stream-json 的输出里就有 `rate_limit_event`：
        //   { status, resetsAt, rateLimitType: 'five_hour', utilization: 0.99, ... }
        //
        // ⚠️ 不要拿它去改 usage：额度是「还剩多少」，
        // usage 是「这一轮花了多少 token」，两回事。
        if (ev.type === 'rate_limit_event' && ev.rate_limit_info) {
          limit = ev.rate_limit_info;
        }
        if (ev.type === 'result') {
          if (ev.usage) usage = ev.usage;
          if (typeof ev.total_cost_usd === 'number') cost = ev.total_cost_usd;
          if (ev.is_error) error = error || String(ev.result || '这一轮出错了');
          continue;
        }
      }
    });

    child.stderr.on('data', d => {
      const s = d.toString('utf8').trim();
      if (s) console.error('[claude]', s.slice(0, 400));
    });

    child.on('error', e => {
      error = `起不来 claude：${e.message}。是不是没装，或者不在 PATH 里？`;
      finish();
    });
    child.on('close', () => finish());
  });
}

// ────────────────────────────── 把 tool_call 抠出来

const TOOL_FENCE = FENCE + 'tool_call';

/** 正文里能看见的部分（fence 之前那一段） */
function visiblePart(raw) {
  const i = raw.indexOf(TOOL_FENCE);
  return i >= 0 ? raw.slice(0, i) : raw;
}

/** 尾巴上可能是半个 fence，先扣住别发出去，不然她会看见半截 ``` */
function holdBack(s) {
  const max = Math.min(TOOL_FENCE.length, s.length);
  for (let k = max; k > 0; k--) {
    if (TOOL_FENCE.startsWith(s.slice(s.length - k))) return s.slice(0, s.length - k);
  }
  return s;
}

function parseToolCalls(raw) {
  const out = [];
  const re = /```tool_call\s*([\s\S]*?)```/g;
  let m;
  while ((m = re.exec(raw)) !== null) {
    let obj = null;
    try { obj = JSON.parse(m[1].trim()); } catch (e) { obj = null; }
    if (!obj || !obj.name) continue;
    const args = obj.arguments === undefined ? {} : obj.arguments;
    out.push({
      id: 'call_' + Math.random().toString(36).slice(2, 12),
      type: 'function',
      function: {
        name: String(obj.name),
        arguments: typeof args === 'string' ? args : JSON.stringify(args)
      }
    });
  }
  return out;
}

// ────────────────────────────── HTTP

function sse(res, obj) {
  res.write('data: ' + JSON.stringify(obj) + '\n\n');
}

function chunkOf(id, model, delta, finish) {
  return {
    id,
    object: 'chat.completion.chunk',
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{ index: 0, delta: delta || {}, finish_reason: finish || null }]
  };
}

async function handleChat(req, res, body) {
  let payload;
  try { payload = JSON.parse(body); } catch (e) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { message: '请求体不是 JSON' } }));
    return;
  }

  const wantsStream = payload.stream !== false;
  const model = payload.model || 'claude-code';
  const id = 'chatcmpl-' + Math.random().toString(36).slice(2, 12);
  const imgBag = [];

  const { system, prompt } = render(payload.messages, imgBag);
  const fullSystem = system + toolProtocol(payload.tools);

  await slot();
  const startedAt = Date.now();
  console.log(`[${new Date().toLocaleTimeString()}] 一轮开始 · ${payload.messages ? payload.messages.length : 0} 条 · ${imgBag.length} 张图 · 工具 ${payload.tools ? payload.tools.length : 0} 个`);

  let raw = '';
  let sent = 0;

  if (wantsStream) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    sse(res, chunkOf(id, model, { role: 'assistant', content: '' }, null));
  }

  const onText = piece => {
    raw += piece;
    if (!wantsStream) return;
    const visible = holdBack(visiblePart(raw));
    if (visible.length > sent) {
      sse(res, chunkOf(id, model, { content: visible.slice(sent) }, null));
      sent = visible.length;
    }
  };

  let result;
  try {
    result = await runClaude({
      system: fullSystem,
      prompt,
      model: pickModel(model),
      needsRead: imgBag.length > 0
    }, onText);
  } finally {
    freeSlot();
    for (const f of imgBag) { try { fs.unlinkSync(f); } catch (e) {} }
  }

  const calls = parseToolCalls(raw);
  const finalText = visiblePart(raw).trim();
  const finish = calls.length ? 'tool_calls' : 'stop';
  const secs = ((Date.now() - startedAt) / 1000).toFixed(1);
  console.log(`   ↳ ${secs}s · ${finalText.length} 字${calls.length ? ' · 调了 ' + calls.length + ' 个工具' : ''}${result.error ? ' · 出错：' + result.error : ''}`);

  if (wantsStream) {
    // 收尾：把扣住的那点尾巴补上
    const visible = visiblePart(raw);
    if (visible.length > sent) {
      sse(res, chunkOf(id, model, { content: visible.slice(sent) }, null));
      sent = visible.length;
    }
    if (result.error && !finalText && !calls.length) {
      sse(res, chunkOf(id, model, { content: '（电脑上的 Claude Code 那头出错了：' + result.error + '）' }, null));
    }
    if (calls.length) {
      sse(res, chunkOf(id, model, { tool_calls: calls.map((c, i) => Object.assign({ index: i }, c)) }, null));
    }
    sse(res, chunkOf(id, model, {}, finish));
    if (result.usage || result.limit) {
      const tail = {
        id, object: 'chat.completion.chunk',
        created: Math.floor(Date.now() / 1000),
        model, choices: [], usage: result.usage || {}
      };
      // 额度搭在最后那一帧上。
      //
      // ⚠️ 放在 usage 旁边，**不混进 usage 里**：
      // usage 是「这一轮花了多少 token」，
      // 额度是「你这个窗口还剩多少」——两回事，混了就再也分不开。
      if (result.limit) tail.rate_limit = result.limit;
      if (typeof result.cost === 'number') tail.subscription_cost_usd = result.cost;
      sse(res, tail);
    }
    res.write('data: [DONE]\n\n');
    res.end();
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({
    id,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{
      index: 0,
      message: {
        role: 'assistant',
        content: finalText || (result.error ? '（出错了：' + result.error + '）' : ''),
        tool_calls: calls.length ? calls : undefined
      },
      finish_reason: finish
    }],
    usage: result.usage || {},
    rate_limit: result.limit || undefined,
    subscription_cost_usd: typeof result.cost === 'number' ? result.cost : undefined
  }));
}

const server = http.createServer((req, res) => {
  const url = (req.url || '').split('?')[0];

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS'
    });
    res.end();
    return;
  }

  if (TOKEN) {
    const auth = req.headers['authorization'] || '';
    if (auth !== 'Bearer ' + TOKEN) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: '密钥不对' } }));
      return;
    }
  }

  // ───── 终端：真的在这台电脑上跑一条命令
  //
  // 她定的：「我需要终端可以敲命令，我的需求就是一个完整的
  // claudecode 搬到我的 app。」
  //
  // ⚠️⚠️ **这是整个桥里权限最大的一处。** 它等于把这台电脑的命令行
  // 摆在了局域网上。所以有一条硬规矩：
  //
  //   **没设 BRIDGE_TOKEN 就不开这个端点。**
  //
  // 不是「建议设」——是不设就没有。聊天那几个口子最坏是有人替你
  // 花点额度；这个口子最坏是有人把你的盘格了。两件事的严重程度
  // 差得太远，不该共用同一档默认。
  //
  // 另外两道：只在 WORKSPACE 里跑（不给改目录）；跑过两分钟就掐。
  if (req.method === 'POST' && (url === '/v1/shell' || url === '/shell')) {
    if (!TOKEN) {
      res.writeHead(403, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error:
        '终端没开。这个口子能在这台电脑上跑任意命令，' +
        '所以必须先设密钥：启动前 set BRIDGE_TOKEN=你自己编一串，' +
        '手机那边供应商的「密钥」栏填一样的。' }));
      return;
    }
    let body = '';
    req.on('data', d => { body += d; });
    req.on('end', () => {
      let cmd = '';
      try { cmd = String(JSON.parse(body || '{}').command || ''); } catch (e) {}
      cmd = cmd.trim();
      if (!cmd) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: '没给命令' }));
        return;
      }
      // 流式吐回去（ndjson）——跑个 build 要好几十秒，
      // 等完了才给的话她那边就是一屏空白。
      res.writeHead(200, {
        'Content-Type': 'application/x-ndjson; charset=utf-8',
        'Cache-Control': 'no-store',
        'Access-Control-Allow-Origin': '*'
      });
      const line = o => { try { res.write(JSON.stringify(o) + '\n'); } catch (e) {} };
      line({ type: 'start', cwd: WORKSPACE, command: cmd });

      const sh = IS_WIN ? 'cmd.exe' : '/bin/sh';
      const shArgs = IS_WIN ? ['/d', '/s', '/c', cmd] : ['-c', cmd];
      const child = spawn(sh, shArgs, { cwd: WORKSPACE, windowsHide: true });

      child.stdout.on('data', d => line({ type: 'out', text: d.toString('utf8') }));
      child.stderr.on('data', d => line({ type: 'err', text: d.toString('utf8') }));
      child.on('error', e => line({ type: 'err', text: String(e.message || e) }));

      // 跑太久就掐。卡死一个子进程在那儿，
      // 她那边只会看到一个永远转着的圈。
      const killer = setTimeout(() => {
        line({ type: 'err', text: '（跑了太久，停了）' });
        try { child.kill(); } catch (e) {}
      }, 120000);

      child.on('close', code => {
        clearTimeout(killer);
        line({ type: 'exit', code: code });
        res.end();
      });
    });
    return;
  }

  if (req.method === 'GET' && (url === '/v1/models' || url === '/models')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      object: 'list',
      // 带 `-code` 的那几个是**工坐区用的**：
      // 它们带工具、带 CLAUDE.md、在项目目录里跑。
      // 不带后缀的给絮语（阿晏）用，那边一个工具都没有。
      data: ['opus', 'sonnet', 'haiku', 'fable',
             'opus-code', 'sonnet-code', 'haiku-code'].map(m => ({
        id: m, object: 'model', owned_by: 'claude-code'
      }))
    }));
    return;
  }

  if (req.method === 'GET' && (url === '/' || url === '/health')) {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('桥是通的。接口填 http://<这台电脑的IP>:' + PORT + '/v1\n');
    return;
  }

  if (req.method === 'POST' && (url === '/v1/chat/completions' || url === '/chat/completions')) {
    let body = '';
    req.on('data', d => { body += d; });
    req.on('end', () => {
      handleChat(req, res, body).catch(e => {
        console.error('[桥]', e);
        if (!res.headersSent) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: String(e && e.message || e) } }));
        } else {
          try { res.end(); } catch (x) {}
        }
      });
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: { message: '没有这个路径：' + url } }));
});

function lanAddresses() {
  const out = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const n of nets[name] || []) {
      if (n.family === 'IPv4' && !n.internal) out.push(n.address);
    }
  }
  return out;
}

server.listen(PORT, '0.0.0.0', () => {
  const addrs = lanAddresses();
  console.log('');
  console.log('  Claude Code 桥起来了。');
  console.log('');
  if (addrs.length) {
    console.log('  手机跟这台电脑连同一个 WiFi，在栖里新增一个供应商：');
    for (const a of addrs) console.log('    接口地址   http://' + a + ':' + PORT + '/v1');
    console.log('    密钥       ' + (TOKEN ? '（跟 BRIDGE_TOKEN 一样）' : '留空'));
    console.log('');
    console.log('  模型分两档，别选错：');
    console.log('    絮语（阿晏）  opus / sonnet / haiku');
    console.log('                 —— 只是他。不碰你电脑上任何东西。');
    console.log('    工坐（写代码）opus-code / sonnet-code');
    console.log('                 —— 就是终端里那个 Claude Code。');
    console.log('                 带 CLAUDE.md、带工具，能读能改：');
    console.log('                 ' + WORKSPACE);
    console.log('                 跑命令还是会问（acceptEdits）。');
  } else {
    console.log('  没找到局域网地址，检查一下 WiFi 是不是连着。');
  }
  console.log('');
  console.log('  用的是：' + CLAUDE.cmd);
  console.log('  第一次用之前，先在这台电脑上单独跑一次：claude -p "说一个字：好"');
  console.log('  打出「Not logged in」的话先登录（记得挂梯子），登好了这个桥才有用。');
  console.log('');
  console.log('  这个窗口关掉桥就断了。手机上那个供应商会连不上——');
  console.log('  切回原来的供应商就还能聊。');
  console.log('');
});
