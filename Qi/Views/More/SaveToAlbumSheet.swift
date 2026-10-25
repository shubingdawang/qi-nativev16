import SwiftUI
import Photos

/// 把一张图存起来：存进「栖的相册」（App 里的相册，按文件夹）或者「手机相册」。
/// 跟手机相册一样：可以选一个已有的相册，也可以新建一个。存完把存到哪儿告诉调用方。
struct SaveToAlbumSheet: View {
    let image: UIImage
    let title: String
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var app: AppState
    @ObservedObject private var media = MediaStore.shared

    @State private var dest = 0              // 0 栖的相册，1 手机相册
    @State private var chosen: String = ""   // 选中的相册名（栖的相册）；"" = 未归类
    @State private var phoneAlbums: [PHAssetCollection] = []
    @State private var phoneChosen: String?  // 手机相册的 localIdentifier；nil = 不放进相册（只在「最近项目」）
    @State private var newName = ""
    @State private var creating = false
    @State private var denied = false
    @State private var saving = false

    private var accent: Color { app.settings.accentColor }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .frame(maxWidth: .infinity)

                    Picker("", selection: $dest) {
                        Text("栖的相册").tag(0)
                        Text("手机相册").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dest) { _, d in if d == 1 { loadPhone() } }

                    if dest == 0 { appList } else { phoneList }

                    // 新建相册
                    if creating {
                        HStack(spacing: 8) {
                            TextField("相册名字", text: $newName)
                                .font(.app(14))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.softFillDeep))
                            Button("建好") { createAlbum() }
                                .font(.app(13.5, weight: .semibold))
                                .foregroundStyle(accent)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button { creating = true } label: {
                            Label("新建相册", systemImage: "plus")
                                .font(.app(13.5))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("保存到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { save() }
                        .disabled(saving || (dest == 1 && denied))
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: 栖的相册

    private var appList: some View {
        VStack(spacing: 0) {
            pickRow("未归类", sub: "\(media.list("photo", folder: "").count) 张", on: chosen.isEmpty) { chosen = "" }
            ForEach(media.folders("photo"), id: \.self) { name in
                pickRow(name, sub: "\(media.list("photo", folder: name).count) 张", on: chosen == name) { chosen = name }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.softFill))
    }

    // MARK: 手机相册

    @ViewBuilder
    private var phoneList: some View {
        if denied {
            Text("没有相册权限。可以去系统设置 → 栖 → 照片里打开。")
                .font(.app(12.5))
                .foregroundStyle(Theme.textMuted(scheme))
        } else {
            VStack(spacing: 0) {
                pickRow("不放进相册", sub: "只存在「最近项目」里", on: phoneChosen == nil) { phoneChosen = nil }
                ForEach(phoneAlbums, id: \.localIdentifier) { c in
                    pickRow(c.localizedTitle ?? "相册", sub: "\(c.estimatedAssetCount == NSNotFound ? 0 : c.estimatedAssetCount) 张", on: phoneChosen == c.localIdentifier) { phoneChosen = c.localIdentifier }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.softFill))
        }
    }

    private func pickRow(_ name: String, sub: String, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.app(14.5)).foregroundStyle(Theme.textMain(scheme))
                    Text(sub).font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(on ? accent : Theme.textMuted(scheme).opacity(0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func loadPhone() {
        let fetch = {
            let r = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var out: [PHAssetCollection] = []
            r.enumerateObjects { c, _, _ in out.append(c) }
            phoneAlbums = out.sorted { ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "") }
        }
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: fetch()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                Task { @MainActor in if s == .authorized || s == .limited { fetch() } else { denied = true } }
            }
        default: denied = true
        }
    }

    private func createAlbum() {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if dest == 0 {
            media.createFolder("photo", name: n)
            chosen = n
            creating = false; newName = ""
        } else {
            var id: String?
            PHPhotoLibrary.shared().performChanges({
                id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: n).placeholderForCreatedAssetCollection.localIdentifier
            }) { ok, _ in
                Task { @MainActor in
                    creating = false; newName = ""
                    if ok { loadPhone(); phoneChosen = id }
                }
            }
        }
    }

    private func save() {
        saving = true
        if dest == 0 {
            media.add(image, kind: "photo", folder: chosen)
            onDone(chosen.isEmpty ? "栖的相册" : chosen)
            dismiss()
            return
        }
        let album = phoneAlbums.first { $0.localIdentifier == phoneChosen }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetChangeRequest.creationRequestForAsset(from: image)
            if let a = album, let ph = req.placeholderForCreatedAsset, let c = PHAssetCollectionChangeRequest(for: a) {
                c.addAssets([ph] as NSArray)
            }
        }) { ok, _ in
            Task { @MainActor in
                saving = false
                if ok { onDone(album?.localizedTitle ?? "手机相册"); dismiss() }
            }
        }
    }
}
