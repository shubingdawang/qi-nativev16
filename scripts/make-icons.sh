#!/bin/bash
# ============================================================
# 把 AppIcons/ 里的图片变成 App 里可以选的桌面图标
#
# 用法：往仓库根目录的 AppIcons/ 文件夹里丢 png 就行，
# 文件名就是 App 里显示的名字（比如「阿晏.png」「夏天.png」）。
# 构建的时候这个脚本会自动跑，不用你做别的。
#
# iOS 的规矩是备用图标必须在打包时就存在，没法在手机上现加——
# 所以只能走这条路：图先进仓库，构建时变成图标。
# ============================================================
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/AppIcons"
DEST="$ROOT/Qi"
PLIST="$ROOT/Info.plist"

if [ ! -d "$SRC" ]; then
  echo "· 没有 AppIcons 文件夹，跳过"
  exit 0
fi

shopt -s nullglob
files=("$SRC"/*.png "$SRC"/*.PNG "$SRC"/*.jpg "$SRC"/*.jpeg)
if [ ${#files[@]} -eq 0 ]; then
  echo "· AppIcons 里还没有图，跳过"
  exit 0
fi

# 先把上一次自动生成的清掉，免得删了图之后残留
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons:CFBundleAlternateIcons" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundleAlternateIcons dict" "$PLIST"
rm -f "$DEST"/UserIcon-*.png

index=0
for f in "${files[@]}"; do
  base="$(basename "$f")"
  name="${base%.*}"
  index=$((index + 1))

  # 图标 key 只能用英文数字，中文名另外记在清单里
  key="User$index"
  out2x="$DEST/UserIcon-$key@2x.png"
  out3x="$DEST/UserIcon-$key@3x.png"

  # sips 是 macOS 自带的，不用装任何东西
  sips -s format png -z 120 120 "$f" --out "$out2x" >/dev/null
  sips -s format png -z 180 180 "$f" --out "$out3x" >/dev/null

  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleIcons:CFBundleAlternateIcons:$key dict" \
    -c "Add :CFBundleIcons:CFBundleAlternateIcons:$key:CFBundleIconFiles array" \
    -c "Add :CFBundleIcons:CFBundleAlternateIcons:$key:CFBundleIconFiles:0 string UserIcon-$key" \
    -c "Add :CFBundleIcons:CFBundleAlternateIcons:$key:UIPrerenderedIcon bool false" \
    "$PLIST"

  echo "  ✓ $name → $key"
done

# App 里要按中文名显示，写一份清单进去
MANIFEST="$DEST/UserIcons.json"
{
  echo "["
  i=0
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    name="${base%.*}"
    i=$((i + 1))
    [ $i -gt 1 ] && echo ","
    printf '  {"key": "User%s", "name": "%s"}' "$i" "$name"
  done
  echo ""
  echo "]"
} > "$MANIFEST"

echo "· 一共 $index 个图标，清单写好了"
