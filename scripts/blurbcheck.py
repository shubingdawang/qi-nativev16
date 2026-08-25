"""对两张表：工具真的有哪些 vs ToolBlurb 里写了哪些。
漏了 → 那件工具在开关页上还是显示模型提示词。
多了 → 表里有个不存在的名字，纯垃圾。
（加新工具要记得来这儿补一条，跟加家具要动五处是同一类事。）"""
import re, io

def names(path):
    src = io.open(path, encoding='utf-8').read()
    return set(re.findall(r'add\("([a-z_0-9]+)"', src))

real = names('Qi/Core/NativeTools.swift') | names('Qi/Core/MemoryTools.swift')

blurb_src = io.open('Qi/Core/ToolBlurb.swift', encoding='utf-8').read()
listed = set(re.findall(r'^\s*"([a-z_0-9]+)":', blurb_src, re.M))

missing = sorted(real - listed)
extra = sorted(listed - real)

print("工具总数 %d，表里写了 %d" % (len(real), len(listed)))
if missing:
    print("\n⚠️ 漏了 %d 个（会退回显示模型提示词）：" % len(missing))
    for n in missing:
        print("   ", n)
if extra:
    print("\n⚠️ 表里多了 %d 个不存在的名字：" % len(extra))
    for n in extra:
        print("   ", n)
if not missing and not extra:
    print("两张表对得上。")
