import Foundation

// 由 scripts/island/pack.py 生成：栖岛自己画的景在 island_art.png 里的位置（像素，x y 宽 高）。
// 改图改生成脚本，别手改这里。

enum IslandAtlas {
    struct Rect { let x: Int; let y: Int; let w: Int; let h: Int }

    static let sprites: [String: Rect] = [
        "barrel": .init(x: 85, y: 142, w: 14, h: 16),
        "bench": .init(x: 143, y: 115, w: 32, h: 18),
        "bush": .init(x: 176, y: 115, w: 21, h: 16),
        "bush_berry": .init(x: 198, y: 115, w: 21, h: 16),
        "crate": .init(x: 68, y: 142, w: 16, h: 16),
        "fence": .init(x: 66, y: 115, w: 32, h: 20),
        "fence_v": .init(x: 183, y: 65, w: 10, h: 36),
        "fl_daisy": .init(x: 220, y: 115, w: 16, h: 16),
        "fl_pink": .init(x: 237, y: 115, w: 16, h: 16),
        "fl_yellow": .init(x: 0, y: 142, w: 16, h: 16),
        "fruit_small": .init(x: 25, y: 115, w: 23, h: 26),
        "house_blue": .init(x: 65, y: 0, w: 64, h: 64),
        "house_lilac": .init(x: 130, y: 0, w: 64, h: 64),
        "house_pink": .init(x: 0, y: 0, w: 64, h: 64),
        "house_sage": .init(x: 195, y: 0, w: 56, h: 64),
        "lamp": .init(x: 216, y: 65, w: 10, h: 30),
        "lavender": .init(x: 51, y: 142, w: 16, h: 16),
        "lily": .init(x: 136, y: 142, w: 16, h: 12),
        "mailbox": .init(x: 99, y: 115, w: 12, h: 20),
        "pine": .init(x: 0, y: 65, w: 32, h: 49),
        "pine_small": .init(x: 194, y: 65, w: 21, h: 32),
        "pink_small": .init(x: 0, y: 115, w: 24, h: 26),
        "rock": .init(x: 100, y: 142, w: 16, h: 14),
        "rock_small": .init(x: 153, y: 142, w: 10, h: 9),
        "rocks": .init(x: 112, y: 115, w: 30, h: 18),
        "stump": .init(x: 117, y: 142, w: 18, h: 14),
        "sunflower": .init(x: 49, y: 115, w: 16, h: 20),
        "tree_autumn": .init(x: 70, y: 65, w: 37, h: 40),
        "tree_fruit": .init(x: 147, y: 65, w: 35, h: 39),
        "tree_green": .init(x: 108, y: 65, w: 38, h: 39),
        "tree_pink": .init(x: 33, y: 65, w: 36, h: 40),
        "tree_small": .init(x: 227, y: 65, w: 25, h: 26),
        "tulip_peach": .init(x: 34, y: 142, w: 16, h: 16),
        "tulip_pink": .init(x: 17, y: 142, w: 16, h: 16)
    ]
}
