/*
 * 把电脑上的 Claude Code 摆到手机里：**真的那个 Claude Code**，
 * 会用工具、会改文件、会接着上一次的会话说。
 *
 * 跑起来：node bridge.js       （或者双击同目录的「启动新桥.bat」）
 * 手机那边：聊天页左边栏 → Code。
 *
 * 零依赖，只用 Node 自带的东西。Node 18 以上。
 *
 * ── 跟旁边那座旧桥（scripts/claude-bridge）的分工 ──
 *
 * 旧桥把 Claude Code 装成一个「供应商」：一轮一轮地问，
 * 工具是用文字约的（让他输出一段 JSON，桥再翻译），**他偶尔不照格式写**。
 *
 * 这座新桥走的是 Claude Code 自己的流式协议
 * （`--output-format stream-json`，也就是 Agent SDK 底下那一套）：
 * 工具是他真的在调，文件是他真的在改，每一步都以事件的形式流回手机。
 *
 * 两座可以同时开，端口不一样（旧 8787 / 新 8788）。
 * 只开新的也行——聊天页那个 Code 渠道只用新的。
 *
 * ── 会话是怎么接上的 ──
 *
 * 她问的：「那我可以选择窗口继续聊吗，就是我现在已有的窗口，还是得开启一个新的窗口。」
 * 答案是**可以接着已有的窗口**：`GET /v1/sessions` 把这台电脑上最近的会话列出来
 * （电脑上开过的那些窗口也在里面），手机上挑一个，之后每一轮都带 `--resume <id>`。
 * 不挑就是开一个新窗口，新窗口的 id 会在第一个事件里发回手机，下一轮自动接上。
 *
 * ⚠️ 电脑上那个窗口**同时开着**的时候别 resume 同一个会话——
 * 两头往同一份记录里写，记录会乱。挑之前先把电脑上那个窗口关了。
 *
 * ── 权限 ──
 *
 * 手机上没法弹「允许吗」，所以权限是**这一轮开始前就定好**的一档：
 *
 *     read    只让他看（Read/Grep/Glob/WebFetch…），不改东西
 *     edit    可以改文件（默认）
 *     all     全放开，命令也随便跑
 *
 * ⚠️⚠️ 这座桥等于把这台电脑摆在了局域网上，所以**没设 BRIDGE_TOKEN 就什么都不开**。
 */

'use strict';

const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PORT = parseInt(process.env.BRIDGE_PORT || '8788', 10);
const TOKEN = process.env.BRIDGE_TOKEN || '';
/* 一轮最多跑多久（毫秒）。真干活的一轮可以很长，给到 20 分钟。 */
const TIMEOUT_MS = parseInt(process.env.BRIDGE_TIMEOUT || '1200000', 10);
/* 默认在哪个目录里干活 */
const WORKSPACE = process.env.BRIDGE_WORKSPACE || path.resolve(__dirname, '..', '..');
/* 同时最多跑几轮 */
const MAX_RUNS = parseInt(process.env.BRIDGE_CONCURRENCY || '2', 10);

const IS_WIN = process.platform === 'win32';
const TMP = path.join(os.tmpdir(), 'qi-agent-bridge');
fs.mkdirSync(TMP, { recursive: true });

/**
 * 找 claude 本体。
 *
 * ⚠️ 要 `.exe` 不要 PATH 里那个 `claude.cmd`——走 .cmd 就得开 shell，
 * 而开了 shell 之后 Node 把参数直接拼成一行，提示里的空格引号会把命令行拆散。
 */
function resolveClaude() {
  if (process.env.BRIDGE_CLAUDE) return process.env.BRIDGE_CLAUDE;
  const guesses = [];
  if (IS_WIN && process.env.APPDATA) {
    guesses.push(path.join(process.env.APPDATA, 'npm', 'node_modules',
                           '@anthropic-ai', 'claude-code', 'bin', 'claude.exe'));
  }
  guesses.push(path.join(os.homedir(), '.local', 'bin', IS_WIN ? 'claude.exe' : 'claude'));
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (dir) guesses.push(path.join(dir, IS_WIN ? 'claude.exe' : 'claude'));
  }
  for (const g of guesses) {
    try { if (fs.statSync(g).isFile()) return g; } catch (_) {}
  }
  return IS_WIN ? 'claude.exe' : 'claude';
}

const CLAUDE = resolveClaude();

/* ────────────────────────── 会话清单 ────────────────────────── */

/** `~/.claude/projects` 里一个目录名对应一个工作目录，路径里的分隔符换成了 `-` */
function projectsDir() {
  return path.join(os.homedir(), '.claude', 'projects');
}

/**
 * 这台电脑上最近的会话。
 *
 * 一个 `.jsonl` 就是一个窗口的完整记录，文件名就是会话 id。
 * 只读**头几行和文件大小**：记录可以有几十兆，整份读进来会把桥卡死。
 */
function listSessions(limit) {
  const root = projectsDir();
  let dirs = [];
  try { dirs = fs.readdirSync(root); } catch (_) { return []; }
  const out = [];
  for (const d of dirs) {
    let files = [];
    try { files = fs.readdirSync(path.join(root, d)); } catch (_) { continue; }
    for (const f of files) {
      if (!f.endsWith('.jsonl')) continue;
      const p = path.join(root, d, f);
      let st;
      try { st = fs.statSync(p); } catch (_) { continue; }
      out.push({ id: f.replace(/\.jsonl$/, ''), path: p, dir: d,
                 at: st.mtimeMs, size: st.size });
    }
  }
  out.sort((a, b) => b.at - a.at);
  const top = out.slice(0, limit || 25);
  for (const s of top) {
    s.title = firstWords(s.path);
    s.cwd = cwdOf(s.path) || s.dir;
    delete s.path;
  }
  return top;
}

/**
 * 这个窗口叫什么。
 *
 * 记录开头有几行是元信息：`custom-title` 是她自己改的名字、`ai-title` 是自动起的，
 * **先认这两行**；都没有再退回去找头一句人话。
 */
function firstWords(file) {
  const lines = headLines(file, 40);
  let ai = '';
  for (const line of lines) {
    let j;
    try { j = JSON.parse(line); } catch (_) { continue; }
    if (j.type === 'custom-title' && j.customTitle) return String(j.customTitle).slice(0, 60);
    if (j.type === 'ai-title' && j.aiTitle && !ai) ai = String(j.aiTitle).slice(0, 60);
  }
  if (ai) return ai;
  for (const line of lines) {
    let j;
    try { j = JSON.parse(line); } catch (_) { continue; }
    if (j.type !== 'user') continue;
    const c = j.message && j.message.content;
    const text = typeof c === 'string' ? c
      : Array.isArray(c) ? c.filter(p => p.type === 'text').map(p => p.text).join(' ') : '';
    const t = (text || '').replace(/\s+/g, ' ').trim();
    /* 命令回显、粘进去的长文都不算 */
    if (t && !t.startsWith('<') && !t.startsWith('Caveat:')) return t.slice(0, 60);
  }
  return '（没有标题）';
}

function cwdOf(file) {
  /* ⚠️ 开头那几行是元信息，中间还夹着一条很长的文件快照，
     所以要往后多翻几行才碰得到带 `cwd` 的那一条 */
  for (const line of headLines(file, 200)) {
    try {
      const j = JSON.parse(line);
      if (j.cwd) return j.cwd;
    } catch (_) {}
  }
  return '';
}

/** 只读文件开头那一小块，按行切开 */
function headLines(file, n) {
  let buf;
  try {
    const fd = fs.openSync(file, 'r');
    buf = Buffer.alloc(512 * 1024);
    const read = fs.readSync(fd, buf, 0, buf.length, 0);
    fs.closeSync(fd);
    buf = buf.slice(0, read);
  } catch (_) { return []; }
  return buf.toString('utf8').split('\n').slice(0, n).filter(Boolean);
}

/* ────────────────────────── 跑一轮 ────────────────────────── */

const MODES = {
  read: ['--permission-mode', 'plan'],
  edit: ['--permission-mode', 'acceptEdits'],
  all: ['--dangerously-skip-permissions'],
};

let running = 0;
/** 手机那边可以叫停：会话 id → 正在跑的那个进程 */
const live = new Map();

/**
 * 起一个 claude，把它吐出来的事件翻译成手机认的 ndjson。
 *
 * 事件长这样（一行一个）：
 *
 *     {"t":"session","id":"…","cwd":"…","model":"…"}
 *     {"t":"text","delta":"他正在说的字"}
 *     {"t":"tool","name":"Edit","brief":"改 Qi/Core/…"}
 *     {"t":"tool_done","ok":true,"brief":"改好了"}
 *     {"t":"done","ms":12345,"cost":0.03}
 *     {"t":"error","msg":"…"}
 */
function run(opts, emit, onEnd) {
  const args = ['-p', '--output-format', 'stream-json', '--include-partial-messages',
                '--verbose'];
  args.push(...(MODES[opts.mode] || MODES.edit));
  if (opts.session) args.push('--resume', opts.session);
  if (opts.model) args.push('--model', opts.model);
  // 聊天页、工作页那边带过来的人设（阿晏是谁、她是谁），接在 Claude Code 自己那份后面
  if (opts.system) args.push('--append-system-prompt', opts.system);
  args.push(opts.text);

  const cwd = opts.cwd && fs.existsSync(opts.cwd) ? opts.cwd : WORKSPACE;
  const child = spawn(CLAUDE, args, {
    cwd,
    shell: false,
    windowsHide: true,
    env: Object.assign({}, process.env, { FORCE_COLOR: '0' }),
  });

  running += 1;
  let sid = opts.session || '';
  let told = false;
  let rest = '';
  let stderr = '';
  let ended = false;

  const timer = setTimeout(() => {
    emit({ t: 'error', msg: '这一轮跑了太久，停了。' });
    try { child.kill(); } catch (_) {}
  }, TIMEOUT_MS);

  function finish(why) {
    if (ended) return;
    ended = true;
    clearTimeout(timer);
    running -= 1;
    if (sid) live.delete(sid);
    onEnd(why);
  }

  child.stdout.on('data', (b) => {
    rest += b.toString('utf8');
    let at;
    while ((at = rest.indexOf('\n')) >= 0) {
      const line = rest.slice(0, at).trim();
      rest = rest.slice(at + 1);
      if (!line) continue;
      let j;
      try { j = JSON.parse(line); } catch (_) { continue; }
      /* ⚠️ 接着老会话那一轮也要发一次：手机那边要拿这个 id 记住「这一轮在哪个窗口里」，
         而且 claude 有时候会在 resume 的时候另开一个 id（分叉），发了她才跟得上 */
      if (j.session_id && (j.session_id !== sid || !told)) {
        sid = j.session_id;
        told = true;
        live.set(sid, child);
        emit({ t: 'session', id: sid, cwd: j.cwd || cwd, model: j.model || '' });
      }
      translate(j, emit);
    }
  });

  child.stderr.on('data', (b) => { stderr += b.toString('utf8').slice(0, 4000); });

  child.on('error', (e) => {
    emit({ t: 'error', msg: '起不来 claude：' + e.message });
    finish('spawn');
  });

  child.on('close', (code) => {
    if (code && code !== 0) {
      emit({ t: 'error', msg: '退出码 ' + code + (stderr ? '：' + stderr.trim().slice(0, 500) : '') });
    }
    finish('close');
  });

  return child;
}

/** 一条 claude 事件 → 一条手机认的事件 */
function translate(j, emit) {
  if (j.type === 'stream_event' && j.event) {
    const e = j.event;
    if (e.type === 'content_block_delta' && e.delta) {
      if (e.delta.type === 'text_delta' && e.delta.text) {
        emit({ t: 'text', delta: e.delta.text });
      } else if (e.delta.type === 'thinking_delta' && e.delta.thinking) {
        emit({ t: 'think', delta: e.delta.thinking });
      }
    }
    return;
  }
  if (j.type === 'assistant' && j.message && Array.isArray(j.message.content)) {
    for (const p of j.message.content) {
      if (p.type === 'tool_use') {
        emit({ t: 'tool', id: p.id, name: p.name, brief: briefOf(p.name, p.input) });
      }
    }
    return;
  }
  if (j.type === 'user' && j.message && Array.isArray(j.message.content)) {
    for (const p of j.message.content) {
      if (p.type === 'tool_result') {
        emit({ t: 'tool_done', id: p.tool_use_id, ok: !p.is_error,
               brief: resultBrief(p.content) });
      }
    }
    return;
  }
  if (j.type === 'result') {
    if (j.is_error) emit({ t: 'error', msg: String(j.result || '出错了').slice(0, 800) });
    emit({ t: 'done', ms: j.duration_ms || 0, cost: j.total_cost_usd || 0 });
  }
}

/** 工具那一行给她看什么：一眼看出他在动哪个文件、跑哪条命令 */
function briefOf(name, input) {
  const i = input || {};
  const one = (s) => String(s || '').replace(/\s+/g, ' ').trim().slice(0, 120);
  switch (name) {
    case 'Bash': case 'PowerShell': return one(i.command);
    case 'Read': case 'Edit': case 'Write': case 'NotebookEdit': return one(i.file_path);
    case 'Grep': return one(i.pattern) + (i.path ? '  在 ' + one(i.path) : '');
    case 'Glob': return one(i.pattern);
    case 'WebFetch': case 'WebSearch': return one(i.url || i.query);
    case 'Task': case 'Agent': return one(i.description);
    case 'TodoWrite': return '记一下要做的事';
    default: return one(i.description || i.prompt || i.command || '');
  }
}

function resultBrief(content) {
  const text = typeof content === 'string' ? content
    : Array.isArray(content) ? content.filter(p => p.type === 'text').map(p => p.text).join('\n')
    : '';
  const t = String(text || '').trim();
  if (!t) return '';
  const lines = t.split('\n').filter(Boolean);
  return (lines[0] || '').slice(0, 160) + (lines.length > 1 ? ` …共 ${lines.length} 行` : '');
}

/* ────────────────────────── 端点 ────────────────────────── */

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8',
                        'Access-Control-Allow-Origin': '*' });
  res.end(body);
}

function readBody(req) {
  return new Promise((ok, no) => {
    let s = '';
    req.on('data', (b) => {
      s += b;
      if (s.length > 8e6) { no(new Error('这条太长了')); req.destroy(); }
    });
    req.on('end', () => ok(s));
    req.on('error', no);
  });
}

/* ────────────────────────── 当「供应商」用：聊天页、工作页 ──────────────────────────
 *
 * 她问的：「不能直接接到工作页和聊天页吗？」
 *
 * 能。这一段让新桥长得跟一个普通的 OpenAI 接口一样（`/v1/models`、`/v1/chat/completions`），
 * 在「设置 → 供应商」里加一条 `http://192.168.x.x:8788/v1`、密钥填 BRIDGE_TOKEN，
 * 聊天页和工作页就能像选模型一样选它。
 *
 * 跟旧桥当供应商的区别：
 *   · 工具是 Claude Code **自己的**（读文件、改文件、跑命令），他真的在调；
 *     每用一次，回复里会冒出一行「› Edit 某某文件」让她看见他在干什么
 *   · App 那边传过来的工具清单**不用**——Claude Code 不认那套协议
 *   · **会话接得上**：同一段对话（按第一句话认）第二轮开始走 `--resume`，
 *     只把她新说的那句递过去，不用每轮把整段历史重讲一遍
 *
 * 模型名：sonnet / opus / haiku 是「改文件」那一档；
 * 后面带 -all 的全放开（命令也随便跑），带 -read 的只看不动。
 */

const crypto = require('crypto');
const CHAT_MAP = path.join(TMP, 'chat-sessions.json');

function loadChatMap() {
  try { return JSON.parse(fs.readFileSync(CHAT_MAP, 'utf8')); } catch (_) { return {}; }
}
function saveChatMap(m) {
  try { fs.writeFileSync(CHAT_MAP, JSON.stringify(m)); } catch (_) {}
}

/** 一条消息里的字（OpenAI 那边 content 可能是字符串，也可能是一串 part） */
function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter(p => p && p.type === 'text').map(p => p.text || '').join('\n');
}

/** 图：落到临时目录，把路径告诉他，他自己用 Read 去看 */
function imagesOf(content) {
  if (!Array.isArray(content)) return [];
  const out = [];
  for (const p of content) {
    const u = p && p.type === 'image_url' && p.image_url && p.image_url.url;
    const m = typeof u === 'string' && u.match(/^data:image\/(\w+);base64,(.+)$/);
    if (!m) continue;
    const f = path.join(TMP, 'img-' + Date.now() + '-' + out.length + '.' + (m[1] === 'jpeg' ? 'jpg' : m[1]));
    try { fs.writeFileSync(f, Buffer.from(m[2], 'base64')); out.push(f); } catch (_) {}
  }
  return out;
}

function chatModel(id) {
  const s = String(id || 'sonnet');
  const mode = s.endsWith('-all') ? 'all' : s.endsWith('-read') ? 'read' : 'edit';
  const model = s.replace(/-(all|read)$/, '').replace(/^claude-code-?/, '') || 'sonnet';
  return { model, mode };
}

function sseWrite(res, obj) {
  try { res.write('data: ' + JSON.stringify(obj) + '\n\n'); } catch (_) {}
}

function chunkOf(id, model, delta, finish) {
  return {
    id, object: 'chat.completion.chunk', created: Math.floor(Date.now() / 1000), model,
    choices: [{ index: 0, delta: delta || {}, finish_reason: finish || null }],
  };
}

async function handleChat(req, res) {
  let body;
  try { body = JSON.parse((await readBody(req)) || '{}'); }
  catch (e) { return send(res, 400, { error: { message: '请求体不是 JSON' } }); }
  const msgs = Array.isArray(body.messages) ? body.messages : [];
  const users = msgs.filter(m => m.role === 'user');
  if (!users.length) return send(res, 400, { error: { message: '没有她说的话' } });
  if (running >= MAX_RUNS) {
    return send(res, 429, { error: { message: '这台电脑上已经有 ' + running + ' 轮在跑了，等一会儿。' } });
  }

  const { model, mode } = chatModel(body.model);
  const system = msgs.filter(m => m.role === 'system').map(m => textOf(m.content)).join('\n\n');
  const last = users[users.length - 1];

  // 这段对话是哪一段：按**第一句话 + 模型那一档**认。同一段对话每一轮第一句都一样
  const key = crypto.createHash('sha1')
    .update(textOf(users[0].content).slice(0, 2000) + '|' + mode).digest('hex');
  const map = loadChatMap();
  // App 那边钉了电脑上哪个窗口（工作区上面那一栏挑的）就接着那个；
  // 没钉就按「同一段对话」自己认
  const pinned = typeof body.claude_session === 'string' ? body.claude_session.trim() : '';
  if (pinned && map[key] !== pinned) { map[key] = pinned; saveChatMap(map); }
  const resume = pinned || map[key] || '';

  let text = textOf(last.content);
  const imgs = imagesOf(last.content);
  if (imgs.length) text += '\n\n（她发了图，存在这几个路径，用 Read 看：' + imgs.join('、') + '）';
  // 第一次接这段对话、而前面已经聊过几轮（比如她中途换到这个供应商）：
  // 把前面的对话压成一段递过去，不然他什么都不知道
  if (!resume && msgs.length > 2) {
    const before = msgs.slice(0, msgs.lastIndexOf(last))
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => (m.role === 'user' ? '她：' : '你：') + textOf(m.content).slice(0, 1500))
      .join('\n');
    if (before.trim()) text = '（前面的对话）\n' + before + '\n\n（她现在说）\n' + text;
  }

  const stream = body.stream !== false;
  const id = 'chatcmpl-' + Date.now();
  if (stream) {
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8',
                         'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });
    sseWrite(res, chunkOf(id, model, { role: 'assistant', content: '' }));
  }
  let full = '';
  let lastWasTool = false;
  const put = (s) => {
    full += s;
    if (stream) sseWrite(res, chunkOf(id, model, { content: s }));
  };

  const started = Date.now();
  console.log(new Date().toLocaleTimeString() + '  [聊天] ' + (resume ? '接着 ' + resume.slice(0, 8) : '新会话') +
              ' · ' + mode + ' · ' + text.slice(0, 40).replace(/\s+/g, ' '));

  const child = run({ text, session: resume, mode, model, system },
    (e) => {
      if (e.t === 'session' && e.id && map[key] !== e.id) { map[key] = e.id; saveChatMap(map); }
      else if (e.t === 'text') {
        if (lastWasTool) { put('\n'); lastWasTool = false; }
        put(e.delta);
      } else if (e.t === 'tool') {
        // 他动了什么，一行摆出来
        put((full && !full.endsWith('\n') ? '\n' : '') + '› ' + e.name + (e.brief ? '　' + e.brief : '') + '\n');
        lastWasTool = true;
      } else if (e.t === 'tool_done' && !e.ok) {
        put('  ✗ ' + (e.brief || '没成') + '\n');
      } else if (e.t === 'error') {
        put('\n（桥：' + e.msg + '）');
      }
    },
    (why) => {
      console.log('  这一轮完了（' + why + '）' + Math.round((Date.now() - started) / 1000) + ' 秒');
      if (stream) {
        sseWrite(res, chunkOf(id, model, {}, 'stop'));
        try { res.write('data: [DONE]\n\n'); res.end(); } catch (_) {}
      } else {
        send(res, 200, {
          id, object: 'chat.completion', created: Math.floor(Date.now() / 1000), model,
          choices: [{ index: 0, message: { role: 'assistant', content: full }, finish_reason: 'stop' }],
        });
      }
    });
  req.on('close', () => { if (!res.writableEnded) { try { child.kill(); } catch (_) {} } });
}

/** 终端那一页的命令口（跟旧桥同一个协议，ndjson 流回来） */
async function handleShell(req, res) {
  let cmd = '';
  try { cmd = String(JSON.parse((await readBody(req)) || '{}').command || '').trim(); } catch (_) {}
  if (!cmd) return send(res, 400, { error: '没给命令' });
  res.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store' });
  const line = (o) => { try { res.write(JSON.stringify(o) + '\n'); } catch (_) {} };
  line({ type: 'start', cwd: WORKSPACE, command: cmd });
  const sh = IS_WIN ? 'cmd.exe' : '/bin/sh';
  const child = spawn(sh, IS_WIN ? ['/d', '/s', '/c', cmd] : ['-c', cmd], { cwd: WORKSPACE, windowsHide: true });
  child.stdout.on('data', d => line({ type: 'out', text: d.toString('utf8') }));
  child.stderr.on('data', d => line({ type: 'err', text: d.toString('utf8') }));
  child.on('error', e => line({ type: 'err', text: String(e.message || e) }));
  const killer = setTimeout(() => { line({ type: 'err', text: '（跑了太久，停了）' }); try { child.kill(); } catch (_) {} }, 120000);
  child.on('close', code => { clearTimeout(killer); line({ type: 'exit', code }); try { res.end(); } catch (_) {} });
}

const server = http.createServer(async (req, res) => {
  const url = (req.url || '').split('?')[0].replace(/\/+$/, '') || '/';
  const query = new URL(req.url || '/', 'http://x').searchParams;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*',
                         'Access-Control-Allow-Headers': '*',
                         'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' });
    return res.end();
  }

  if (url === '/' || url === '/v1') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('新桥是通的。\n'
      + '· 聊天页左边栏 → Code → 接法：填 http://<这台电脑 192.168 开头的地址>:' + PORT + '\n'
      + '· 当供应商用（聊天页、工作页）：设置 → 供应商，地址填 http://<同上>:' + PORT + '/v1，密钥填 BRIDGE_TOKEN\n');
  }

  /* ⚠️ 除了上面那句「通了」，**所有端点都要密钥**——
     这座桥能在这台电脑上改文件、跑命令。 */
  if (!TOKEN) {
    return send(res, 403, { error: '这座桥没设密钥，所以什么都不开。'
      + '启动前先 set BRIDGE_TOKEN=你自己编一串（或者用「启动新桥.bat」，它会问你）。' });
  }
  const auth = req.headers.authorization || '';
  if (auth !== 'Bearer ' + TOKEN) {
    return send(res, 401, { error: '密钥不对。手机那边填的要跟电脑上 BRIDGE_TOKEN 一模一样。' });
  }

  if (req.method === 'GET' && (url === '/v1/models' || url === '/models')) {
    return send(res, 200, { object: 'list', data:
      ['sonnet', 'opus', 'haiku', 'sonnet-all', 'opus-all', 'sonnet-read']
        .map(id => ({ id, object: 'model', owned_by: 'claude-code' })) });
  }

  if (req.method === 'POST' && (url === '/v1/chat/completions' || url === '/chat/completions')) {
    return handleChat(req, res);
  }

  if (req.method === 'POST' && (url === '/v1/shell' || url === '/shell')) {
    return handleShell(req, res);
  }

  if (req.method === 'GET' && url === '/v1/sessions') {
    return send(res, 200, { workspace: WORKSPACE,
                            sessions: listSessions(parseInt(query.get('limit') || '25', 10)) });
  }

  if (req.method === 'POST' && url === '/v1/interrupt') {
    const body = JSON.parse((await readBody(req)) || '{}');
    const child = live.get(body.session);
    if (child) { try { child.kill(); } catch (_) {} return send(res, 200, { ok: true }); }
    return send(res, 200, { ok: false, note: '那一轮已经不在跑了' });
  }

  if (req.method === 'POST' && url === '/v1/agent') {
    let body;
    try { body = JSON.parse((await readBody(req)) || '{}'); }
    catch (e) { return send(res, 400, { error: '这条消息不是 JSON' }); }
    if (!body.text || !String(body.text).trim()) {
      return send(res, 400, { error: '没有话' });
    }
    if (running >= MAX_RUNS) {
      return send(res, 429, { error: '这台电脑上已经有 ' + running + ' 轮在跑了，等一会儿。' });
    }

    res.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8',
                         'Cache-Control': 'no-cache',
                         'Access-Control-Allow-Origin': '*' });
    const emit = (o) => { try { res.write(JSON.stringify(o) + '\n'); } catch (_) {} };
    const started = Date.now();
    console.log(new Date().toLocaleTimeString() + '  一轮开始 ' +
                (body.session ? '接着 ' + body.session.slice(0, 8) : '新窗口') +
                ' · ' + (body.mode || 'edit') + ' · ' + String(body.text).slice(0, 40));
    const child = run({ text: String(body.text), session: body.session || '',
                        cwd: body.cwd || '', mode: body.mode || 'edit',
                        model: body.model || '' },
                      emit,
                      (why) => {
                        console.log('  这一轮完了（' + why + '）' +
                                    Math.round((Date.now() - started) / 1000) + ' 秒');
                        try { res.end(); } catch (_) {}
                      });
    /* 手机把这条连接掐了（退出页面、切后台太久）就顺手把进程也停了 */
    req.on('close', () => { try { child.kill(); } catch (_) {} });
    return;
  }

  return send(res, 404, { error: '没有这个端点：' + url });
});

/**
 * 手机在同一个 WiFi 下能连到的地址。
 *
 * ⚠️ 她两次都填了 198.18.0.1——那是梯子开 TUN 模式时的虚拟网卡，手机连不到；
 * 100.x 是 Tailscale 的，她不开 Tailscale 也连不到。两样都不打印了，
 * 只留家里路由器发的那几段（192.168 / 10 / 172.16~31）。
 */
function lanAddresses() {
  const out = [];
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const a of ifs[name] || []) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const [x, y] = a.address.split('.').map(Number);
      const home = x === 192 && y === 168 || x === 10 || (x === 172 && y >= 16 && y <= 31);
      if (home) out.push(a.address);
    }
  }
  return out;
}

server.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('  新桥起来了（真的 Claude Code，会用工具、能接着上次说）');
  console.log('  claude    ' + CLAUDE);
  console.log('  工作目录  ' + WORKSPACE);
  console.log('  密钥      ' + (TOKEN ? '已设（手机那边填一样的）' : '⚠️ 没设——什么都不会开'));
  const ips = lanAddresses();
  if (!ips.length) console.log('  ⚠️ 没找到家里 WiFi 的地址（192.168 开头那种）。电脑连上 WiFi 了吗？');
  for (const ip of ips) {
    console.log('  Code 页「接法」填   http://' + ip + ':' + PORT);
    console.log('  当供应商用地址填    http://' + ip + ':' + PORT + '/v1');
  }
  console.log('');
  console.log('  （只列手机能连的地址。198.18、100 开头的是梯子和 Tailscale 的，手机连不到。）');
  console.log('  关掉这个窗口桥就断了。');
  console.log('');
});
