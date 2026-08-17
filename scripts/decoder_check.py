"""数一遍：结构体里的字段，容错解码器是不是每个都补上了。

用法：python decoder_check.py Models.swift ChatMessage
"""
import io, re, sys

path, name = sys.argv[1], sys.argv[2]
s = io.open(path, encoding='utf-8').read()

m = re.search(r'\nstruct %s[^{]*\{\n(.*?)\n\}\n' % name, s, re.S)
decl = []
for line in m.group(1).split('\n'):
    mm = re.match(r'^    var (\w+)\s*[:=]', line)
    if mm and not line.rstrip().endswith('{'):
        decl.append(mm.group(1))

e = re.search(r'\nextension %s \{\n    init\(from decoder.*?\n    \}\n\}' % name, s, re.S)
asg = re.findall(r'^\s{8}(\w+) = ', e.group(0), re.M)

missing = [d for d in decl if d not in asg]
print(name, '字段', len(decl), '解码器', len(asg), missing or '全对上')
