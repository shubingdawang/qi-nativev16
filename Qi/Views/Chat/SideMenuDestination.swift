import SwiftUI

/// 左侧边栏点进去以后打开的页面
struct SideMenuDestination: View {

    let item: SideMenuItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                content
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.id {
        case "footprint": FootprintView()
        case "favorite":   FavoritesView()
        case "thoughts":   ThoughtPoolView()
        case "call":       CallHistoryView()
        case "fortune":    DivinationView()
        case "clawd":      ClawdHomeView()
        case "phone":      PhoneActivityView()
        case "music":      MusicLibraryView()
        case "pixel":      PixelStudioView()
        case "library":    LibraryView()
        case "memo":       MemoListView()
        case "mood":       MoodView()
        case "sticker":   StickerLibraryView()
        case "games":     GamesView()
        default:          FootprintView()
        }
    }
}
