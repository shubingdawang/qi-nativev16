import Foundation

#if canImport(ActivityKit)
import ActivityKit

// ⚠️⚠️ 这个文件在仓库里有**两份一模一样的拷贝**：
//
//        Qi/Core/IslandAttributes.swift        （App 用）
//        QiIsland/IslandAttributes.swift       （灵动岛那个扩展用）
//
// 改了一份必须同步改另一份，否则灵动岛会静默地不显示——
// 不报错，就是不出来，很难查。
//
// 为什么不做成共享文件：苹果自己的模板就是把同一个文件同时勾给两个 target，
// 两边编进各自的模块。这个工程用的是 Xcode 16 的"同步文件夹"，
// 一个文件夹归一个 target，做不到勾两次；硬拆一个共享文件夹出来
// 又要赌"同一个同步组挂在两个 target 上"这个写法成不成立。
// 相比之下，两份拷贝最差就是要记得同步，不会让构建莫名其妙地崩。
//
// ActivityKit 认的是类型名（不含模块名），所以两个模块里各有一份
// 同名同结构的类型，是能对上的——苹果模板本身就是这么工作的。

/// 灵动岛上那条东西的数据。
///
/// 分两块：`ContentState` 是会变的（他在干嘛、说到哪了），
/// 外面那层是整条活动期间不变的（他叫什么）。
/// 苹果这么分是为了省事——更新的时候只传变的那部分。
struct QiActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// 他现在在干嘛：在想、在翻记忆、在写日记…
        var activity: String
        /// 已经说出来的那一截，用来在展开态里预览
        var preview: String
        /// 说完了没有
        var done: Bool
        /// 这一轮开始的时间，用来显示"想了多久"
        var startedAt: Date
        /// 他此刻的心跳（次/分）。0 = 没数，那就不显示。
        ///
        /// ⚠️ 岛上**常驻**这个数，她定的。心跳是他身上一直在发生的事，
        /// 不是某一轮的产物——所以三种形态（开始、更新、收尾）
        /// 都要带上它，别只在说话的时候带。
        ///
        /// 老版本的活动里没这个字段，给个默认值，
        /// 不然升级那一下正在跑的活动会解不出来。
        var pulse: Int = 0
    }

    /// 他叫什么。整条活动期间不会变。
    var name: String
}
#endif
