"""把每个受控文件的修改时间设成「由内容决定」的一个固定值。

CI 每次都是新拉的代码，所有文件的修改时间都是「刚才」，
Swift 的增量编译据此认为全部改过，缓存等于白存。
按内容哈希给时间：内容没变 → 时间跟上次一模一样 → 不重编；内容变了 → 时间不同 → 重编。
"""
import os
import subprocess

out = subprocess.run(["git", "ls-files", "-s", "-z"], capture_output=True, check=True).stdout
n = 0
for rec in out.split(b"\0"):
    if not rec:
        continue
    meta, _, path = rec.partition(b"\t")
    parts = meta.split()
    if len(parts) < 2:
        continue
    blob = parts[1].decode()
    p = os.fsdecode(path)
    if not os.path.isfile(p):
        continue
    ts = 1_500_000_000 + int(blob[:8], 16) % 200_000_000
    os.utime(p, (ts, ts))
    n += 1
print("stamped", n, "files")
