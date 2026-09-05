import SwiftUI

/// 左侧边栏点进去以后打开的页面
struct SideMenuDestination: View {

    let item: SideMenuItem

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                content
            }
            // ⚠️ **这儿以前有个「关上」。已经删了，别再加回来。**
            //
            // 她说的：「删掉『关上』按钮 让文字居中 反正可以下滑关闭
            // 其他的没有功能的按钮也删掉。」
            //
            // 这一层是 sheet，下滑就关；那个按钮做的是系统已经做了的事，
            // 只是把标题挤得不居中、还在顶上多占一行。
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.id {
        case "footprint": FootprintView()
        case "favorite":   FavoritesView()
        case "moments":    MomentsView()
        case "quests":     QuestView()
        case "thoughts":   ThoughtPoolView()
        case "call":       CallHistoryView()
        case "fortune":    DivinationView()
        case "clawd":      ClawdHomeView()
        case "phone":      PhoneActivityView()
        case "music":      MusicLibraryView()
        case "pixel":      PixelStudioView()
        case "library":    BookshelfView()
        case "trash":      TrashView()
        case "memo":       MemoListView()
        case "promise":    PromiseView()
        case "mood":       MoodView()
        case "hobby":      HobbyView()
        case "clawdart":   ClawdStudioView()
        case "journal":    JournalView()
        case "sticker":   StickerLibraryView()
        case "games":     GamesView()
        case "terminal":  TerminalView()
        case "moment":    ThisMomentView()
        default:          FootprintView()
        }
    }
}
