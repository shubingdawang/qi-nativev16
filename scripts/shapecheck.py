# -*- coding: utf-8 -*-
"""看**结构**对不对，不只是看括号数得对不对。

## 为什么要有这个

v117 构建挂了两百多个错，根源只有两处，而且两处 `cmp.py` 都放行了：

  ① `Theme.swift` —— 删 `glassDim` 那次连着删掉了后面一大片
     （`fontScale`、`textMain`… 一直到 `struct GlassSurface: View {` 那一行）。
     于是 `GlassSurface` 的属性（`@Environment var scheme`、`radius`…）
     **全掉进了 `enum Theme` 里**。报出来是
     「non-static property 'scheme' declared inside an enum cannot have a wrapper」，
     以及全工程几百个「type 'Theme' has no member 'textMain'」。

  ② `AppState.swift` —— 批量替换 `tagStickerLibrary` 的正文时，
     **把它的函数头一起吃掉了**，代码接到了上面那个 `tagStickers` 里。
     报出来是「trailing closure passed to parameter of type 'Predicate<MediaItem>'」
     和「unexpected non-void return value in void function」——
     两条都指着现象，一条都没指着病根。

**两处的括号都是平衡的。** 少了一行 `struct X {`，同时也就少了它那个 `}`，
`cmp.py` 数出来照样是 0。

⚠️ 记一句：**括号平衡只保证「能解析」，不保证「解析成你想的那个形状」。**

## 这个脚本查什么

按缩进认顶层声明（`enum` / `struct` / `class` / `extension` / `protocol`），
然后查两样：

  · 顶层类型里有没有 `@Environment` / `@State` 这类**只能待在 View 里**的东西，
    而那个类型又是 `enum`（enum 根本不能有存储属性）
  · 顶层声明之间有没有大段**孤儿代码**（不属于任何类型的成员）

用法：python shapecheck.py 文件.swift ...
"""
import io, re, sys

# 顶层声明：不缩进的 enum/struct/class/extension/protocol
TOP = re.compile(r'^(public\s+|internal\s+|private\s+|fileprivate\s+)?'
                 r'(final\s+)?(enum|struct|class|extension|protocol)\s+(\w+)')
# ⚠️ 名字后面可能跟着泛型参数（`struct SettingsCard<Content: View>`），
# 所以只认名字本身，后面那一串不管。
# 只能待在 View / ObservableObject 里的包装器
VIEW_ONLY = re.compile(r'^\s*@(Environment|EnvironmentObject|State|StateObject|'
                       r'Binding|ObservedObject|FocusState|AppStorage|SceneStorage|'
                       r'GestureState|Namespace)\b')


def strip(src):
    """把字符串和注释里的花括号去掉，免得数错。"""
    out, i, n = [], 0, len(src)
    in_s = in_line = in_block = False
    esc = False
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if in_line:
            if c == '\n':
                in_line = False
                out.append(c)
            else:
                out.append(' ')
        elif in_block:
            if two == '*/':
                in_block = False
                out.append('  ')
                i += 2
                continue
            out.append('\n' if c == '\n' else ' ')
        elif in_s:
            out.append(' ')
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_s = False
        else:
            if two == '//':
                in_line = True
                out.append('  ')
                i += 2
                continue
            if two == '/*':
                in_block = True
                out.append('  ')
                i += 2
                continue
            if c == '"':
                in_s = True
                out.append(' ')
            else:
                out.append(c)
        i += 1
    return ''.join(out)


def check(path):
    raw = io.open(path, encoding='utf-8').read()
    clean = strip(raw).split('\n')
    lines = raw.split('\n')
    bad = []

    # 走一遍，记录每一行属于哪个顶层声明
    owner = [None] * len(lines)
    cur, depth = None, 0
    for i, cl in enumerate(clean):
        m = TOP.match(lines[i]) if depth == 0 else None
        if m:
            cur = (m.group(3), m.group(4), i + 1)
        owner[i] = cur
        depth += cl.count('{') - cl.count('}')
        if depth <= 0:
            depth = 0
            if cl.count('}') and cur:
                cur = None

    # ⚠️ `: Layout` 会被解析成**项目自己那个 `enum Layout`**（管标签栏高度的），
    # 不是 SwiftUI 的布局协议。报出来是
    # 「inheritance from non-protocol type 'Layout'」+ 一串 'Subviews' 找不到，
    # 看着像 SDK 出了问题，其实只是重名。写全名 `SwiftUI.Layout` 就好。
    for i, line in enumerate(lines):
        if re.match(r'^\s*(public\s+|private\s+)?struct\s+\w+\s*:\s*Layout\s*\{', line):
            bad.append((i + 1, '`: Layout` 要写成 `: SwiftUI.Layout`'
                               '——项目里另有一个 enum Layout'))

    for i, line in enumerate(lines):
        if not VIEW_ONLY.match(line):
            continue
        o = owner[i]
        if o and o[0] == 'enum':
            bad.append((i + 1, '在 enum %s 里（第 %d 行开始）出现了 %s'
                        % (o[1], o[2], line.strip()[:46])))
        # ⚠️ 「孤儿属性」那一条**关掉了**。
        #
        # 它误报太多（嵌套类型、`#if`、泛型约束写换行…都会中），
        # 而**一个总在报警的检查等于没有检查**——下次真出事也没人看。
        # 上面那一条（enum 里出现 View 属性）已经能拓住 v117 那两处事故了。
    return bad


total = 0
for p in sys.argv[1:]:
    for ln, why in check(p):
        print('BAD %s:%d  %s' % (p, ln, why))
        total += 1
print('--- %d 处形状不对' % total)
