#!/bin/bash
# publish.sh
# 发布一条公开 Release：源码仓库打包 DMG → 本仓库（公开）创建 GitHub Release 并上传 DMG
#
# ─────────────────────────────────────────────────────────────────────
#  💡 用法：
#     ./Scripts/publish.sh v0.7.6                  # 打包 + 提交打 tag 推送 + 发布
#     ./Scripts/publish.sh v0.7.6 --dmg <path>     # 用已有的 DMG，不重新编译
#     ./Scripts/publish.sh v0.7.6 --draft          # 先发草稿，人工确认后再手动发布
#     ./Scripts/publish.sh v0.7.6 --dry-run        # 只打印将要执行的命令
#     ./Scripts/publish.sh v0.7.6 --no-git         # 不动源码仓库（不提交 / 不打 tag / 不推送）
#     ./Scripts/publish.sh v0.7.6 --yes            # 源码仓库有未提交改动时不问，直接提交
#
#  💡 说明：
#     1. 源码仓库默认在 $HOME/AuraPane，可用 AURAPANE_SRC 覆盖；
#        打包命令就是源码仓库自己的 `./build.sh --dmg --no-launch`，产物在 build/dist/。
#     2. 打包并校验完版本号之后，会把源码仓库的当前状态提交、打 tag、推送到 origin，
#        保证「发出去的包」和「库里的代码」是同一个点；--no-git 可跳过这一步。
#        有未提交改动时会先把文件列表打出来、等你按 y 确认（--yes 跳过确认）。
#     3. 发布说明优先用 Notes/<版本>.md；没有时从源码仓库 CHANGELOG.md 里截取同版本小节；
#        小节正文还留着「待补充」/ TODO 时拒绝发布。
#     4. DMG 不提交进 git（见 .gitignore），只作为 Release 附件上传。
#     5. 需要 `gh auth login` 过、且对公开仓库有写权限。
#
#  💡 发一个新版本的完整流程：
#     cd ~/AuraPane && ./Scripts/bump.sh 0.7.6 "一句话标题"   # 改版本号 + 开 CHANGELOG 条目
#     （写 CHANGELOG 正文）
#     cd ~/AuraPane-Release && ./Scripts/publish.sh v0.7.6     # 剩下的全在这条命令里
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
NO_GIT=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --dmg) DMG_PATH="${2:-}"; [ -n "$DMG_PATH" ] || { echo "❌ --dmg 需要一个路径"; exit 1; }; shift 2 ;;
        --draft) DRAFT=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-git) NO_GIT=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        v[0-9]*) VERSION="$1"; shift ;;
        *) echo "❌ 不认识的参数: $1"; exit 1 ;;
    esac
done

[ -n "$VERSION" ] || { echo "❌ 用法: ./Scripts/publish.sh v0.7.6 [--dmg <path>] [--draft] [--dry-run] [--no-git]"; exit 1; }
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
    echo "🔨 打包 Release DMG（${SOURCE_REPO}）..."
    [ -d "$SOURCE_REPO" ] || { echo "❌ 源码仓库不存在: ${SOURCE_REPO}（用 AURAPANE_SRC 指定）"; exit 1; }
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
[ "$APP_VERSION" = "${VERSION#v}" ] || { echo "❌ DMG 里的版本是 ${APP_VERSION}，与 ${VERSION} 不一致（重新打包或换 --dmg）"; exit 1; }
echo "✅ 版本校验通过: $APP_VERSION (build $APP_BUILD)"

# ── 3. 源码仓库：提交 + 打 tag + 推送（--no-git 跳过）──────────────────
if [ $NO_GIT -eq 1 ]; then
    echo "⏭️  --no-git：跳过源码仓库的提交、tag 与推送"
elif [ ! -d "$SOURCE_REPO/.git" ]; then
    echo "⏭️  $SOURCE_REPO 不是 git 仓库，跳过提交、tag 与推送"
else
    echo "🧾 对齐源码仓库（${SOURCE_REPO}）..."
    CHANGELOG_TITLE="$(grep -m1 "^## \[$VERSION\]" "$SOURCE_REPO/CHANGELOG.md" 2>/dev/null | sed 's/^## \[v[0-9.]*\] *- *//' || true)"
    [ -n "$CHANGELOG_TITLE" ] || CHANGELOG_TITLE="发布 $VERSION"
    if [ -n "$(git -C "$SOURCE_REPO" status --porcelain)" ]; then
        echo "   ⚠️  源码仓库有未提交的改动，发布会把它们一起提交："
        git -C "$SOURCE_REPO" status --short | sed 's/^/     /'
        if [ $ASSUME_YES -eq 0 ] && [ -t 0 ]; then
            printf '   继续？（不想把这些一起发就先自己 commit，或加 --no-git）[y/N] '
            read -r ANSWER
            case "$ANSWER" in
                y|Y|yes|YES) ;;
                *) echo "❌ 已取消：源码仓库没有改动"; exit 1 ;;
            esac
        fi
        run git -C "$SOURCE_REPO" add -A
        run git -C "$SOURCE_REPO" commit -q -m "release: $VERSION — $CHANGELOG_TITLE"
    else
        echo "   工作区干净，跳过提交"
    fi
    if git -C "$SOURCE_REPO" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
        echo "   tag $VERSION 已存在，跳过打 tag"
    else
        run git -C "$SOURCE_REPO" tag -a "$VERSION" -m "$CHANGELOG_TITLE"
    fi
    run git -C "$SOURCE_REPO" push origin HEAD
    run git -C "$SOURCE_REPO" push origin "$VERSION"
fi

# ── 4. 准备发布说明 ───────────────────────────────────────────────────
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
if grep -qE '待补充|TODO' "$NOTES_FILE"; then
    echo "❌ 发布说明里还留着「待补充」/ TODO：先把 CHANGELOG 的 $VERSION 小节写完（或放 Notes/$VERSION.md）"
    exit 1
fi

SIZE="$(du -h "$DMG_PATH" | cut -f1)"
# 落到临时目录，不往仓库里留 .final 文件（dry-run 也能直接看）
NOTES_FINAL="$(mktemp -t "aurapane-$VERSION-notes")"
{
    cat "$NOTES_FILE"
    printf '\n## 安装包\n\n'
    printf '| 文件 | `AuraPane-%s.dmg` |\n| --- | --- |\n' "${VERSION#v}"
    printf '| 大小 | %s |\n' "$SIZE"
    printf '| SHA-256 | `%s` |\n\n' "$SHA"
    printf '首次打开请在「应用程序」里右键 → 打开（本地签名，未走 Apple 公证）。\n'
} > "$NOTES_FINAL"

# ── 5. 创建 / 更新 Release ────────────────────────────────────────────
TITLE="AuraPane ${VERSION#v}"
if gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
    echo "🔁 $VERSION 已存在，覆盖附件与说明"
    run gh release upload "$VERSION" "$DMG_PATH" --repo "$PUBLIC_REPO" --clobber
    run gh release edit "$VERSION" --repo "$PUBLIC_REPO" --title "$TITLE" --notes-file "$NOTES_FINAL"
else
    ARGS=(gh release create "$VERSION" "$DMG_PATH" --repo "$PUBLIC_REPO" --title "$TITLE" --notes-file "$NOTES_FINAL")
    [ $DRAFT -eq 1 ] && ARGS+=(--draft) || ARGS+=(--latest)
    run "${ARGS[@]}"
fi

echo
echo "✅ 完成: https://github.com/$PUBLIC_REPO/releases/tag/$VERSION"
if [ $DRY_RUN -eq 1 ]; then
    echo "（dry-run 未上传，发布说明草稿在 ${NOTES_FINAL}）"
else
    rm -f "$NOTES_FINAL"
fi
