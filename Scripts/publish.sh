#!/bin/bash
# publish.sh
# 发布一条公开 Release：源码仓库打包 DMG → 本仓库（公开）创建 GitHub Release 并上传 DMG
#
# ─────────────────────────────────────────────────────────────────────
#  💡 用法：
#     ./Scripts/publish.sh v0.7.5                  # 自动打包 + 发布
#     ./Scripts/publish.sh v0.7.5 --dmg <path>     # 用已有的 DMG，不重新编译
#     ./Scripts/publish.sh v0.7.5 --draft          # 先发草稿，人工确认后再手动发布
#     ./Scripts/publish.sh v0.7.5 --dry-run        # 只打印将要执行的命令
#
#  💡 说明：
#     1. 源码仓库默认在 $HOME/AuraPane，可用 AURAPANE_SRC 覆盖；
#        打包命令就是源码仓库自己的 `./build.sh --dmg --no-launch`，产物在 build/dist/。
#     2. 发布说明优先用 Notes/<版本>.md；没有时从源码仓库 CHANGELOG.md 里截取同版本小节。
#     3. DMG 不提交进 git（见 .gitignore），只作为 Release 附件上传。
#     4. 需要 `gh auth login` 过、且对公开仓库有写权限。
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail
trap 'echo "🚨 发布失败（脚本第 $LINENO 行）"; exit 1' ERR

PUBLIC_REPO="${AURAPANE_PUBLIC_REPO:-8wcznkmy6b-del/AuraPane}"
SOURCE_REPO="${AURAPANE_SRC:-$HOME/AuraPane}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=""
DMG_PATH=""
DRAFT=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --dmg) DMG_PATH="${2:-}"; [ -n "$DMG_PATH" ] || { echo "❌ --dmg 需要一个路径"; exit 1; }; shift 2 ;;
        --draft) DRAFT=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        v[0-9]*) VERSION="$1"; shift ;;
        *) echo "❌ 不认识的参数: $1"; exit 1 ;;
    esac
done

[ -n "$VERSION" ] || { echo "❌ 用法: ./Scripts/publish.sh v0.7.5 [--dmg <path>] [--draft] [--dry-run]"; exit 1; }
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ 版本号要写成 v1.2.3 的形式: $VERSION"; exit 1; }

run() {
    if [ $DRY_RUN -eq 1 ]; then
        printf '   [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

echo "🚀 发布 AuraPane $VERSION → $PUBLIC_REPO"

# ── 1. 取出 DMG ───────────────────────────────────────────────────────
if [ -z "$DMG_PATH" ]; then
    echo "🔨 打包 Release DMG（$SOURCE_REPO）..."
    [ -d "$SOURCE_REPO" ] || { echo "❌ 源码仓库不存在: $SOURCE_REPO（用 AURAPANE_SRC 指定）"; exit 1; }
    run bash -c "cd '$SOURCE_REPO' && ./build.sh --dmg --no-launch"
    DMG_PATH="$SOURCE_REPO/build/dist/AuraPane-${VERSION#v}.dmg"
fi
[ -f "$DMG_PATH" ] || { echo "❌ 找不到 DMG: $DMG_PATH"; exit 1; }
echo "💿 DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# ── 2. 校验 DMG 里的 App 版本与要发的版本一致 ─────────────────────────
MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly 2>/dev/null | tail -1 | awk -F'\t' '{print $NF}')"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_POINT/AuraPane.app/Contents/Info.plist" 2>/dev/null || true)"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MOUNT_POINT/AuraPane.app/Contents/Info.plist" 2>/dev/null || true)"
hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
[ "$APP_VERSION" = "${VERSION#v}" ] || { echo "❌ DMG 里的版本是 $APP_VERSION，与 $VERSION 不一致（重新打包或换 --dmg）"; exit 1; }
echo "✅ 版本校验通过: $APP_VERSION (build $APP_BUILD)"

# ── 3. 准备发布说明 ───────────────────────────────────────────────────
NOTES_FILE="$REPO_DIR/Notes/$VERSION.md"
if [ ! -f "$NOTES_FILE" ]; then
    echo "📝 本仓库没有 Notes/$VERSION.md，从源码仓库 CHANGELOG.md 截取同名小节"
    NOTES_FILE="$(mktemp -t aurapane-notes)"
    awk -v header="## [$VERSION]" '
        index($0, header) == 1 { found = 1; next }
        found && /^## \[/ { exit }
        found { print }
    ' "$SOURCE_REPO/CHANGELOG.md" > "$NOTES_FILE"
    if ! grep -q '[^[:space:]]' "$NOTES_FILE"; then
        echo "❌ CHANGELOG.md 里没有 $VERSION 小节，请手写 Notes/$VERSION.md"
        exit 1
    fi
    # 去掉小节标题下那行「---」
    sed -i '' -e '/^---$/d' "$NOTES_FILE"
fi

SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE="$(du -h "$DMG_PATH" | cut -f1)"
{
    cat "$NOTES_FILE"
    printf '\n## 安装包\n\n'
    printf '| 文件 | `AuraPane-%s.dmg` |\n| --- | --- |\n' "${VERSION#v}"
    printf '| 大小 | %s |\n' "$SIZE"
    printf '| SHA-256 | `%s` |\n\n' "$SHA"
    printf '首次打开请在「应用程序」里右键 → 打开（本地签名，未走 Apple 公证）。\n'
} > "$NOTES_FILE.final"

# ── 4. 创建 / 更新 Release ────────────────────────────────────────────
TITLE="AuraPane ${VERSION#v}"
if gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
    echo "🔁 $VERSION 已存在，覆盖附件与说明"
    run gh release upload "$VERSION" "$DMG_PATH" --repo "$PUBLIC_REPO" --clobber
    run gh release edit "$VERSION" --repo "$PUBLIC_REPO" --title "$TITLE" --notes-file "$NOTES_FILE.final"
else
    ARGS=(gh release create "$VERSION" "$DMG_PATH" --repo "$PUBLIC_REPO" --title "$TITLE" --notes-file "$NOTES_FILE.final")
    [ $DRAFT -eq 1 ] && ARGS+=(--draft) || ARGS+=(--latest)
    run "${ARGS[@]}"
fi

echo
echo "✅ 完成: https://github.com/$PUBLIC_REPO/releases/tag/$VERSION"
if [ $DRY_RUN -eq 0 ]; then
    rm -f "$NOTES_FILE.final"
else
    echo "（dry-run 未上传，发布说明草稿保留在 $NOTES_FILE.final）"
fi
