import SwiftUI
import UniformTypeIdentifiers
import QuickLook

/// 工坊里存文件的地方。放进来的文件按日期倒着排，
/// 能搜名字、能归到文件夹里，也能直接发到对话里去。
struct LibraryFile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var attachment: FileAttachment
    var folder: String = ""
    var addedAt: Date = Date()
}

@MainActor
final class FileLibraryStore: ObservableObject {

    static let shared = FileLibraryStore()

    @Published var files: [LibraryFile] = [] {
        didSet { if loaded { Storage.save(files, to: "library.json") } }
    }
    private var loaded = false

    /// 文件夹自己的名单。
    ///
    /// ⚠️ 以前没有这个东西，文件夹是从文件的归属**反推**出来的——
    /// 所以「新建文件夹」点确认之后什么也不会发生（一个空文件夹推不出来），
    /// 她看到的就是「点击确认后无反应，也没有创建新的文件夹」。
    /// 跟相册那个老 bug 一模一样，这儿是同一套解法：文件夹独立存一份。
    @Published var folderNames: [String] = [] {
        didSet { if loaded { Storage.save(folderNames, to: "library-folders.json") } }
    }

    init() {
        files = Storage.load([LibraryFile].self, from: "library.json") ?? []
        folderNames = Storage.load([String].self, from: "library-folders.json") ?? []
        loaded = true
    }

    func folders() -> [String] {
        // 自己建的 + 文件上带着的（老数据），并起来
        var names = Set(folderNames)
        names.formUnion(files.map { $0.folder })
        names.remove("")
        return names.sorted()
    }

    @discardableResult
    func createFolder(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !folders().contains(n) else { return false }
        folderNames.append(n)
        return true
    }

    /// 删文件夹。`keepFiles` 为真就只删壳子，文件退回未归类。
    func deleteFolder(_ name: String, keepFiles: Bool) {
        for f in files where f.folder == name {
            if keepFiles { move(f, to: "") } else { remove(f) }
        }
        folderNames.removeAll { $0 == name }
    }

    func renameFolder(from old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != old else { return }
        for f in files where f.folder == old { move(f, to: n) }
        folderNames.removeAll { $0 == old }
        if !folderNames.contains(n) { folderNames.append(n) }
    }

    func list(folder: String?, keyword: String) -> [LibraryFile] {
        var out = files
        if let folder { out = out.filter { $0.folder == folder } }
        if !keyword.isEmpty {
            out = out.filter { $0.attachment.displayName.localizedCaseInsensitiveContains(keyword) }
        }
        return out.sorted { $0.addedAt > $1.addedAt }
    }

    func add(_ attachment: FileAttachment, folder: String = "") {
        files.append(LibraryFile(attachment: attachment, folder: folder))
    }

    func remove(_ file: LibraryFile) {
        FileStore.delete(file.attachment)
        files.removeAll { $0.id == file.id }
    }

    func move(_ file: LibraryFile, to folder: String) {
        guard let i = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[i].folder = folder
    }
}

// MARK: - 界面

struct FileLibraryView: View {

    /// 挑中一个文件之后干什么（比如带到对话里）
    var onPick: ((FileAttachment) -> Void)? = nil

    @ObservedObject private var store = FileLibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var keyword = ""
    @State private var folder: String? = nil      // nil = 全部
    @State private var importing = false
    @State private var creatingFolder = false
    @State private var newFolder = ""
    @State private var moving: LibraryFile?
    @State private var previewURL: URL?

    private var list: [LibraryFile] { store.list(folder: folder, keyword: keyword) }

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 6) {
                Image(systemName: Icon.search)
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                TextField("搜文件名", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.app(14))
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                Button { importing = true } label: {
                    Image(systemName: Icon.add)
                        .font(.app(15))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassBackground(radius: 22, strength: app.settings.glassOpacity * 0.9)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("全部", active: folder == nil) { folder = nil }
                    ForEach(store.folders(), id: \.self) { name in
                        chip(name, active: folder == name) { folder = name }
                    }
                    Button {
                        newFolder = ""
                        creatingFolder = true
                    } label: {
                        Image(systemName: Icon.add)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if list.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.app(32, weight: .light))
                                .foregroundStyle(app.settings.accentColor.opacity(0.5))
                            Text(keyword.isEmpty ? "这里还空着" : "没找到")
                                .font(.app(13))
                                .foregroundStyle(Theme.textMuted(scheme))
                            if keyword.isEmpty {
                                Text("点右上角把文件放进来，按日期排好")
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                            }
                        }
                        .padding(.top, 70)
                    }

                    ForEach(groupedByDay, id: \.0) { day, items in
                        HStack {
                            Text(day)
                                .font(.app(11, weight: .medium))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)

                        ForEach(items) { file in
                            row(file)
                        }
                    }
                }
                .padding(.bottom, Layout.tabBarExpanded + 12)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for u in urls {
                    if let item = FileStore.importFile(from: u) {
                        store.add(item, folder: folder ?? "")
                    }
                }
            }
        }
        .alert("新建文件夹", isPresented: $creatingFolder) {
            TextField("起个名字", text: $newFolder)
            Button("取消", role: .cancel) {}
            Button("建好了") {
                let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                // **真的建出来**，不只是把当前视图切过去
                store.createFolder(name)
                folder = name
                newFolder = ""
            }
        } message: {
            Text("建好之后，放进来的文件会归到这个文件夹里。")
        }
        .confirmationDialog("挪到哪儿", isPresented: Binding(
            get: { moving != nil }, set: { if !$0 { moving = nil } }
        )) {
            ForEach(store.folders(), id: \.self) { name in
                Button(name) {
                    if let m = moving { store.move(m, to: name) }
                    moving = nil
                }
            }
            Button("取出") {
                if let m = moving { store.move(m, to: "") }
                moving = nil
            }
            Button("算了", role: .cancel) { moving = nil }
        }
        .quickLookPreview($previewURL)
    }

    private func chip(_ title: String, active: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.app(12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.textMain(scheme) : Theme.textMuted(scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active
                        ? app.settings.accentColor.opacity(0.28)
                        : Theme.softFillDeep)
                )
        }
        .buttonStyle(.plain)
    }

    /// 按天分组，最近的在上面
    private var groupedByDay: [(String, [LibraryFile])] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"

        var buckets: [Date: [LibraryFile]] = [:]
        for file in list {
            let day = cal.startOfDay(for: file.addedAt)
            buckets[day, default: []].append(file)
        }
        return buckets.keys.sorted(by: >).map { day in
            let label: String
            if cal.isDateInToday(day) { label = "今天" }
            else if cal.isDateInYesterday(day) { label = "昨天" }
            else { label = f.string(from: day) }
            return (label, buckets[day] ?? [])
        }
    }

    private func row(_ file: LibraryFile) -> some View {
        Button {
            if let onPick {
                onPick(file.attachment)
            } else {
                previewURL = FileStore.url(for: file.attachment)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: file.attachment.icon)
                    .font(.app(17))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.attachment.displayName)
                        .font(.app(14))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(file.attachment.sizeText)
                        if !file.folder.isEmpty {
                            Text("· \(file.folder)")
                        }
                        if file.attachment.unreadable {
                            Text("· 读不出文字")
                        }
                    }
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(padding: 0)
        .padding(.horizontal, 14)
        .contextMenu {
            Button {
                previewURL = FileStore.url(for: file.attachment)
            } label: {
                Label("打开", systemImage: "eye")
            }
            Button {
                moving = file
            } label: {
                Label("挪到别的文件夹", systemImage: "folder")
            }
            Button(role: .destructive) {
                store.remove(file)
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }
}
