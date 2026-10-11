import Foundation

// 由 scripts/island/pack.py 生成：栖岛自己画的景在 island_art.png 里的位置（像素，x y 宽 高）。
// 改图改生成脚本，别手改这里。

enum IslandAtlas {
    struct Rect { let x: Int; let y: Int; let w: Int; let h: Int }

    static let sprites: [String: Rect] = [
        "barrel": .init(x: 34, y: 210, w: 14, h: 16),
        "bench": .init(x: 94, y: 189, w: 32, h: 18),
        "bush": .init(x: 127, y: 189, w: 21, h: 16),
        "bush_berry": .init(x: 149, y: 189, w: 21, h: 16),
        "crate": .init(x: 17, y: 210, w: 16, h: 16),
        "fence": .init(x: 17, y: 189, w: 32, h: 20),
        "fence_v": .init(x: 113, y: 148, w: 10, h: 36),
        "fl_daisy": .init(x: 171, y: 189, w: 16, h: 16),
        "fl_pink": .init(x: 188, y: 189, w: 16, h: 16),
        "fl_yellow": .init(x: 205, y: 189, w: 16, h: 16),
        "fruit_small": .init(x: 208, y: 148, w: 23, h: 26),
        "greenhouse": .init(x: 57, y: 83, w: 66, h: 52),
        "house_blue": .init(x: 96, y: 0, w: 64, h: 64),
        "house_lilac": .init(x: 161, y: 0, w: 64, h: 64),
        "house_pink": .init(x: 31, y: 0, w: 64, h: 64),
        "house_sage": .init(x: 0, y: 83, w: 56, h: 64),
        "lamp": .init(x: 146, y: 148, w: 10, h: 30),
        "lavender": .init(x: 0, y: 210, w: 16, h: 16),
        "lighthouse": .init(x: 0, y: 0, w: 30, h: 82),
        "lily": .init(x: 85, y: 210, w: 16, h: 12),
        "mailbox": .init(x: 50, y: 189, w: 12, h: 20),
        "pine": .init(x: 124, y: 83, w: 32, h: 49),
        "pine_small": .init(x: 124, y: 148, w: 21, h: 32),
        "pink_small": .init(x: 183, y: 148, w: 24, h: 26),
        "rock": .init(x: 49, y: 210, w: 16, h: 14),
        "rock_small": .init(x: 102, y: 210, w: 10, h: 9),
        "rocks": .init(x: 63, y: 189, w: 30, h: 18),
        "signpost": .init(x: 232, y: 148, w: 22, h: 26),
        "stump": .init(x: 66, y: 210, w: 18, h: 14),
        "sunflower": .init(x: 0, y: 189, w: 16, h: 20),
        "telescope": .init(x: 157, y: 83, w: 48, h: 46),
        "tree_autumn": .init(x: 0, y: 148, w: 37, h: 40),
        "tree_fruit": .init(x: 77, y: 148, w: 35, h: 39),
        "tree_green": .init(x: 38, y: 148, w: 38, h: 39),
        "tree_pink": .init(x: 206, y: 83, w: 36, h: 40),
        "tree_small": .init(x: 157, y: 148, w: 25, h: 26),
        "tulip_peach": .init(x: 239, y: 189, w: 16, h: 16),
        "tulip_pink": .init(x: 222, y: 189, w: 16, h: 16)
    ]
}
