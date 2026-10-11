# 小岛的画（栖岛自己画的一套）

生成器是唯一真相：改图改这里的脚本，别手修 PNG。出的图会写到这个文件夹（*_look.png 是放大对照图，不进 App）。

- `terrain.py`：地面的画法（草、花丛、路、沙、田、池塘、海岸）。App 里 `Qi/Views/More/IslandPaint.swift` 是同一套算法，两边一起改
- `sprites.py`：树、松树、灌木、石头（用 `.claude/skills/pixel-art` 的 pixelkit）
- `houses.py`：四种屋顶的小屋（直接画像素，`px2d.py`）
- `smalls.py`：花丛、郁金香、薰衣草、向日葵、篱笆、果箱、水桶、树桩、路灯、信箱、长椅、睡莲
- `girl.py`：她的小人（16×25，三个方向 × 站 / 左脚 / 右脚）→ 复制到 `Qi/Resources/Island/island_girl.png`
- `pack.py`：把景打成 `Qi/Resources/Island/island_art.png`，生成 `Qi/Core/IslandAtlas.swift`
- `compose.py`：整座岛拼一张预览（`island_own.png`）
- `shape.py`：岛的轮廓；`island_map.txt` / `island_decor.json`：初始地图和景（App 里 `WorldStore.starterMap` / `starterDecor` 照抄）

顺序：sprites.py → houses.py → smalls.py → girl.py → pack.py → compose.py
