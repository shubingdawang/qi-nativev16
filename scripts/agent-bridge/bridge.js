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
    return res.end('新桥是通的。聊天页左边栏 → Code。\n');
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

function lanAddresses() {
  const out = [];
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const a of ifs[name] || []) {
      if (a.family === 'IPv4' && !a.internal) out.push(a.address);
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
  for (const ip of lanAddresses()) {
    console.log('  接口地址  http://' + ip + ':' + PORT);
  }
  console.log('');
  console.log('  手机上：聊天页左边栏 → Code → 右上角填这个地址和密钥。');
  console.log('  关掉这个窗口桥就断了。');
  console.log('');
});
